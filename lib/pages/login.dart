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
      Navigator.pop(context, {
        'tokens': provider.tokens?.toJson(),
        'user': provider.state.user,
      });
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
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    Text(_error!,
                        style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton(
                    onPressed: _startLogin,
                    child: Text('auth.login').tr(),
                  ),
                ],
              ),
      ),
    );
  }
}
