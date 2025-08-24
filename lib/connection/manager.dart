import 'package:flutter/material.dart';
import 'package:dalimaster/dali/log.dart';
import 'dart:async';
import 'dart:typed_data';
import 'ble.dart';
import 'serial_ip.dart';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'serial_platform.dart';
import 'connection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/toast.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'mock.dart';

class ConnectionManager extends ChangeNotifier {
  static ConnectionManager? _instance;
  Connection _connection = BleManager();
  // 假设 checkGatewayType 返回 0 时为 type0 网关（需求: 仅对 type0 网关启用总线异常检测）
  int gatewayType = -1; // 未知
  String _busStatus = 'normal'; // normal / abnormal
  Timer? _busRecoverTimer;
  DateTime? _lastToastTime;
  String? _lastToastMsg;
  Duration toastThrottle = const Duration(seconds: 2);

  static ConnectionManager get instance {
    _instance ??= ConnectionManager();
    return _instance!;
  }

  String _classifyMethod(Connection c) {
    try {
      if (c is BleManager) return 'BLE';
      if (c is TcpClient || c is UdpClient) return 'IP';
      if (c is MockConnection) return 'MOCK';
      // 通过 type 文案粗略判断串口
      final t = c.type;
      if (t.startsWith('Serial')) return 'USB';
    } catch (_) {}
    return 'UNKNOWN';
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    String connectionMethod = prefs.getString('connectionMethod') ?? 'BLE';
    // 兼容旧版本保存的 TCP/UDP 写法 -> 统一为 IP
    if (connectionMethod == 'TCP' || connectionMethod == 'UDP') {
      connectionMethod = 'IP';
      prefs.setString('connectionMethod', 'IP');
    }
    // Web 平台不支持 dart:io Socket，强制回退到 BLE
    if (kIsWeb && (connectionMethod == 'IP')) {
      connectionMethod = 'BLE';
      await prefs.setString('connectionMethod', 'BLE');
      DaliLog.instance.debugLog('On Web: fallback connection method to BLE');
    }

    // 如果连接方式发生变化，立即断开当前连接（满足“切换方式即断开”的要求）
    final currentMethod = _classifyMethod(_connection);
    if (currentMethod != 'UNKNOWN' && currentMethod != connectionMethod) {
      try {
        _connection.disconnect();
        DaliLog.instance
            .debugLog('Disconnected due to method change: $currentMethod -> $connectionMethod');
      } catch (_) {}
      notifyListeners();
    }
    if (connectionMethod == 'MOCK') {
      replaceConnection(MockConnection());
      DaliLog.instance.debugLog('Initializing Mock connection');
      return;
    } else if (connectionMethod == 'BLE') {
      if (_connection is BleManager) {
        DaliLog.instance.debugLog('BLE connection already initialized');
        return;
      }
      DaliLog.instance.debugLog('Initializing BLE connection');
      replaceConnection(BleManager());
      return;
    } else if (connectionMethod == 'IP') {
      if (!(_connection is TcpClient || _connection is UdpClient)) {
        // 默认 TCP，具体 UDP/TCP 在 IP 弹窗中可切换
        replaceConnection(TcpClient());
        return;
      }
      // 已经是 IP 系列：也通知一次，确保 UI 立即刷新（比如显示的 type 文案）
      notifyListeners();
      return;
    } else if (connectionMethod == 'USB') {
      if (_connection.type == 'Serial USB' || _connection.type == 'Serial Web') {
        DaliLog.instance.debugLog('Serial connection already initialized');
        return;
      }
      DaliLog.instance.debugLog('Initializing Serial connection');
      replaceConnection(createSerialConnection());
      return;
    } else {
      DaliLog.instance.debugLog('Unknown connection method: $connectionMethod');
      return;
    }
  }

  void openDeviceSelection(BuildContext context) async {
    final perfs = await SharedPreferences.getInstance();
    String connectionMethod = perfs.getString('connectionMethod') ?? 'BLE';
    if (connectionMethod == 'TCP' || connectionMethod == 'UDP') {
      connectionMethod = 'IP';
    }
    if (!context.mounted) return;
    if (connectionMethod == 'IP') {
      _openIpDialog(context);
      return;
    }
    if ((connectionMethod == 'BLE' && _connection is BleManager) ||
        (connectionMethod == 'USB' && (_connection.type.startsWith('Serial')))) {
      _connection.openDeviceSelection(context);
    }
  }

