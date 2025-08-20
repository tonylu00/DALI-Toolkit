import 'dart:convert';
import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dalimaster/auth/casdoor_config.dart';

/// Auth token model
class AuthTokens {
  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final DateTime? expiresAt;

  AuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken,
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['accessToken'],
        refreshToken: json['refreshToken'],
        idToken: json['idToken'],
        expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
      );
}

class UserProfile {
  final Map<String, dynamic> raw;
  UserProfile(this.raw);
  String? get username => raw['preferred_username'] ?? raw['name'];
  String? get email => raw['email'];
}

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_tokens';

  final Casdoor _casdoor = Casdoor(config: casdoorConfig);

  Future<(AuthTokens, UserProfile)> login() async {
    final rawResult = await _casdoor.show();
    // SDK 在 iOS 上可能返回完整回调 URL: scheme://callback?code=xxx&state=yyy
    // 需要从中提取 code 参数；若仅返回 code 则直接使用
    String code;
    if (rawResult.contains('://')) {
      try {
        final uri = Uri.parse(rawResult);
        code = uri.queryParameters['code'] ?? '';
      } catch (_) {
        code = rawResult; // 解析失败时退回原始
      }
    } else {
      code = rawResult;
    }
    if (code.isEmpty) {
      throw Exception('Login cancelled: empty authorization code.');
    }

    final response = await _casdoor.requestOauthAccessToken(code);
    if (response.statusCode != 200) {
      throw Exception('Token exchange failed: ${response.statusCode} ${response.body}');
    }
    final dynamic bodyRaw = jsonDecode(response.body);
    if (bodyRaw is! Map<String, dynamic>) {
      throw Exception('Unexpected token response format');
    }
    final body = bodyRaw;

    final accessToken = body['access_token'] as String?;
    if (accessToken == null) {
      // 返回可能是错误 JSON: {"error":"...","error_description":"..."}
      throw Exception('Token exchange missing access_token: ${response.body}');
    }
    final refreshToken = body['refresh_token'] as String?;
    final idToken = body['id_token'] as String?;

    int? expiresIn;
    final expiresInRaw = body['expires_in'];
    if (expiresInRaw is int) {
      expiresIn = expiresInRaw;
    } else if (expiresInRaw is String) {
      expiresIn = int.tryParse(expiresInRaw);
    }
    final DateTime? expiresAt =
        expiresIn != null ? DateTime.now().add(Duration(seconds: expiresIn)) : null;

    final userInfoResp = await _casdoor.getUserInfo(accessToken);
    if (userInfoResp.statusCode != 200) {
      throw Exception('Get user info failed: ${userInfoResp.statusCode} ${userInfoResp.body}');
    }
    final dynamic userInfoRaw = jsonDecode(userInfoResp.body);
    if (userInfoRaw is! Map<String, dynamic>) {
      throw Exception('Unexpected user info format');
    }

    final tokens = AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: idToken,
      expiresAt: expiresAt,
    );
    await _persistTokens(tokens);

    return (tokens, UserProfile(userInfoRaw));
  }

  Future<UserProfile?> getCachedUser() async {
    final tokens = await loadTokens();
    if (tokens == null) return null;
    if (tokens.expiresAt != null && DateTime.now().isAfter(tokens.expiresAt!)) {
      // try refresh
      final refreshed = await refreshTokens(tokens);
      if (refreshed == null) return null;
      return await fetchUser(refreshed.accessToken);
    }
    return await fetchUser(tokens.accessToken);
  }

  Future<UserProfile?> fetchUser(String accessToken) async {
    final resp = await _casdoor.getUserInfo(accessToken);
    if (resp.statusCode == 200) {
      return UserProfile(jsonDecode(resp.body));
    }
    return null;
  }

  Future<AuthTokens?> refreshTokens(AuthTokens current) async {
    if (current.refreshToken == null) return null;
    final resp = await _casdoor.refreshToken(current.refreshToken!, null);
    if (resp.statusCode == 200) {
      final dynamic raw = jsonDecode(resp.body);
      if (raw is! Map<String, dynamic>) return null;
      final body = raw;
      final accessToken = body['access_token'] as String?;
      if (accessToken == null) return null; // 刷新失败
      final refreshToken = (body['refresh_token'] as String?) ?? current.refreshToken;
      int? expiresIn;
      final expiresInRaw = body['expires_in'];
      if (expiresInRaw is int) {
        expiresIn = expiresInRaw;
      } else if (expiresInRaw is String) {
        expiresIn = int.tryParse(expiresInRaw);
      }
      final expiresAt = expiresIn != null ? DateTime.now().add(Duration(seconds: expiresIn)) : null;
      final updated = AuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        idToken: (body['id_token'] as String?) ?? current.idToken,
        expiresAt: expiresAt,
      );
      await _persistTokens(updated);
      return updated;
    }
    return null;
  }

  /// Decode a JWT-like token (access or id token) using the SDK helper.
  /// Returns a map of claims or null on error.
  Future<Map<String, dynamic>?> decodeToken(String token) async {
    try {
      final dynamic decoded = _casdoor.decodedToken(token);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout({bool revoke = false}) async {
    final tokens = await loadTokens();
    if (tokens != null && revoke && tokens.idToken != null) {
      await _casdoor.tokenLogout(tokens.idToken!, null, 'logout');
    }
    await _clearTokens();
  }

  Future<void> _persistTokens(AuthTokens tokens) async {
    await _storage.write(key: _tokenKey, value: jsonEncode(tokens.toJson()));
  }

  Future<AuthTokens?> loadTokens() async {
    final data = await _storage.read(key: _tokenKey);
    if (data == null) return null;
    return AuthTokens.fromJson(jsonDecode(data));
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: _tokenKey);
  }
}
