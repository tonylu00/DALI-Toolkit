import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../dali/dali.dart';

class SceneGotoWidget extends StatelessWidget {
  const SceneGotoWidget({super.key, this.showEditorButton = true});

  final bool showEditorButton;

  Future<void> _go(int sc) async {
    final a = Dali.instance.base!.selectedAddress;
    await Dali.instance.base!.toScene(a, sc);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('scene.goto.title'.tr(), style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (showEditorButton)
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/sceneEditor'),
                    icon: const Icon(Icons.edit),
                    label: Text('scene.edit'.tr()),
                  )
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(16, (i) => _SceneButton(i, _go)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneButton extends StatelessWidget {
  final int idx;
  final Future<void> Function(int) onTap;
  const _SceneButton(this.idx, this.onTap);
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => onTap(idx),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
      child: Text('S$idx'),
    );
  }
}
