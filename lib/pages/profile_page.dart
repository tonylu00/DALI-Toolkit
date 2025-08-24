import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth/auth_provider.dart';
import 'base_scaffold.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show File;

class ProfilePage extends StatelessWidget {
  final bool embedded;
  const ProfilePage({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.state.user ?? {};
    final displayName = user['preferred_username'] ?? user['name'] ?? 'User';
    final displayEmail = user['email'] ?? '';
    final avatarFile = user['avatar_file'] as String?;
    final avatarUrl = user['avatar'] ?? user['avatarUrl'] ?? user['picture'];

    final avatar = () {
      // Web 环境不使用本地文件头像，避免 dart:io 在 Web 运行时错误
      if (!kIsWeb && avatarFile != null && avatarFile.isNotEmpty) {
        return CircleAvatar(
          radius: 40,
          backgroundImage: Image.file(
            File(avatarFile),
            fit: BoxFit.cover,
          ).image,
        );
      } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
        return CircleAvatar(
          radius: 40,
          backgroundImage: NetworkImage(avatarUrl),
        );
      } else {
        return CircleAvatar(
          radius: 40,
          child:
              Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U'),
        );
      }
    }();

    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar,
          const SizedBox(height: 16),
          Text(
            displayName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (displayEmail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              displayEmail,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 24),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('用户名'),
              subtitle: Text(displayName),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            child: ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('邮箱'),
              subtitle: Text(displayEmail.isNotEmpty ? displayEmail : '未绑定'),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('认证状态'),
              subtitle: Text(auth.state.authenticated ? '已登录' : '未登录'),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
            onPressed: auth.state.authenticated
                ? () async {
                    await auth.logout();
                    if (context.mounted) {
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/login', (route) => false);
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 48),
            ),
          ),
        ],
      ),
    );

    if (embedded) return content;
    return BaseScaffold(currentPage: 'Profile', body: content);
  }
}
