import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/diagnostics.dart';

/// Whether this device may show the liquid-glass navigation bar.
///
/// Mirrors the gate the reference apps use: the effect is Android 13+
/// (API 33, i.e. RuntimeShader + RenderEffect), skipped on low-RAM
/// devices and in battery saver. Below that the app keeps the plain
/// Material bar, which is exactly what legado/NeriPlayer do there.
///
/// The capabilities come from the MainActivity channel (no plugin
/// dependency): "zlibx/device" -> glassSupport -> {sdkInt, lowRam,
/// powerSave}. Resolved once at startup (before runApp) and read
/// synchronously; tests run on the host, so the default is disabled.
abstract final class GlassSupport {
  static const MethodChannel _channel = MethodChannel('zlibx/device');

  /// True only when [initialize] proved the device can run the effect.
  static bool enabled = false;

  /// Why the gate closed, for the diagnostics trail. Never shown.
  static String reason = 'not initialized';

  /// Android 13 = API 33, the first release with public RuntimeShader and
  /// RenderEffect; both reference apps also start their glass module at 33.
  static const int minSdk = 33;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) {
      reason = 'not android';
      return;
    }
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'glassSupport',
      );
      final sdk = info?['sdkInt'] as int? ?? 0;
      if (sdk < minSdk) {
        reason = 'sdk $sdk';
        return;
      }
      if (info?['lowRam'] == true) {
        reason = 'low ram';
        return;
      }
      if (info?['powerSave'] == true) {
        reason = 'power save';
        return;
      }
      enabled = true;
      reason = 'sdk $sdk';
    } catch (error) {
      logIgnored('glass_support', error);
      reason = 'channel failed';
    }
  }
}
