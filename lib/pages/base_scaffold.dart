import '/connection/manager.dart';
import '/connection/connection.dart';
import '/utils/navigation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/dali/log.dart';

class BaseScaffold extends StatefulWidget {
  final Widget body;
  final String currentPage;

  const BaseScaffold({required this.body, required this.currentPage, super.key});

  @override
  BaseScaffoldState createState() => BaseScaffoldState();
}

class BaseScaffoldState extends State<BaseScaffold> {
  String _accountName = 'Not Logged In'.tr();
  String _accountEmail = '';

  @override
  void initState() {
    super.initState();
    ConnectionManager.instance.addListener(_updateConnectionStatus);
  }

  @override
  void dispose() {
    ConnectionManager.instance.removeListener(_updateConnectionStatus);
    super.dispose();
  }

  void _updateConnectionStatus() {
    setState(() {});
  }

  void _updateAccountInfo(String newName, String newEmail) {
    setState(() {
      _accountName = newName;
      _accountEmail = newEmail;
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    Connection connection = ConnectionManager.instance.connection;
    bool isConnected = connection.isDeviceConnected();
    final log = DaliLog.instance;

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
        leading: isLandscape
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
                connection.showDevicesDialog(context);
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
      drawer: isLandscape ? null : _buildDrawer(context),
      body: Row(
        children: <Widget>[
          if (isLandscape) _buildDrawer(context),
          Expanded(child: widget.body),
        ],
      ),
    );
  }

  // 统一使用 utils/navigation.dart 中的 navigateToPage

  Widget _buildDrawer(BuildContext context) {
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
              if (widget.currentPage != 'Home') {
                Navigator.pop(context); // 关闭抽屉
                navigateToPage(context, '/home');
              }
            },
          ),
          ListTile(
            title: const Text('Settings').tr(),
            selected: widget.currentPage == 'Settings',
            onTap: () {
              if (widget.currentPage != 'Settings') {
                Navigator.pop(context); // 关闭抽屉
                navigateToPage(context, '/settings');
              }
            },
          ),
          ListTile(
            title: const Text('short_addr_manager.title').tr(),
            selected: widget.currentPage == 'ShortAddressManager',
            onTap: () {
              if (widget.currentPage != 'ShortAddressManager') {
                Navigator.pop(context); // 关闭抽屉
                navigateToPage(context, '/shortAddressManager');
              }
            },
          ),
          ListTile(
            title: const Text('Sequence Editor').tr(),
            selected: widget.currentPage == 'SequenceEditor',
            onTap: () {
              if (widget.currentPage != 'SequenceEditor') {
                Navigator.pop(context); // 关闭抽屉
                navigateToPage(context, '/sequenceEditor');
              }
            },
          ),
        ],
      ),
    );
  }
}
