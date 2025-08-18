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
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dali/dali.dart';

FirebaseAnalytics analytics = FirebaseAnalytics.instance;
Color themeColor = Colors.blue;
bool isDarkMode = false;
final navigatorKey = GlobalKey<NavigatorState>();
Dali dali = Dali.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  int colorValue = prefs.getInt('themeColor') ?? DaliColor.toInt(Colors.blue);
  themeColor = Color(colorValue);
  isDarkMode = prefs.getBool('isDarkMode') ?? false;
  Firebase.initializeApp(
    name: 'DALI_Inspector',
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(EasyLocalization(
      supportedLocales: [Locale('en'), Locale('zh', 'CN')],
      path: 'assets/translations', // <-- change the path of the translation files
      fallbackLocale: Locale('zh', 'CN'),
      child: MyApp()));
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue, brightness: Brightness.dark),
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
      },
    );
  }
}
