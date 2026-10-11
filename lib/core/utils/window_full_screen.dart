import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Toggles borderless full screen for the native Windows window.
abstract final class WindowFullScreen {
  static const _channel = MethodChannel('app/window');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Current full-screen state, shared by every toggle in the app.
  static final ValueNotifier<bool> state = ValueNotifier<bool>(false);

  static bool _synced = false;

  /// Reads the native state once (it survives a Dart hot restart).
  static Future<void> sync() async {
    if (!isSupported || _synced) return;
    _synced = true;
    try {
      state.value = await _channel.invokeMethod<bool>('isFullScreen') ?? false;
    } catch (e) {
      debugPrint('WindowFullScreen.sync failed: $e');
    }
  }

  static Future<void> set(bool enabled) async {
    if (!isSupported) return;
    try {
      state.value =
          await _channel.invokeMethod<bool>('setFullScreen', enabled) ??
          enabled;
    } catch (e) {
      debugPrint('WindowFullScreen.set failed: $e');
    }
  }

  static Future<void> toggle() => set(!state.value);
}
