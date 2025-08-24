import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

class RenameDeviceDialog extends StatefulWidget {
  final String currentName;
  final String connectedDeviceId;
  final Function(Uint8List) sendCommand;

  const RenameDeviceDialog({
    super.key,
    required this.currentName,
    required this.connectedDeviceId,
    required this.sendCommand,
  });

  static void show(
    BuildContext context, {
    required String currentName,
    required String connectedDeviceId,
    required Function(Uint8List) sendCommand,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return RenameDeviceDialog(
          currentName: currentName,
          connectedDeviceId: connectedDeviceId,
          sendCommand: sendCommand,
        );
      },
    );
  }

  @override
  State<RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<RenameDeviceDialog> {
  late TextEditingController controller;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _validateInput(String text) {
    setState(() {
      if (text.length > 20) {
        errorMessage = 'rename.device_name_too_long'.tr();
        controller.text = text.substring(0, 20);
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
      } else if (!RegExp(r'^[\x00-\x7F]+$').hasMatch(text)) {
        errorMessage = 'Only ASCII characters are allowed'.tr();
        controller.text = text.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
      } else {
        errorMessage = null;
      }
    });
  }

  Future<void> _handleRename() async {
    if (controller.text.isEmpty) {
      setState(() {
        errorMessage = 'validation.device_name_required'.tr();
      });
      controller.text =
          'DALInspector_${widget.connectedDeviceId.substring(widget.connectedDeviceId.length - 6)}';
      return;
    } else if (controller.text.length > 20 ||
        !RegExp(r'^[\x00-\x7F]+$').hasMatch(controller.text)) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('deviceName', controller.text);
      widget.sendCommand(
          Uint8List.fromList('AT+NAME=${controller.text}\r\n'.codeUnits));

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        errorMessage = 'rename.save_failed'.tr();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('rename.device_title').tr(),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'rename.enter_new_name'.tr(),
              errorText: errorMessage,
            ),
            onChanged: _validateInput,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('common.cancel').tr(),
        ),
        TextButton(
          onPressed: _handleRename,
          child: const Text('common.ok').tr(),
        ),
      ],
    );
  }
}
