import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
// Casdoor SDK 使用被封装在 AuthService 内
// auth_service 仅在 provider 内部使用
import 'package:dalimaster/auth/auth_provider.dart';
import 'package:provider/provider.dart';
import 'dart:async';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'auth.login'.tr(),
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Auto-start login after first frame to ensure context is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_started) return;
      _started = true;
      _startLogin();
    });
  }

  Future<void> _startLogin() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      // 调用 SDK 展示登录并返回 code
      final provider = context.read<AuthProvider>();
      await provider.login();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('auth.login'.tr())),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_loading) const CircularProgressIndicator(),
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child:
                    Text('auth.opening_login'.tr(), style: Theme.of(context).textTheme.bodyMedium),
              ),
            if (_error != null) ...[
              Text('auth.login_failed'.tr(),
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                _localizedLoginError(_error!),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _startLogin,
                child: Text('auth.login').tr(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _localizedLoginError(String message) {
    final m = message.toLowerCase();
    if (m.contains('empty authorization code') || m.contains('cancelled')) {
      return 'auth.error.cancelled'.tr();
    }
    if (m.contains('token exchange failed') || m.contains('missing access_token')) {
      return 'auth.error.token_exchange_failed'.tr();
    }
    if (m.contains('unexpected token response format')) {
      return 'auth.error.unexpected_token_format'.tr();
    }
    if (m.contains('get user info failed')) {
      return 'auth.error.userinfo_failed'.tr();
    }
    if (m.contains('unexpected user info format')) {
      return 'auth.error.unexpected_userinfo_format'.tr();
    }
    return 'auth.error.unknown'.tr(namedArgs: {'reason': message});
  }
}
