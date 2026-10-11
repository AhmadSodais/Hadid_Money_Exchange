import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Paints the native Windows title bar (the strip with minimize / maximize /
/// close) to match the app background.
abstract final class WindowTitleBar {
  static const _channel = MethodChannel('app/window');

  static Color? _lastBackground;
  static Color? _lastForeground;

  static bool _held = false;
  static ({Color background, Color foreground, Brightness brightness})?
  _deferred;

  /// Follows the app theme. Ignored (but remembered) while [hold] is active.
  static void sync({
    required Color background,
    required Color foreground,
    required Brightness brightness,
  }) {
    if (_held) {
      _deferred = (
        background: background,
        foreground: foreground,
        brightness: brightness,
      );
      return;
    }
    _apply(background, foreground, brightness);
  }

  /// Pins the title bar to [color] (e.g. during the theme transition) until
  /// [release]; theme-driven [sync] calls are deferred meanwhile.
  static void hold({required Color color, required Brightness brightness}) {
    _held = true;
    _apply(
      color,
      brightness == Brightness.dark
          ? AppColors.darkPalette.textPrimary
          : AppColors.lightTextPrimary,
      brightness,
    );
  }

  /// Ends [hold] and applies the latest deferred [sync], if any.
  static void release() {
    if (!_held) return;
    _held = false;
    final deferred = _deferred;
    _deferred = null;
    if (deferred != null) {
      _apply(deferred.background, deferred.foreground, deferred.brightness);
    }
  }

  static void _apply(Color background, Color foreground, Brightness brightness) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    if (background == _lastBackground && foreground == _lastForeground) return;
    _lastBackground = background;
    _lastForeground = foreground;

    _channel.invokeMethod<void>('setTitleBarColor', {
      'background': background.toARGB32(),
      'foreground': foreground.toARGB32(),
      'dark': brightness == Brightness.dark,
    }).catchError((Object e) {
      debugPrint('WindowTitleBar.sync failed: $e');
    });
  }
}
