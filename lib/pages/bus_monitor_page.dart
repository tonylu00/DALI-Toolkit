import 'dart:async';
import 'package:flutter/material.dart';
import '../dali/bus_monitor.dart';
import '../dali/decode.dart';
import 'base_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BusMonitorPage extends StatefulWidget {
  final bool embedded;
  const BusMonitorPage({super.key, this.embedded = false});

  @override
  State<BusMonitorPage> createState() => _BusMonitorPageState();
}

class _BusMonitorPageState extends State<BusMonitorPage> {
  final ScrollController _controller = ScrollController();
  final List<DecodedRecord> _items = [];
  StreamSubscription? _sub;
  bool _autoScroll = true;
  int _windowMs = 100;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _sub = BusMonitor.I.decodedStream.listen((rec) {
      setState(() {
        _items.add(rec);
      });
      _maybeAutoScroll();
    });
    _controller.addListener(_onScroll);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('busMonitor.responseWindowMs') ?? 100;
    setState(() {
      _windowMs = ms;
    });
    BusMonitor.I.setResponseWindowMs(ms);
  }

  Future<void> _savePrefs(int ms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('busMonitor.responseWindowMs', ms);
    BusMonitor.I.setResponseWindowMs(ms);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final atBottom = pos.pixels >= (pos.maxScrollExtent - 16);
    if (!atBottom && _autoScroll) {
      setState(() => _autoScroll = false);
    }
  }

  void _maybeAutoScroll() {
    if (!_autoScroll || !_controller.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      final target = _controller.position.maxScrollExtent;
      try {
        _controller.jumpTo(target);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'brightness':
        return Colors.amber;
      case 'cmd':
        return Colors.blueAccent;
      case 'query':
        return Colors.purple;
      case 'ext':
        return Colors.teal;
      case 'special':
        return Colors.orange;
      case 'response':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              const Text('Bus Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              const Text('Response window (ms):'),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: TextEditingController(text: _windowMs.toString()),
                  keyboardType: TextInputType.number,
                  onSubmitted: (s) {
                    final v = int.tryParse(s) ?? 100;
                    setState(() => _windowMs = v);
                    _savePrefs(v);
                  },
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 16),
              const Text('Auto scroll'),
              Switch(value: _autoScroll, onChanged: (v) => setState(() => _autoScroll = v)),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _items.clear()),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _controller,
            itemCount: _items.length,
            itemBuilder: (c, i) {
              final r = _items[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 5),
                        decoration:
                            BoxDecoration(color: _colorFor(r.type), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.text,
                        style: TextStyle(color: _colorFor(r.type)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );

    if (widget.embedded) return content;
    return BaseScaffold(currentPage: 'BusMonitor', body: content);
  }
}
