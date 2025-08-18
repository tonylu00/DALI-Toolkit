import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../dali/addr.dart';
import '../widgets/short_address_manager.dart';

class ShortAddressManagerPage extends StatelessWidget {
  final DaliAddr daliAddr;
  const ShortAddressManagerPage({super.key, required this.daliAddr});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('short_addr_manager.title').tr(),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'short_addr_manager.scan'.tr(),
            onPressed: () {
              // 访问内部 state 触发扫描: 使用 GlobalKey 更优, 这里给出简单回调方式
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ShortAddressManager(
          daliAddr: daliAddr,
          onScanResult: (list) {
            // 可在此处广播或处理扫描结果
          },
        ),
      ),
    );
  }
}
