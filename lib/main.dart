import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'connection/manager.dart';
import 'dali/color.dart';
import 'firebase_options.dart';
import 'pages/settings.dart';
import 'pages/home.dart';
import 'pages/login.dart';
import 'pages/short_address_manager_page.dart';
import 'pages/sequence_editor_page.dart';
import 'pages/about_page.dart';
import 'pages/custom_keys_page.dart';
import 'pages/profile_page.dart';
import 'pages/bus_monitor_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dali/dali.dart';
import 'package:provider/provider.dart';
import 'auth/auth_provider.dart';
import 'auth/auth_required.dart';
import 'dali/log.dart';
import 'utils/import_channel.dart';

FirebaseAnalytics analytics = FirebaseAnalytics.instance;
// 自定义屏幕名提取：优先 RouteSettings.name；否则从 arguments 中读取；最后回退到路由类型名
String? _screenNameExtractor(RouteSettings settings) {
  final name = settings.name;
  if (name != null && name.isNotEmpty) return name;
  final args = settings.arguments;
  if (args is Map) {
    for (final key in const ['screenName', 'screen_name', 'screen']) {
      final v = args[key];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  // 退而求其次，使用 arguments 的类型名；否则返回固定占位名
  final type = args?.runtimeType.toString();
  if (type != null && type.isNotEmpty) return type;
  return 'UnnamedRoute';
}

FirebaseAnalyticsObserver analyticsObserver = FirebaseAnalyticsObserver(
  analytics: analytics,
  nameExtractor: _screenNameExtractor,
);
// VS Code 默认蓝色 #007ACC 作为应用默认主题色
Color themeColor = const Color(0xFF007ACC);
bool isDarkMode = false;
// 是否将所有 Flutter 错误上报为致命错误到 Crashlytics，由设置页开关控制
bool reportAllErrors = false;
// 匿名用户标识符，用于 Crashlytics 关联
String anonymousId = '';
final navigatorKey = GlobalKey<NavigatorState>();
Dali dali = Dali.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // 如果还没有保存的主题色，使用 VS Code 蓝 #007ACC
  int colorValue = prefs.getInt('themeColor') ?? DaliColor.toInt(const Color(0xFF007ACC));
  themeColor = Color(colorValue);
  isDarkMode = prefs.getBool('isDarkMode') ?? false;
  // 读取 Crashlytics 上报策略
  reportAllErrors = prefs.getBool('reportAllErrors') ?? false;
  // 确保匿名标识符存在
  anonymousId = prefs.getString('anonymousId') ?? '';
  if (anonymousId.isEmpty) {
    anonymousId = _generateUuidV4();
    await prefs.setString('anonymousId', anonymousId);
  }
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAnalytics.instance.setUserId(id: anonymousId);
  // Crashlytics 在 Web 端不受支持：仅在非 Web 目标启用
  if (!kIsWeb) {
    // 将匿名标识符设置到 Crashlytics 中
    await FirebaseCrashlytics.instance.setUserIdentifier(anonymousId);
    FlutterError.onError = (errorDetails) {
      if (reportAllErrors) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      } else {
        FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } else {
    // Web 平台：避免触发 Crashlytics 初始化，改为本地日志与控制台输出
    FlutterError.onError = (errorDetails) {
      // 控制台与自定义日志
      FlutterError.presentError(errorDetails);
      DaliLog.instance.debugLog('Flutter error (web): '
          '${errorDetails.exceptionAsString()}\n${errorDetails.stack}');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      // 控制台与自定义日志
      // ignore: avoid_print
      print('Uncaught (web): $error\n$stack');
      DaliLog.instance.debugLog('Uncaught (web): $error\n$stack');
      return true;
    };
  }
  // Initialize log level (default depends on build mode) on first launch
  await DaliLog.instance.init();
  // Initialize platform import channel (.daliproj opener)
  ImportChannel.instance.init();
  runApp(EasyLocalization(
      supportedLocales: [Locale('en'), Locale('zh', 'CN')],
      path: 'assets/translations',
      fallbackLocale: Locale('zh', 'CN'),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()..init()),
        ],
        child: const MyApp(),
      )));
  ConnectionManager.instance.init();
}

// 生成一个简单的 UUID v4 字符串（基于随机数）
String _generateUuidV4() {
  // xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  final rand = DateTime.now().microsecondsSinceEpoch ^
      identityHashCode(Object()) ^
      (DateTime.now().millisecondsSinceEpoch << 7);
  int seed = rand & 0x7fffffff;
  int next() {
    // 线性同余生成器，避免外部依赖
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed;
  }

  String hex(int n, int width) => n.toRadixString(16).padLeft(width, '0');
  final p1 = hex(next(), 8);
  final p2 = hex(next() & 0xFFFF, 4);
  final p3 = ((next() & 0x0FFF) | 0x4000); // version 4
  final p4 = ((next() & 0x3FFF) | 0x8000); // variant 10
  final p5a = hex(next(), 8);
  final p5b = hex(next(), 4);
  return '$p1-$p2-${hex(p3, 4)}-${hex(p4, 4)}-$p5a$p5b'.toLowerCase();
}

// 重置匿名标识符并同步更新 Crashlytics，返回新 ID
Future<String> resetAnonymousId() async {
  final prefs = await SharedPreferences.getInstance();
  anonymousId = _generateUuidV4();
  await prefs.setString('anonymousId', anonymousId);
  await FirebaseCrashlytics.instance.setUserIdentifier(anonymousId);
  return anonymousId;
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  ThemeMode _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
  Color _themeColor = themeColor;

  void _toggleThemeMode(bool isDarkMode) {
    setState(() {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _changeThemeColor(Color color) {
    setState(() {
      _themeColor = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: FToastBuilder(),
      navigatorKey: navigatorKey,
      navigatorObservers: [analyticsObserver],
      title: 'DALI Inspector',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _themeColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _themeColor, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      initialRoute: '/home',
      routes: {
        '/home': (context) => const MyHomePage(
              title: '',
            ),
        '/busMonitor': (context) => const BusMonitorPage(),
        '/settings': (context) => SettingsPage(
              onThemeModeChanged: _toggleThemeMode,
              onThemeColorChanged: _changeThemeColor,
            ),
        '/login': (context) => const LoginPage(),
        '/shortAddressManager': (context) => ShortAddressManagerPage(daliAddr: dali.addr!),
        '/sequenceEditor': (context) => const SequenceEditorPage(),
        '/customKeys': (context) => const CustomKeysPage(),
        '/about': (context) => const AuthRequired(child: AboutPage()),
        '/profile': (context) => const ProfilePage(),
      },
    );
  }
}
