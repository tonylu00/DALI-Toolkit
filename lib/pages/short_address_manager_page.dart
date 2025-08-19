import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../dali/addr.dart';
import '../widgets/short_address_manager.dart';

class ShortAddressManagerPage extends StatelessWidget {
  final DaliAddr daliAddr;
  final bool embedded;
  const ShortAddressManagerPage({super.key, required this.daliAddr, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(12.0),
      child: ShortAddressManager(
        daliAddr: daliAddr,
        onScanResult: (list) {
          // 可在此处广播或处理扫描结果
        },
      ),
    );
    if (embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('short_addr_manager.title').tr(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'short_addr_manager.scan'.tr(),
            onPressed: () {},
          )
        ],
      ),
      body: content,
    );
  }
}
