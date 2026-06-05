import 'package:flutter/foundation.dart';

class Logger {
  static void info(String message) {
    debugPrint('[INFO] $message');
  }

  static void warn(String message) {
    debugPrint('[WARN] $message');
  }

  static void debug(String message) {
    debugPrint('[DEBUG] $message');
  }

  static void error(String message) {
    debugPrint('[ERROR] $message');
  }
}
