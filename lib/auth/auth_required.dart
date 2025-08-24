import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_provider.dart';
import '../toast.dart';
import '../pages/login.dart';

/// Wrap a widget that requires authentication. If not authenticated, push login
/// and once success returns, rebuild to show protected content.
class AuthRequired extends StatefulWidget {
  final Widget child;
  const AuthRequired({super.key, required this.child});

  @override
  State<AuthRequired> createState() => _AuthRequiredState();
}

class _AuthRequiredState extends State<AuthRequired> {
  bool _checking = false;
  bool _loginRoutePushed = false; // ensure we don't push multiple times

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensure();
  }

  Future<void> _ensure() async {
    if (_checking) return;
    _checking = true;
    final auth = context.read<AuthProvider>();
    if (!auth.state.authenticated &&
        !auth.state.loading &&
        !_loginRoutePushed) {
      _loginRoutePushed = true;
      // Defer navigation until after current frame to avoid push during build
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const LoginPage(),
            settings: const RouteSettings(name: '/login'),
          ),
        );
        if (!mounted) return;
        // After returning from login, if still unauthenticated treat as failure/cancel.
        final authAfter = context.read<AuthProvider>();
        if (!authAfter.state.authenticated) {
          ToastManager().showErrorToast('auth.login_failed');
          // Leave the protected page.
          Navigator.of(context).maybePop();
        }
      });
    }
    _checking = false;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!auth.state.authenticated) {
      return Center(
        child: Text(
          '需要登录才能访问',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return widget.child;
  }
}
