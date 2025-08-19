import '/connection/manager.dart';
import '/connection/connection.dart';
import '/utils/navigation.dart';
import '/dali/dali.dart';
import '/widgets/panels/device_selection_panel.dart';
import '/pages/home.dart';
import '/pages/settings.dart';
import '/pages/short_address_manager_page.dart';
import '/pages/sequence_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'dart:io' show Platform; // 对桌面平台判断
import 'package:desktop_window/desktop_window.dart';

import '/dali/log.dart';
import '/utils/internal_page_prefs.dart';

class BaseScaffold extends StatefulWidget {
  final Widget body;
  final String currentPage;

  const BaseScaffold({required this.body, required this.currentPage, super.key});

  @override
  BaseScaffoldState createState() => BaseScaffoldState();
}

class BaseScaffoldState extends State<BaseScaffold> {
  // 布局参数集中：方便同时用于窗口最小尺寸与实时计算
  static const double _kLeftPanelWidth = 340.0;
  static const double _kNavRailWidth = 72.0; // 大屏模式功能区导航宽
  static const double _kMinFunctionalWidth = 560.0; // 右侧功能区最小有效内容宽
  static const double _kExtraMargin = 32.0; // 余量（窗口边缘/滚动条等）
  String _accountName = 'Not Logged In'.tr();
  String _accountEmail = '';
  String? _internalPage; // 大尺寸模式当前功能区
  late final InternalPagePrefs _prefs;

  @override
  void initState() {
    super.initState();
    ConnectionManager.instance.addListener(_updateConnectionStatus);
    _initDesktopWindow();
    _prefs = InternalPagePrefs.instance..addListener(_onPrefsChanged);
    _loadPrefs();
    _internalPage = widget.currentPage; // 初始内部页，偏好加载后可能覆盖
  }

  @override
  void dispose() {
    ConnectionManager.instance.removeListener(_updateConnectionStatus);
    super.dispose();
  }

  void _updateConnectionStatus() {
    setState(() {});
  }

  void _onPrefsChanged() {
    if (!mounted) return;
    setState(() {}); // 仅刷新 remember 状态展示（未来可加 UI）
  }

  Future<void> _loadPrefs() async {
    await _prefs.load();
    if (!mounted) return;
    if (_prefs.remember && _prefs.lastPage != null) {
      setState(() => _internalPage = _prefs.lastPage);
    }
  }

  void _changeInternalPage(String key) {
    setState(() => _internalPage = key);
    _prefs.setLastPage(key); // 未开启记忆时内部忽略
  }

