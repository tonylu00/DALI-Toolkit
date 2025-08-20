import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../toast.dart';
import '/dali/dali.dart';
import '/connection/manager.dart';
import 'base_scaffold.dart';

// Import the new widget components
import '../widgets/widgets.dart';
import '../utils/broadcast_read_prefs.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, this.embedded = false});
  final String title;
  final bool embedded; // 大尺寸模式由外部 BaseScaffold 承载

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {
  bool isDrawerOpen = false;
  double brightness = 50;
  Color color = Colors.red;
  double colorTemperature = 2700;
  List<bool> groupCheckboxes = List.generate(16, (_) => false);

  @override
  void initState() {
    super.initState();
    Dali.instance.addr!.selectedDeviceStream.listen((address) {
      setState(() {});
    });
    BroadcastReadPrefs.instance.addListener(_onPrefsChanged);
    BroadcastReadPrefs.instance.load();
    ToastManager().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ToastManager().showInfoToast('Initialization complete');
    });
  }

  @override
  void dispose() {
    BroadcastReadPrefs.instance.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  bool _checkDeviceConnection() {
    return ConnectionManager.instance.ensureReadyForOperation();
  }

  Future<void> _readBrightness() async {
    if (!_checkDeviceConnection()) return;
    int? bright = await Dali.instance.base!.getBright(Dali.instance.base!.selectedAddress);
    if (bright == null || bright < 0 || bright > 254) {
      return;
    }
    setState(() {
      brightness = bright.toDouble();
    });
  }

  Future<void> _readColor() async {
    if (!_checkDeviceConnection()) return;
    final colorRGB = await Dali.instance.dt8!.getColourRGB(Dali.instance.base!.selectedAddress);
    if (colorRGB.isEmpty) {
      return;
    }
    debugPrint('Color: $colorRGB');
    final colorObj = Color((0xFF << 24) + (colorRGB[0] << 16) + (colorRGB[1] << 8) + colorRGB[2]);
    setState(() {
      color = colorObj;
    });
  }

  Future<void> _readColorTemperature() async {
    if (!_checkDeviceConnection()) return;
    int colorTemp =
        await Dali.instance.dt8!.getColorTemperature(Dali.instance.base!.selectedAddress);
    if (colorTemp < 2700) {
      colorTemp = 2700;
    }
    if (colorTemp > 6500) {
      colorTemp = 6500;
    }
    setState(() {
      colorTemperature = colorTemp.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selAddr = Dali.instance.base!.selectedAddress;
    final allowBroadcast = BroadcastReadPrefs.instance.allow;
    final bool isReadable = selAddr <= 63 || allowBroadcast; // 普通读取条件
    final bool canReadGroup = selAddr <= 63 || allowBroadcast; // 组读取同条件 (地址>63 禁止)
    final content = Row(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Device Status (disable tap in embedded ultra-wide layout)
                    DeviceStatusWidget(clickable: !widget.embedded),

                    // Device Control Buttons
                    const DeviceControlButtonsWidget(),

                    // Read Operation Buttons
                    ReadOperationButtonsWidget(
                      isReadable: isReadable,
                      onReadBrightness: _readBrightness,
                      onReadColorTemperature: _readColorTemperature,
                      onReadColor: _readColor,
                    ),

                    // Brightness Control
                    BrightnessControlWidget(
                      brightness: brightness,
                      isReadable: isReadable,
                      onBrightnessChanged: (value) {
                        setState(() {
                          brightness = value;
                        });
                      },
                    ),

                    // Color Temperature Control
                    ColorTemperatureControlWidget(
                      colorTemperature: colorTemperature,
                      isReadable: isReadable,
                      onColorTemperatureChanged: (value) {
                        setState(() {
                          colorTemperature = value;
                        });
                      },
                    ),

                    // Color Control
                    ColorControlWidget(
                      color: color,
                      isReadable: isReadable,
                      onColorChanged: (newColor) {
                        setState(() {
                          color = newColor;
                        });
                      },
                    ),

                    // Group Control
                    GroupControlWidget(
                      groupCheckboxes: groupCheckboxes,
                      canRead: canReadGroup,
                      onGroupCheckboxesChanged: (newCheckboxes) {
                        setState(() {
                          groupCheckboxes = newCheckboxes;
                        });
                      },
                    ),

                    // Toast Test Buttons (only in debug)
                    if (kDebugMode) const ToastTestButtonsWidget(),

                    // Bottom spacing
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (widget.embedded) return content; // 嵌入模式返回纯内容
    return BaseScaffold(currentPage: 'Home', body: content);
  }
}