  void updateConnectionStatus(bool isConnected) {
    notifyListeners();
  }

  void updateGatewayType(int type) {
    gatewayType = type;
    notifyListeners();
  }

  /// 确保已获取 gatewayType（仅首次获取），在连接建立后调用。
  Future<void> ensureGatewayType() async {
    if (gatewayType != -1) return; // 已有值
    final conn = _connection;
    while (gatewayType == -1) {
      try {
        // 参考 DaliComm.checkGatewayType 逻辑，避免直接依赖产生循环导入
        List<int> bytes1 = [0x01, 0x00, 0x00]; // USB type 0
        // 默认 gateway 地址 0
        int gateway = 0;
        List<int> bytes2 = [0x28, 0x01, gateway, 0x11, 0x00, 0x00, 0xff]; // Legacy type 1
        List<int> bytes3 = [
          0x28,
          0x01,
          gateway,
          0x11,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xff
        ]; // New type 2

        await conn.send(Uint8List.fromList(bytes1));
        await Future.delayed(const Duration(milliseconds: 100));
        Uint8List? data = await conn.read(2, timeout: 100);
        if ((data != null && data.isNotEmpty) &&
            (data[0] == 0x01 || data[0] == 0x03 || data[0] == 0x05)) {
          gatewayType = 0; // USB
          notifyListeners();
          DaliLog.instance.debugLog("Gateway type detected: USB");
          return;
        }

        await conn.send(Uint8List.fromList(bytes2));
        await Future.delayed(const Duration(milliseconds: 100));
        data = await conn.read(2, timeout: 100);
        if (data != null && data.length == 2 && data[0] == gateway && data[1] >= 0) {
          gatewayType = 1; // Legacy 485
          notifyListeners();
          DaliLog.instance.debugLog("Gateway type detected: Legacy 485");
          return;
        }

        await conn.send(Uint8List.fromList(bytes3));
        await Future.delayed(const Duration(milliseconds: 100));
        data = await conn.read(2, timeout: 100);
        if (data != null && data.length == 2 && data[0] == gateway && data[1] >= 0) {
          gatewayType = 2; // New 485
          notifyListeners();
          DaliLog.instance.debugLog("Gateway type detected: New 485");
          return;
        }
        //gatewayType = 0; // 视为 type0（需求中使用）
        //notifyListeners();
        DaliLog.instance.debugLog("Could not detect gateway type, try again later");
      } catch (e) {
        // 检测失败保持 -1 以便之后可再尝试
        DaliLog.instance.debugLog('ensureGatewayType failed: $e');
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  String get busStatus => _busStatus;

  bool canOperateBus() {
    // 可扩展加入其它条件（如连接状态、网关类型等）
    return _busStatus != 'abnormal';
  }

  /// 统一检查：设备连接 + 总线正常
  bool ensureReadyForOperation({bool showToast = true}) {
    final connected = _connection.isDeviceConnected();
    if (!connected) {
      if (showToast) {
        DaliLog.instance.debugLog('connection.disconnected');
        _showToastSafe('connection.disconnected'.tr());
      }
      return false;
    }
    if (!canOperateBus()) {
      if (showToast) {
        DaliLog.instance.debugLog('Bus abnormal');
        _showToastSafe('Bus abnormal');
      }
      return false;
    }
    return true;
  }

  void _showToastSafe(String msg) {
    try {
      final now = DateTime.now();
      if (_lastToastTime != null && _lastToastMsg == msg) {
        if (now.difference(_lastToastTime!) < toastThrottle) {
          // 节流：相同消息短时间内不再弹
          return;
        }
      }
      _lastToastTime = now;
      _lastToastMsg = msg;
      ToastManager().showErrorToast(msg);
    } catch (e) {
      DaliLog.instance.debugLog('Toast show failed: $e');
    }
  }

  void markBusAbnormal({Duration recoverAfter = const Duration(seconds: 5)}) {
    if (_busStatus == 'abnormal') {
      // 刷新计时器
      _busRecoverTimer?.cancel();
    }
    _busStatus = 'abnormal';
    _busRecoverTimer?.cancel();
    _busRecoverTimer = Timer(recoverAfter, () {
      _busStatus = 'normal';
      notifyListeners();
    });
    notifyListeners();
  }

  void resetBusStatus() {
    _busRecoverTimer?.cancel();
    _busStatus = 'normal';
    notifyListeners();
  }

  Connection get connection => _connection;

  // 允许外部替换连接实例
  void replaceConnection(Connection c) {
    try {
      _connection.disconnect();
    } catch (_) {}
    _connection = c;
    gatewayType = -1;
    resetBusStatus();
    notifyListeners();
  }

  /// Force using the mock connection and persist preference.
  Future<void> useMock() async {
    // Avoid calling disconnect on existing BLE plugin in test environment
    _connection = MockConnection();
    gatewayType = -1;
    resetBusStatus();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connectionMethod', 'MOCK');
  }

  // -------------------- IP 弹窗 & 历史 --------------------
  static const _ipHistoryKey = 'ipConnectionHistory';
  static const _ipHistoryMax = 10;
  static const _ipProtocolKey = 'ipProtocolPreferred'; // 保存上次使用协议

  Future<List<Map<String, dynamic>>> _loadIpHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_ipHistoryKey) ?? [];
    final List<Map<String, dynamic>> list = [];
    for (final s in raw) {
      try {
        final m = jsonDecode(s);
        if (m is Map<String, dynamic> &&
            m['address'] is String &&
            m['port'] is int &&
            m['protocol'] is String) {
          list.add({
            'address': m['address'],
            'port': m['port'],
            'protocol': m['protocol'],
            'remark': m['remark'] is String ? m['remark'] : ''
          });
        }
      } catch (_) {}
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> _saveIpHistory(String addr, int port, String protocol,
      {String remark = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadIpHistory();
    // 查找同 address+port 记录
    final idx = list.indexWhere((e) => e['address'] == addr && e['port'] == port);
    if (idx >= 0) {
      // 只更新备注（需求：相同地址端口组合时只更新备注）
      list[idx]['remark'] = remark;
      // 可选：保留原 protocol，不改动
      final existing = list.removeAt(idx);
      list.insert(0, existing); // 移到最前保持最近性
    } else {
      list.insert(0, {
        'address': addr,
        'port': port,
        'protocol': protocol,
        'remark': remark,
      });
    }
    while (list.length > _ipHistoryMax) {
      list.removeLast();
    }
    final encoded = list.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_ipHistoryKey, encoded);
    return list;
  }

  Future<void> _removeIpHistory(Map<String, dynamic> item) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _loadIpHistory();
    list.removeWhere((e) =>
        e['address'] == item['address'] &&
        e['port'] == item['port'] &&
        e['protocol'] == item['protocol']);
    final encoded = list.map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_ipHistoryKey, encoded);
  }

  Future<void> _openIpDialog(BuildContext context) async {
    // 断开旧连接，确保使用最新实例
    try {
      _connection.disconnect();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connectionMethod', 'IP');
    String lastProtocol = prefs.getString(_ipProtocolKey) ?? 'TCP';
    if (lastProtocol != 'UDP') lastProtocol = 'TCP';
    final addressCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '12345');
    String protocol = lastProtocol; // TCP / UDP
    List<Map<String, dynamic>> history = await _loadIpHistory();
    final remarkCtrl = TextEditingController();

    if (!context.mounted) return;
    bool connecting = false;
    int attempt = 0;
    String? errorMsg;
    bool aborted = false;

    void stop(StateSetter setState) {
      if (!connecting) return;
      aborted = true;
      errorMsg ??= 'Aborted';
      connecting = false;
      setState(() {});
    }

    Future<void> doConnect(StateSetter setState, BuildContext dialogCtx) async {
      final addr = addressCtrl.text.trim();
      final p = int.tryParse(portCtrl.text.trim()) ?? 0;
      if (addr.isEmpty || p <= 0) {
        setState(() => errorMsg = 'Invalid address/port');
        return;
      }
      errorMsg = null;
      connecting = true;
      attempt = 0;
      setState(() {});
      while (attempt < 3) {
        if (aborted) break;
        attempt++;
        setState(() {});
        try {
          prefs.setString(_ipProtocolKey, protocol);
          final newConn = protocol == 'UDP' ? UdpClient() : TcpClient();
          replaceConnection(newConn);
          await newConn.connect(addr, port: p).timeout(const Duration(seconds: 6));
          if (!aborted) {
            history = await _saveIpHistory(addr, p, protocol, remark: remarkCtrl.text.trim());
            if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
          }
          return; // success (or aborted right after success attempt)
        } catch (e) {
          if (aborted) break;
          errorMsg = 'Attempt $attempt failed: $e';
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }
      connecting = false;
      if (aborted && errorMsg == null) {
        errorMsg = 'Aborted';
      }
      setState(() {});
    }

    showDialog(
      context: context,
      barrierDismissible: !connecting,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('ip.dialog.title').tr(),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: addressCtrl,
                    decoration: InputDecoration(labelText: 'ip.dialog.address'.tr()),
                    enabled: !connecting,
                  ),
                  TextField(
                    controller: portCtrl,
                    decoration: InputDecoration(labelText: 'ip.dialog.port'.tr()),
                    keyboardType: TextInputType.number,
                    enabled: !connecting,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarkCtrl,
                    decoration: InputDecoration(labelText: 'ip.dialog.remark'.tr()),
                    enabled: !connecting,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('ip.dialog.protocol').tr(),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: protocol,
                      items: [
                        DropdownMenuItem(value: 'TCP', child: Text('ip.dialog.tcp').tr()),
                        DropdownMenuItem(value: 'UDP', child: Text('ip.dialog.udp').tr()),
                      ],
                      onChanged:
                          connecting ? null : (v) => setState(() => protocol = v ?? protocol),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (connecting)
                    Row(
                      children: [
                        const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('ip.dialog.connecting_attempt'
                              .tr(namedArgs: {'attempt': '$attempt', 'total': '3'})),
                        ),
                      ],
                    ),
                  const Divider(),
                  const Text('ip.dialog.history').tr(),
                  const SizedBox(height: 4),
                  Expanded(
                    child: history.isEmpty
                        ? Center(child: Text('ip.dialog.no_history').tr())
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: history.length,
                            itemBuilder: (c, i) {
                              final e = history[i];
                              final remark = (e['remark'] as String? ?? '').trim();
                              return ListTile(
                                dense: true,
                                title: Text('${e['address']}:${e['port']} (${e['protocol']})'),
                                subtitle: Text(
                                  remark.isNotEmpty ? remark : ' ',
                                  style: const TextStyle(fontSize: 11, height: 1.2),
                                ),
                                trailing: connecting
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.delete, size: 18),
                                        onPressed: () async {
                                          await _removeIpHistory(e);
                                          setState(() => history.removeAt(i));
                                        },
                                      ),
                                onTap: connecting
                                    ? null
                                    : () {
                                        addressCtrl.text = e['address'];
                                        portCtrl.text = e['port'].toString();
                                        setState(() => protocol = e['protocol']);
                                      },
                              );
                            },
                          ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
            ),
            actions: [
              if (!connecting)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('common.close').tr(),
                )
              else
                TextButton(
                  onPressed: () => stop(setState),
                  child: const Text('ip.dialog.stop').tr(),
                ),
              if (!connecting)
                TextButton(
                  onPressed: () async {
                    final addr = addressCtrl.text.trim();
                    final p = int.tryParse(portCtrl.text.trim()) ?? 0;
                    if (addr.isEmpty || p <= 0) {
                      setState(() => errorMsg = 'ip.dialog.invalid_input'.tr());
                      return;
                    }
                    errorMsg = null;
                    setState(() {});
                    prefs.setString(_ipProtocolKey, protocol);
                    history =
                        await _saveIpHistory(addr, p, protocol, remark: remarkCtrl.text.trim());
                    // 不关闭弹窗，仅刷新列表
                    setState(() {});
                  },
                  child: const Text('ip.dialog.save').tr(),
                ),
              ElevatedButton(
                onPressed: connecting ? null : () => doConnect(setState, ctx),
                child: Text(
                  connecting
                      ? 'ip.dialog.connecting_attempt'
                          .tr(namedArgs: {'attempt': '$attempt', 'total': '3'})
                      : 'ip.dialog.connect'.tr(),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}
