import 'dart:io';

import 'package:flutter/services.dart';

/// Cold-restarts the app so an installed patch takes effect.
/// Implemented natively in android/.../MainActivity.kt.
class AppRestart {
  static const _channel = MethodChannel('learn_ota/app_restart');

  /// Returns false if restart is not supported (e.g. iOS): ask the user to
  /// close and reopen the app instead.
  static Future<bool> restart() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod<void>('restart');
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
