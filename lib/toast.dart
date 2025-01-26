import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'main.dart';

class ToastManager {
  static final ToastManager _instance = ToastManager._internal();
  late FToast fToast;

  factory ToastManager() {
    return _instance;
  }

  ToastManager._internal();

  void init() {
    fToast = FToast();
    fToast.init(navigatorKey.currentContext!);
  }

  void showLoadingToast(String message) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: Theme
            .of(navigatorKey.currentContext!)
            .colorScheme
            .secondary,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme
                  .of(navigatorKey.currentContext!)
                  .colorScheme
                  .onSecondary,
            ),
          ),
          SizedBox(width: 12.0),
          Text(message, style: TextStyle(color: Theme
              .of(navigatorKey.currentContext!)
              .colorScheme
              .onSecondary)).tr(),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 2),
    );
  }

  void showDoneToast(String message) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: Theme.of(navigatorKey.currentContext!).colorScheme.secondary,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, color: Theme.of(navigatorKey.currentContext!).colorScheme.onSecondary),
          SizedBox(width: 12.0),
          Text(message, style: TextStyle(color: Theme.of(navigatorKey.currentContext!).colorScheme.onSecondary)).tr(),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 2),
    );
  }

  void showErrorToast(String message) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: Theme.of(navigatorKey.currentContext!).colorScheme.error,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error, color: Theme.of(navigatorKey.currentContext!).colorScheme.onError),
          SizedBox(width: 12.0),
          Text(message, style: TextStyle(color: Theme.of(navigatorKey.currentContext!).colorScheme.onError)).tr(),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 2),
    );
  }

  void showWarningToast(String message) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: Theme.of(navigatorKey.currentContext!).colorScheme.tertiary,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning, color: Theme.of(navigatorKey.currentContext!).colorScheme.onTertiary),
          SizedBox(width: 12.0),
          Text(message, style: TextStyle(color: Theme.of(navigatorKey.currentContext!).colorScheme.onTertiary)).tr(),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 2),
    );
  }

  void showInfoToast(String message) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: Theme.of(navigatorKey.currentContext!).colorScheme.primary,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info, color: Theme.of(navigatorKey.currentContext!).colorScheme.onPrimary),
          SizedBox(width: 12.0),
          Text(message, style: TextStyle(color: Theme.of(navigatorKey.currentContext!).colorScheme.onPrimary)).tr(),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 2),
    );
  }

  void showToast(String message) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: Theme.of(navigatorKey.currentContext!).colorScheme.secondary,
      ),
      child: Text(message, style: TextStyle(color: Theme.of(navigatorKey.currentContext!).colorScheme.onSecondary)).tr(),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 2),
    );
  }
}