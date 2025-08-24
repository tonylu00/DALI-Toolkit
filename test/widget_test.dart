// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个最小可测试的计数器部件，避免依赖项目运行时（如 EasyLocalization/Firebase 等）。
class MiniCounterApp extends StatefulWidget {
  const MiniCounterApp({super.key});

  @override
  State<MiniCounterApp> createState() => _MiniCounterAppState();
}

class _MiniCounterAppState extends State<MiniCounterApp> {
  int _count = 0;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Mini Counter')),
        body: Center(child: Text('$_count', key: const Key('counter-text'))),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => _count++),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // 构建最小计数器应用
    await tester.pumpWidget(const MiniCounterApp());

    // 初始应为 0
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // 点击 + 号并重绘
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // 计数应加 1
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
