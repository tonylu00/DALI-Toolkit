import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../toast.dart';
import '/dali/dali.dart';
import 'base_scaffold.dart';

// Import the new widget components
import '../widgets/widgets.dart';
import '../utils/broadcast_read_prefs.dart';
import '../utils/device_info_store.dart';

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
  StreamSubscription<dynamic>? _selectedDeviceSub;

  @override
  void initState() {
    super.initState();
    _selectedDeviceSub = Dali.instance.addr!.selectedDeviceStream.listen((address) {
      if (!mounted) return;
      setState(() {});
    });
    // Kick store to listen and optionally refresh current selection
    final sel = Dali.instance.base!.selectedAddress;
    DeviceInfoStore.instance.refresh(sel, silent: true);
    BroadcastReadPrefs.instance.addListener(_onPrefsChanged);
    BroadcastReadPrefs.instance.load();
    ToastManager().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ToastManager().showInfoToast('init.complete');
    });
  }

  @override
  void dispose() {
    _selectedDeviceSub?.cancel();
    BroadcastReadPrefs.instance.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
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

                    // Status bits
                    const StatusBitsWidget(),

                    // Device Control Buttons
                    const DeviceControlButtonsWidget(),

                    // Removed standalone read operation buttons (refresh now only via individual sections)

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

                    // Fade controls (time & rate)
                    const FadeControlWidget(),

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

                    // Scene goto (0..15) and editor entry
                    const SceneGotoWidget(),

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
