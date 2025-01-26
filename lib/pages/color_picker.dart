import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class MyColorPicker extends StatefulWidget {
  final ValueChanged<Color> onColorChanged;
  final Color defaultColor;

  const MyColorPicker({super.key, required this.onColorChanged, defaultColor})
      : defaultColor = defaultColor ?? const Color(0xFFFF0000);

  @override
  MyColorState createState() => MyColorState();
}

class MyColorState extends State<MyColorPicker> {
  bool lightTheme = true;
  late Color currentColor;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    currentColor = widget.defaultColor;
  }

  void changeColor(Color color) {
    setState(() => currentColor = color);
    if (color.a < 1.0) {
      color = color.withValues(alpha: 1.0);
    }
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      widget.onColorChanged(color);
    });
  }

  void showColorPickerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a color').tr(),
          content: SingleChildScrollView(
            child: HueRingPicker(
              pickerColor: currentColor,
              onColorChanged: changeColor,
              displayThumbColor: true,
              portraitOnly: true,
              enableAlpha: false,
              hueRingStrokeWidth: 30,
              colorPickerHeight: 250,
              pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(40)),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel').tr(),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('OK').tr(),
              onPressed: () {
                changeColor(currentColor);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final foregroundColor = useWhiteForeground(currentColor) ? Colors.white : Colors.black;
    return Column(
      children: <Widget>[
        ElevatedButton(
          onPressed: () => showColorPickerDialog(context),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.all<Color>(currentColor),
          ),
          child: Text('Pick color', style: TextStyle(color: foregroundColor)).tr(),
        ),
      ],
    );
  }
}