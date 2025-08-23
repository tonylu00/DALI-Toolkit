import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:dalimaster/dali/log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class AuthState {
  final bool loading;
  final bool authenticated;
  final Map<String, dynamic>? user;
  final DateTime? expiresAt;

  const AuthState({
    this.loading = false,
    this.authenticated = false,
    this.user,
    this.expiresAt,
  });

  AuthState copyWith({
    bool? loading,
    bool? authenticated,
    Map<String, dynamic>? user,
    DateTime? expiresAt,
  }) =>
      AuthState(
        loading: loading ?? this.loading,
        authenticated: authenticated ?? this.authenticated,
        user: user ?? this.user,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

class AuthProvider extends ChangeNotifier {
  final AuthService _service = AuthService();
  AuthState _state = const AuthState();
  AuthState get state => _state;
  AuthTokens? _tokens;
  AuthTokens? get tokens => _tokens;
  Timer? _refreshTimer;

  Future<void> init() async {
    _setState(_state.copyWith(loading: true));
    // load cached simple profile for immediate UI feedback
    final prefs = await SharedPreferences.getInstance();
    final cachedName = prefs.getString('auth_cached_name');
    final cachedEmail = prefs.getString('auth_cached_email');
    final cachedAvatar = prefs.getString('auth_cached_avatar');
    final cachedAvatarFile = prefs.getString('auth_cached_avatar_file');
    if (cachedName != null ||
        cachedEmail != null ||
        cachedAvatar != null ||
        cachedAvatarFile != null) {
      _setState(_state.copyWith(user: {
        if (cachedName != null) 'name': cachedName,
        if (cachedEmail != null) 'email': cachedEmail,
        if (cachedAvatar != null) 'avatar': cachedAvatar,
        if (cachedAvatarFile != null) 'avatar_file': cachedAvatarFile,
      }));
    }

    final user = await _service.getCachedUser();
    if (user != null) {
      final tokens = await _service.loadTokens();
      // normalize user map for consistent UI keys
      var normalized = _normalizeUserRaw(user.raw);
      _setState(_state.copyWith(
        loading: false,
        authenticated: true,
        user: normalized,
        expiresAt: tokens?.expiresAt,
      ));
      // persist simple profile cache (only non-empty values)
      final prefs2 = await SharedPreferences.getInstance();
      // attempt to fill missing fields from token claims
      normalized = await _fillFromTokenIfNeeded(normalized, prefs2);
      final String? nName = (normalized['name'] is String) ? normalized['name'] as String : null;
      final String? nEmail = (normalized['email'] is String) ? normalized['email'] as String : null;
      final String? nAvatar =
          (normalized['avatar'] is String) ? normalized['avatar'] as String : null;
      if (nName != null && nName.isNotEmpty) {
        await prefs2.setString('auth_cached_name', nName);
      }
      if (nEmail != null && nEmail.isNotEmpty) {
        await prefs2.setString('auth_cached_email', nEmail);
      }
      if (nAvatar != null && nAvatar.isNotEmpty) {
        await prefs2.setString('auth_cached_avatar', nAvatar);
      }
      // avatar download handled above when _nAvatar is present
      _scheduleRefresh(tokens?.expiresAt);
    } else {
      _setState(_state.copyWith(loading: false));
    }
    // run cleanup to remove stale avatar files
    await _cleanupAvatarCache();
  }

  Future<void> login() async {
    _setState(_state.copyWith(loading: true));
    final (tokens, user) = await _service.login();
    var normalized = _normalizeUserRaw(user.raw);
    // try to augment normalized with token claims
    final SharedPreferences prefsForAll = await SharedPreferences.getInstance();
    normalized = await _fillFromTokenIfNeeded(normalized, prefsForAll);
    _setState(_state.copyWith(
      loading: false,
      authenticated: true,
      user: normalized,
      expiresAt: tokens.expiresAt,
    ));
    // 缓存登录时间戳（毫秒）
    await prefsForAll.setInt('auth_login_time', DateTime.now().millisecondsSinceEpoch);
    // debug: print normalized user for troubleshooting
    try {
      DaliLog.instance.debugLog('AuthProvider.login normalized user: ${normalized.toString()}');
    } catch (_) {}
    _tokens = tokens;
    _scheduleRefresh(tokens.expiresAt);
    // cache simple profile
    final String? lName = (normalized['name'] is String) ? normalized['name'] as String : null;
    final String? lEmail = (normalized['email'] is String) ? normalized['email'] as String : null;
    final String? lAvatar =
        (normalized['avatar'] is String) ? normalized['avatar'] as String : null;
    if (lName != null && lName.isNotEmpty) await prefsForAll.setString('auth_cached_name', lName);
    if (lEmail != null && lEmail.isNotEmpty)
      await prefsForAll.setString('auth_cached_email', lEmail);
    if (lAvatar != null && lAvatar.isNotEmpty) {
      await prefsForAll.setString('auth_cached_avatar', lAvatar);
      if (lAvatar.startsWith('http')) {
        final local = await _downloadAvatarToFile(lAvatar);
        if (local != null) {
          await prefsForAll.setString('auth_cached_avatar_file', local.path);
          final newUser = Map<String, dynamic>.from(_state.user ?? {});
          newUser['avatar_file'] = local.path;
          _setState(_state.copyWith(user: newUser));
        }
      }
    }
  }

  Map<String, dynamic> _normalizeUserRaw(Map<String, dynamic> raw) {
    String? tryGet(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    // search root first
    String name =
        tryGet(raw, ['preferred_username', 'name', 'username', 'displayName', 'display_name']) ??
            '';
    String? email = tryGet(raw, ['email', 'preferred_email', 'mail', 'user_email']);
    String? avatar =
        tryGet(raw, ['avatar', 'picture', 'avatarUrl', 'pictureUrl', 'profile_picture']);

    // if not found, check common nested containers
    if (name.isEmpty && raw['data'] is Map) {
      final d = Map<String, dynamic>.from(raw['data'] as Map);
      name = tryGet(d, ['preferred_username', 'name', 'username', 'displayName', 'display_name']) ??
          name;
      email ??= tryGet(d, ['email', 'preferred_email', 'mail', 'user_email']);
      avatar ??= tryGet(d, ['avatar', 'picture', 'avatarUrl', 'pictureUrl', 'profile_picture']);
    }
    if (name.isEmpty && raw['user'] is Map) {
      final d = Map<String, dynamic>.from(raw['user'] as Map);
      name = tryGet(d, ['preferred_username', 'name', 'username', 'displayName', 'display_name']) ??
          name;
      email ??= tryGet(d, ['email', 'preferred_email', 'mail', 'user_email']);
      avatar ??= tryGet(d, ['avatar', 'picture', 'avatarUrl', 'pictureUrl', 'profile_picture']);
    }

    // debug: if still empty name, print raw to help troubleshooting
    if (name.isEmpty) {
      try {
        DaliLog.instance
            .debugLog('AuthProvider._normalizeUserRaw empty name, raw: ${raw.toString()}');
      } catch (_) {}
    }

    final normalized = Map<String, dynamic>.from(raw);
    normalized['name'] = name;
    if (email != null) normalized['email'] = email;
    if (avatar != null) normalized['avatar'] = avatar;
    // also keep preferred_username for UI checks
    if (!normalized.containsKey('preferred_username') && name.isNotEmpty)
      normalized['preferred_username'] = name;
    return normalized;
  }

  // If normalized is missing name/email/avatar, try to decode token claims and fill them.
  Future<Map<String, dynamic>> _fillFromTokenIfNeeded(
      Map<String, dynamic> normalized, SharedPreferences prefs) async {
    final String? currentName =
        (normalized['name'] is String) ? normalized['name'] as String : null;
    final String? currentEmail =
        (normalized['email'] is String) ? normalized['email'] as String : null;
    if ((currentName != null && currentName.isNotEmpty) ||
        (currentEmail != null && currentEmail.isNotEmpty)) {
      return normalized; // nothing to fill
    }
    try {
      final tokens = await _service.loadTokens();
      if (tokens == null) return normalized;
      final Map<String, dynamic>? claims = await _service.decodeToken(tokens.accessToken);
      if (claims == null) return normalized;
      DaliLog.instance
          .debugLog('AuthProvider._fillFromTokenIfNeeded decoded claims: ${claims.toString()}');
      final String? cName =
          (claims['name'] ?? claims['preferred_username'] ?? claims['username'])?.toString();
      final String? cEmail = (claims['email'])?.toString();
      final String? cAvatar = (claims['avatar'] ?? claims['picture'])?.toString();
      if ((normalized['name'] == null || (normalized['name'] as String).isEmpty) &&
          cName != null &&
          cName.isNotEmpty) {
        normalized['name'] = cName;
        await prefs.setString('auth_cached_name', cName);
      }
      if ((normalized['email'] == null || (normalized['email'] as String).isEmpty) &&
          cEmail != null &&
          cEmail.isNotEmpty) {
        normalized['email'] = cEmail;
        await prefs.setString('auth_cached_email', cEmail);
      }
      if ((normalized['avatar'] == null || (normalized['avatar'] as String).isEmpty) &&
          cAvatar != null &&
          cAvatar.isNotEmpty) {
        normalized['avatar'] = cAvatar;
        await prefs.setString('auth_cached_avatar', cAvatar);
        if (cAvatar.startsWith('http')) {
          final local = await _downloadAvatarToFile(cAvatar);
          if (local != null) {
            await prefs.setString('auth_cached_avatar_file', local.path);
            normalized['avatar_file'] = local.path;
          }
        }
      }
    } catch (_) {}
    return normalized;
  }

  Future<void> logout({bool revoke = false}) async {
    _setState(_state.copyWith(loading: true));
    await _service.logout(revoke: revoke);
    _refreshTimer?.cancel();
    // clear cached profile and delete avatar file if exists
    final prefs = await SharedPreferences.getInstance();
    final avatarFilePath = prefs.getString('auth_cached_avatar_file');
    if (avatarFilePath != null) {
      try {
        final f = File(avatarFilePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    // also remove from cache index
    final list = prefs.getStringList('auth_cached_avatar_files') ?? <String>[];
    list.remove(avatarFilePath);
    await prefs.setStringList('auth_cached_avatar_files', list);
    await prefs.remove('auth_cached_name');
    await prefs.remove('auth_cached_email');
    await prefs.remove('auth_cached_avatar');
    await prefs.remove('auth_cached_avatar_file');
    _setState(const AuthState(loading: false));
  }

  Future<File?> _downloadAvatarToFile(String url) async {
    try {
      final uri = Uri.parse(url);
      final resp = await http.get(uri);
      if (resp.statusCode != 200) return null;
      final bytes = resp.bodyBytes;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      // update cache index and cleanup
      await _registerAvatarFile(file.path);
      await _cleanupAvatarCache();
      return file;
    } catch (_) {
      return null;
    }
  }

  // keep list of cached avatar files and clean old/extra ones
  Future<void> _registerAvatarFile(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('auth_cached_avatar_files') ?? <String>[];
    // add to front
    list.remove(path);
    list.insert(0, path);
    await prefs.setStringList('auth_cached_avatar_files', list);
  }

  Future<void> _cleanupAvatarCache({int keep = 3, int ttlDays = 14}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('auth_cached_avatar_files') ?? <String>[];
    final now = DateTime.now();
    final toKeep = <String>[];
    final toDelete = <String>[];
    for (final p in list) {
      try {
        final f = File(p);
        if (!await f.exists()) continue;
        final stat = await f.stat();
        final age = now.difference(stat.modified).inDays;
        if (age > ttlDays) {
          toDelete.add(p);
        } else {
          toKeep.add(p);
        }
      } catch (_) {}
    }
    // if too many, drop older ones
    if (toKeep.length > keep) {
      toDelete.addAll(toKeep.sublist(keep));
      toKeep.removeRange(keep, toKeep.length);
    }
    for (final p in toDelete) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
        // also remove from prefs
        list.remove(p);
      } catch (_) {}
    }
    // persist updated list
    await prefs.setStringList(
        'auth_cached_avatar_files', list.where((p) => File(p).existsSync()).toList());
  }

  void _scheduleRefresh(DateTime? expiresAt) {
    _refreshTimer?.cancel();
    if (expiresAt == null) return;
    final secondsLeft = expiresAt.difference(DateTime.now()).inSeconds;
    // 刷新阈值：到期前 60 秒尝试刷新
    final triggerIn = (secondsLeft - 60).clamp(5, secondsLeft).toInt();
    _refreshTimer = Timer(Duration(seconds: triggerIn), () async {
      final tokens = await _service.loadTokens();
      if (tokens == null) return;
      final refreshed = await _service.refreshTokens(tokens);
      if (refreshed != null) {
        _tokens = refreshed;
        _setState(_state.copyWith(expiresAt: refreshed.expiresAt));
        _scheduleRefresh(refreshed.expiresAt);
      }
    });
  }

  void _setState(AuthState newState) {
    _state = newState;
    notifyListeners();
  }

  /// 检查离线登录状态，超过15天且无法刷新 token 则强制退出登录
  Future<void> checkOfflineLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final loginTimeMs = prefs.getInt('auth_login_time');
    if (loginTimeMs == null) return;
    final loginTime = DateTime.fromMillisecondsSinceEpoch(loginTimeMs);
    final now = DateTime.now();
    final offlineDays = now.difference(loginTime).inDays;
    // 仅在超过15天时才检测
    if (offlineDays < 15) return;
    // 尝试刷新 token，失败则视为无网
    final tokens = await _service.loadTokens();
    if (tokens == null) {
      await logout();
      return;
    }
    try {
      final refreshed = await _service.refreshTokens(tokens);
      if (refreshed == null) {
        await logout();
      }
    } catch (_) {
      await logout();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
