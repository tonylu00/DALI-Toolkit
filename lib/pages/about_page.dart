import 'package:flutter/material.dart';
import 'base_scaffold.dart';

class AboutPage extends StatelessWidget {
  final bool embedded;
  const AboutPage({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text('关于', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text('版本: 1.0.0'),
          const SizedBox(height: 8),
          Text('本工具用于 DALI 设备调试与控制。'),
          const SizedBox(height: 16),
          Text('版权 © 2025 DALI Toolkit'),
        ],
      ),
    );
    if (embedded) return content;
    return BaseScaffold(currentPage: 'About', body: content);
  }
}
