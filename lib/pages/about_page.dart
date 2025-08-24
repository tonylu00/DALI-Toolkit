import 'package:flutter/material.dart';
import 'base_scaffold.dart';
import 'package:flutter/services.dart';
import '/main.dart';
import 'package:easy_localization/easy_localization.dart';

class AboutPage extends StatelessWidget {
  final bool embedded;
  const AboutPage({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          Text('about.title'.tr(),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text('about.version'.tr(namedArgs: {'version': '1.0.0'})),
          const SizedBox(height: 8),
          Text('about.description'.tr()),
          const SizedBox(height: 16),
          Text('about.copyright'
              .tr(namedArgs: {'year': DateTime.now().year.toString()})),
          const SizedBox(height: 24),
          Text('about.anonymous_id.title'.tr(),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          GestureDetector(
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: anonymousId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('about.copied'.tr())),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: SelectableText(
                anonymousId.isEmpty ? '-' : anonymousId,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
    if (embedded) return content;
    return BaseScaffold(currentPage: 'About', body: content);
  }
}
