import 'package:flutter/services.dart';
import 'app_config.dart';

/// Calls the Android Kotlin layer (MethodChannel "pc_assistant/native").
/// On Windows every call simply reports false / throws - the UI guards by
/// platform before calling.
class NativeBridge {
  static const _channel = MethodChannel('pc_assistant/native');

  static Future<void> saveBridgeConfig(AppConfig cfg) async {
    await _channel.invokeMethod('saveBridgeConfig', {
      'databaseUrl': cfg.cleanDatabaseUrl,
      'pairingCode': cfg.pairingCode.trim(),
      'pcMac': cfg.pcMac.trim(),
      'broadcastIp': cfg.broadcastIp.trim(),
    });
  }

  static Future<bool> startBridgeService() async =>
      await _channel.invokeMethod<bool>('startBridgeService') ?? false;

  static Future<bool> stopBridgeService() async =>
      await _channel.invokeMethod<bool>('stopBridgeService') ?? false;

  static Future<bool> sendWakeNow(AppConfig cfg) async =>
      await _channel.invokeMethod<bool>('sendWakeNow', {
        'mac': cfg.pcMac.trim(),
        'broadcast': cfg.broadcastIp.trim(),
      }) ??
      false;

  /// Native Android speech recognition (Kotlin SpeechRecognizer).
  /// Returns the recognized text, or null if the user said nothing.
  static Future<String?> startSpeech(String locale) async {
    try {
      return await _channel.invokeMethod<String>('startSpeech', {'locale': locale});
    } on PlatformException {
      return null;
    }
  }
}