  // 桌面窗口初始化：限定最小尺寸，确保双列布局不被压缩
  Future<void> _initDesktopWindow() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // 需要同时容纳：左侧设备面板 + 导航 Rail + 最小功能区宽度 + 余量
      const minWidth =
          _kLeftPanelWidth + _kNavRailWidth + _kMinFunctionalWidth + _kExtraMargin; // 1004 默认
      const minHeight = 600.0; // 经验值
      try {
        await DesktopWindow.setMinWindowSize(Size(minWidth.toDouble(), minHeight));
        // 如果当前窗口比我们要求的小，主动放大到最小逻辑尺寸，避免首次显示压缩布局
        final current = await DesktopWindow.getWindowSize();
        if (current.width < minWidth - 1) {
          // 容差
          final targetHeight = current.height < minHeight ? minHeight : current.height;
          await DesktopWindow.setWindowSize(Size(minWidth.toDouble(), targetHeight));
        }
      } catch (_) {}
    }
  }

  void _updateAccountInfo(String newName, String newEmail) {
    setState(() {
      _accountName = newName;
      _accountEmail = newEmail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    // 简易对角线英寸估算：对角 = 像素对角 / ppi；无法精确获取 ppi，这里近似用逻辑像素对角 / 150 估算，>10 判定
    final diagonalLogical = math.sqrt(size.width * size.width + size.height * size.height);
    final approxInches = diagonalLogical / 150.0; // 经验系数
    bool isUltraLarge = approxInches >= 10.0;
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    // 桌面窗口模式强制使用超大屏布局
    if (isDesktop) {
      isUltraLarge = true;
    }
    bool isLandscape = media.orientation == Orientation.landscape;
    // 超大屏强制保持横屏（若当前不是横屏尝试锁定）
    if (isUltraLarge && !isLandscape && !isDesktop) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      isLandscape = true; // 预期锁定后刷新
    } else if (!isUltraLarge && !isDesktop) {
      // 非超大屏解除锁定，允许正常旋转
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    Connection connection = ConnectionManager.instance.connection;
    bool isConnected = connection.isDeviceConnected();
    final log = DaliLog.instance;

    final minFunctionalWidth = _kMinFunctionalWidth; // 功能区域最小宽度
    final leftPanelWidth = isUltraLarge ? _kLeftPanelWidth : 0.0;
    final effectiveRightWidth = size.width - leftPanelWidth;
    final cramped = isUltraLarge && effectiveRightWidth < minFunctionalWidth;

    // 内部功能页集合（大尺寸模式使用）
    final internalPages = <_PageSpec>[
      _PageSpec(
        key: 'Home',
        label: 'Home'.tr(),
        icon: Icons.home_outlined,
        builder: (c) => const MyHomePage(title: '', embedded: true),
      ),
      _PageSpec(
        key: 'Settings',
        label: 'Settings'.tr(),
        icon: Icons.settings_outlined,
        builder: (c) => SettingsPage(
          embedded: true,
          onThemeModeChanged: (v) {}, // 主题切换在嵌入模式下可后续注入
          onThemeColorChanged: (_) {},
        ),
      ),
      _PageSpec(
        key: 'ShortAddressManager',
        label: 'short_addr_manager.title'.tr(),
        icon: Icons.format_list_numbered,
        builder: (c) => ShortAddressManagerPage(
          daliAddr: Dali.instance.addr!,
          embedded: true,
        ),
      ),
      _PageSpec(
        key: 'SequenceEditor',
        label: 'Sequence Editor'.tr(),
        icon: Icons.list_alt_outlined,
        builder: (c) => const SequenceEditorPage(embedded: true),
      ),
    ];

    // 若当前 internalPage 不在集合中，回退首页
    if (isUltraLarge && internalPages.indexWhere((e) => e.key == _internalPage) == -1) {
      _internalPage = 'Home';
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('DALI Toolkit', style: TextStyle(fontSize: 18)).tr(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(isConnected ? "Connected" : "Disconnected",
                        style: const TextStyle(fontSize: 12))
                    .tr(),
                const SizedBox(height: 1),
                Text(connection.type, style: const TextStyle(fontSize: 12)),
                Text(connection.connectedDeviceId, style: const TextStyle(fontSize: 8)),
                if (isConnected && ConnectionManager.instance.gatewayType == 0)
                  Text(
                    ConnectionManager.instance.busStatus == 'abnormal' ? '总线异常' : '总线正常',
                    style: TextStyle(
                      fontSize: 10,
                      color: ConnectionManager.instance.busStatus == 'abnormal'
                          ? Colors.red
                          : Colors.green,
                    ),
                  ),
              ],
            ),
          ],
        ),
        leading: (isLandscape && isUltraLarge)
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String result) async {
              if (result == 'Option 1') {
                connection.openDeviceSelection(context);
              } else if (result == 'Option 2') {
                connection.disconnect();
              } else if (result == 'Option 3') {
                final prefs = await SharedPreferences.getInstance();
                if (!context.mounted) return;
                connection.renameDeviceDialog(context, prefs.getString('deviceName') ?? '');
              } else if (result == 'Option 4') {
                log.showLogDialog(context, 'Log');
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'Option 1',
                child: Text('Connect').tr(),
              ),
              PopupMenuItem<String>(
                value: 'Option 2',
                child: Text('Disconnect').tr(),
              ),
              PopupMenuItem<String>(
                value: 'Option 3',
                child: Text('Rename').tr(),
              ),
              PopupMenuItem<String>(
                value: 'Option 4',
                child: Text('Show Log').tr(),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      drawer: (isLandscape && isUltraLarge) ? null : _buildDrawer(context),
      body: isUltraLarge
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左侧常驻设备面板（短地址设备列表）
                Container(
                  width: leftPanelWidth,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    border: Border(
                        right: BorderSide(
                            color: Theme.of(context).dividerColor.withValues(alpha: 0.2))),
                  ),
                  child: SafeArea(
                    child: DeviceSelectionPanel(
                      daliAddr: Dali.instance.addr!,
                      showTitle: true,
                    ),
                  ),
                ),
                // 功能区导航（Rail）
                Container(
                  width: _kNavRailWidth,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                    border: Border(
                      right:
                          BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                    ),
                  ),
                  child: SafeArea(
                    child: NavigationRail(
                      selectedIndex: internalPages.indexWhere((e) => e.key == _internalPage),
                      onDestinationSelected: (i) => _changeInternalPage(internalPages[i].key),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final p in internalPages)
                          NavigationRailDestination(
                            icon: Icon(p.icon),
                            selectedIcon:
                                Icon(p.icon, color: Theme.of(context).colorScheme.primary),
                            label: Text(p.label, textAlign: TextAlign.center),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: cramped
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              '当前窗口宽度过窄，请放大窗口以继续使用功能区',
                              style: Theme.of(context).textTheme.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : Builder(
                          builder: (c) {
                            final spec = internalPages.firstWhere((e) => e.key == _internalPage,
                                orElse: () => internalPages.first);
                            return spec.builder(c);
                          },
                        ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                if (isLandscape) _buildDrawer(context),
                Expanded(child: widget.body),
              ],
            ),
    );
  }

  // 统一使用 utils/navigation.dart 中的 navigateToPage

  Widget _buildDrawer(BuildContext context) {
    final media = MediaQuery.of(context);
    final diagonalLogical =
        math.sqrt(media.size.width * media.size.width + media.size.height * media.size.height);
    final approxInches = diagonalLogical / 150.0;
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isUltraLarge = isDesktop || approxInches >= 10.0;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: Text(_accountName),
            accountEmail: Text(_accountEmail),
            currentAccountPicture: GestureDetector(
              onTap: () {
                if (_accountName == 'Not Logged In'.tr()) {
                  Navigator.pushNamed(context, '/login').then((value) {
                    if (value != null) {
                      final List<String> loginInfo = value as List<String>;
                      _updateAccountInfo(loginInfo[0], loginInfo[1]);
                    }
                  });
                } else {
                  _updateAccountInfo('Not Logged In'.tr(), '');
                }
              },
              child: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text('User'),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Free').tr(),
              Icon(Icons.star_border, color: Theme.of(context).colorScheme.primary),
              Text('${'Expires'.tr()}: 2099-12-31', style: const TextStyle(fontSize: 10)),
            ],
          ),
          const Divider(),
          ListTile(
            title: const Text('Home').tr(),
            selected: widget.currentPage == 'Home',
            onTap: () {
              if (isUltraLarge) {
                _changeInternalPage('Home');
                Navigator.pop(context);
              } else if (widget.currentPage != 'Home') {
                Navigator.pop(context);
                navigateToPage(context, '/home');
              }
            },
          ),
          ListTile(
            title: const Text('Settings').tr(),
            selected: widget.currentPage == 'Settings',
            onTap: () {
              if (isUltraLarge) {
                _changeInternalPage('Settings');
                Navigator.pop(context);
              } else if (widget.currentPage != 'Settings') {
                Navigator.pop(context);
                navigateToPage(context, '/settings');
              }
            },
          ),
          ListTile(
            title: const Text('short_addr_manager.title').tr(),
            selected: widget.currentPage == 'ShortAddressManager',
            onTap: () {
              if (isUltraLarge) {
                _changeInternalPage('ShortAddressManager');
                Navigator.pop(context);
              } else if (widget.currentPage != 'ShortAddressManager') {
                Navigator.pop(context);
                navigateToPage(context, '/shortAddressManager');
              }
            },
          ),
          ListTile(
            title: const Text('Sequence Editor').tr(),
            selected: widget.currentPage == 'SequenceEditor',
            onTap: () {
              if (isUltraLarge) {
                _changeInternalPage('SequenceEditor');
                Navigator.pop(context);
              } else if (widget.currentPage != 'SequenceEditor') {
                Navigator.pop(context);
                navigateToPage(context, '/sequenceEditor');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _PageSpec {
  final String key;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  _PageSpec({required this.key, required this.label, required this.icon, required this.builder});
}
