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
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dali/dali.dart';
import 'package:provider/provider.dart';
import 'auth/auth_provider.dart';
import 'auth/auth_required.dart';

FirebaseAnalytics analytics = FirebaseAnalytics.instance;
// VS Code 默认蓝色 #007ACC 作为应用默认主题色
Color themeColor = const Color(0xFF007ACC);
bool isDarkMode = false;
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
  Firebase.initializeApp(
    name: 'DALI_Inspector',
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
