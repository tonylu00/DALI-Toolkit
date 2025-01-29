import 'dart:async';

import 'package:dalimaster/pages/color_picker.dart';
import 'package:flutter/material.dart';
import '../dali/color.dart';
import '../dali/log.dart';
import '../toast.dart';
import '../utils/colour_track_shape.dart';
import '/dali/dali.dart';
import '/connection/connection.dart';
import '/connection/manager.dart';
import 'base_scaffold.dart';
import 'package:easy_localization/easy_localization.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SingleTickerProviderStateMixin {
  bool isDrawerOpen = false;
  double brightness = 50;
  Color color = Colors.red;
  double colorTemperature = 2700;
  Connection connection = ConnectionManager.instance.connection;
  Timer? _debounce;
  List<bool> groupCheckboxes = List.generate(16, (_) => false);

  @override
  void initState() {
    super.initState();
    Dali.instance.addr!.selectedDeviceStream.listen((address) {
      setState(() {});
    });
    ToastManager().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ToastManager().showInfoToast('Initialization complete');
    });
  }

  bool _checkDeviceConnection() {
    if (connection.isDeviceConnected() == false) {
      ToastManager().showErrorToast('Device not connected');
      return false;
    }
    return true;
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

  Future<void> _setColor(Color colorNew) async {
    final colorRGB = DaliColor.toIntList(colorNew);
    setState(() {
      color = colorNew;
    });
    if (!_checkDeviceConnection()) return;
    Dali.instance.dt8!.setColourRGB(Dali.instance.base!.selectedAddress, colorRGB[1], colorRGB[2], colorRGB[3]);
  }

  Future<void> _readColorTemperature() async {
    if (!_checkDeviceConnection()) return;
    int colorTemp= await Dali.instance.dt8!.getColorTemperature(Dali.instance.base!.selectedAddress);
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

  void _setBrightness(double value) {
    if (!_checkDeviceConnection()) return;
    setState(() => brightness = value);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 50), () {
      Dali.instance.base!.setBright(Dali.instance.base!.selectedAddress, brightness.toInt());
    });
  }

  void _setColorTemperature(double value) {
    if (!_checkDeviceConnection()) return;
    setState(() => colorTemperature = value);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 50), () {
      Dali.instance.dt8!.setColorTemperature(Dali.instance.base!.selectedAddress, colorTemperature.toInt());
    });
  }

  Future<void> _readGroup() async {
    if (!_checkDeviceConnection()) return;
    int group = await Dali.instance.base!.getGroup(Dali.instance.base!.selectedAddress);
    setState(() {
      for (int i = 0; i < 16; i++) {
        groupCheckboxes[i] = (group & (1 << i)) != 0;
      }
    });
  }

  Future<void> _writeGroup() async {
    if (!_checkDeviceConnection()) return;
    int group = 0;
    for (int i = 0; i < 16; i++) {
      if (groupCheckboxes[i]) {
        group |= (1 << i);
      }
    }
    await Dali.instance.base!.setGroup(Dali.instance.base!.selectedAddress, group);
  }

  @override
  Widget build(BuildContext context) {
    final log = DaliLog.instance;
    return BaseScaffold(
      currentPage: 'Home',
      body: Row(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      StreamBuilder<int>(
                        stream: Dali.instance.addr!.selectedDeviceStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasData) {
                            return Text(
                              '${'Selected Address'.tr()}: ${snapshot.data}',
                              style: TextStyle(fontSize: 20),
                            );
                          } else {
                            return Text(
                              '${'Selected Address'.tr()}: ${Dali.instance.base!.selectedAddress}',
                              style: TextStyle(fontSize: 20),
                            );
                          }
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          ElevatedButton(
                            onPressed: () {
                              if (!_checkDeviceConnection()) return;
                              Dali.instance.base?.recallMaxLevel(Dali.instance.base!.selectedAddress);
                            },
                            child: const Text('ON').tr(),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (!_checkDeviceConnection()) return;
                              Dali.instance.base?.off(Dali.instance.base!.selectedAddress);
                            },
                            child: const Text('OFF').tr(),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (!_checkDeviceConnection()) return;
                              Dali.instance.addr?.resetAndAllocAddr();
                              log.showLogDialog(context, 'Log', clear: true, onCanceled: () {
                                Dali.instance.addr?.stopAllocAddr();
                              });
                            },
                            child: const Text('Addressing').tr(),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              if (!_checkDeviceConnection()) return;
                              Dali.instance.addr?.searchAddr();
                              Dali.instance.addr?.showDevicesDialog(context);
                            },
                            child: const Text('Search').tr(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          ElevatedButton(
                            onPressed: () {
                              if (!_checkDeviceConnection()) return;
                              Dali.instance.base?.reset(Dali.instance.base!.selectedAddress);
                            },
                            child: const Text('Reset').tr(),
                          ),
                          ElevatedButton(
                            onPressed: _readBrightness,
                            child: const Text('Read').tr(),
                          ),
                          ElevatedButton(
                            onPressed: _readColorTemperature,
                            child: const Text('Read').tr(),
                          ),
                          ElevatedButton(
                            onPressed: _readColor,
                            child: const Text('Read').tr(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          ElevatedButton(
                            onPressed: () {
                              ToastManager().showLoadingToast("Loading...");
                            },
                            child: Text("Loading").tr(),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ToastManager().showDoneToast("Done");
                            },
                            child: Text("Done").tr(),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ToastManager().showErrorToast("Error");
                            },
                            child: Text("Error").tr(),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ToastManager().showWarningToast("Warning");
                            },
                            child: Text("Warning").tr(),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ToastManager().showInfoToast("Info");
                            },
                            child: Text("Info").tr(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('${'Brightness'.tr()}: ${brightness.toInt()}'),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9, // Adjust the width as needed
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 8.0,
                            activeTrackColor: Colors.transparent,
                            inactiveTrackColor: Colors.transparent,
                            trackShape: GradientTrackShape(colors: [Colors.black, Colors.white]),
                            thumbColor: Colors.lightBlue,
                            overlayColor: Colors.blue.withAlpha(32),
                            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12.0),
                            overlayShape: RoundSliderOverlayShape(overlayRadius: 18.0),
                          ),
                          child: Slider(
                            value: brightness,
                            min: 0,
                            max: 254,
                            divisions: 255,
                            label: brightness.toInt().toString(),
                            onChanged: _setBrightness,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('${'Color Temperature'.tr()}: ${colorTemperature.toInt()}K'),
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9, // Adjust the width as needed
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 8.0,
                            activeTrackColor: Colors.transparent,
                            inactiveTrackColor: Colors.transparent,
                            trackShape: GradientTrackShape(colors: [Colors.yellow.shade300, Colors.white, Colors.lightBlue.shade300]),
                            thumbColor: Colors.blue,
                            overlayColor: Colors.blue.withAlpha(32),
                            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 12.0),
                            overlayShape: RoundSliderOverlayShape(overlayRadius: 18.0),
                          ),
                          child: Slider(
                            value: colorTemperature,
                            min: 2700,
                            max: 6500,
                            divisions: 3800,
                            label: colorTemperature.toInt().toString(),
                            onChanged: _setColorTemperature,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Color').tr(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          Container(
                            width: 50,
                            height: 50,
                            color: color,
                          ),
                          //const SizedBox(width: 10),
                          Text('R: ${(color.r * 255).toInt()} G: ${(color.g * 255).toInt()} B: ${(color.b * 255).toInt()}'),
                          MyColorPicker(
                            onColorChanged: _setColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Group Configuration').tr(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          Expanded(
                            child: GridView.builder(
                              shrinkWrap: true,
                              itemCount: 16,
                              padding: EdgeInsets.all(8.0),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 8,
                                mainAxisSpacing: 0.0,
                                crossAxisSpacing: 1.0,
                                childAspectRatio: 0.5,
                                mainAxisExtent: 52.0,
                              ),
                              itemBuilder: (context, index) {
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    if (index < 8) Text('$index', style: TextStyle(height: 0.1, fontSize: 16)),
                                    Transform.scale(
                                      scale: 1.6, // Adjust the scale factor to control the size
                                      child: Checkbox(
                                        value: groupCheckboxes[index],
                                        onChanged: (bool? value) {
                                          setState(() {
                                            groupCheckboxes[index] = value ?? false;
                                          });
                                        },
                                      ),
                                    ),
                                    if (index >= 8) Text('$index', style: TextStyle(height: 0.1, fontSize: 16)),
                                  ],
                                );
                              },
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: <Widget>[
                              ElevatedButton(
                                onPressed: _readGroup,
                                child: const Text('Read').tr(),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: _writeGroup,
                                child: const Text('Write').tr(),
                              ),
                            ],
                          ),
                          const SizedBox(width: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}