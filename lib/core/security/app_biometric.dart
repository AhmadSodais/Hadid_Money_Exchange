// Biometric unlock is disabled while `local_auth` is removed from pubspec.yaml.
// To restore it, re-add the package and the commented code below.

// import 'dart:io';
//
// import 'package:flutter/services.dart';
// import 'package:local_auth/local_auth.dart';

/// Fingerprint / face hardware on this computer.
class AppBiometricHardware {
  const AppBiometricHardware({
    required this.ready,
    required this.fingerprint,
    required this.face,
  });

  /// False while the Windows probe is still running.
  final bool ready;
  final bool fingerprint;
  final bool face;

  bool get any => fingerprint || face;

  static const pending = AppBiometricHardware(
    ready: false,
    fingerprint: false,
    face: false,
  );
}

enum AppBiometricStatus { success, failed, canceled, notReady, unavailable }

/// Windows Hello prompt, gated by real fingerprint or face hardware.
class AppBiometric {
  AppBiometric();

  // AppBiometric({LocalAuthentication? auth, MethodChannel? channel})
  //   : _auth = auth ?? LocalAuthentication(),
  //     _channel = channel ?? const MethodChannel('app/window');
  //
  // final LocalAuthentication _auth;
  // final MethodChannel _channel;

  /// Always reports no hardware, which hides every biometric option in the UI.
  Future<AppBiometricHardware> detect() async {
    return const AppBiometricHardware(
      ready: true,
      fingerprint: false,
      face: false,
    );
    // if (!Platform.isWindows) {
    //   return const AppBiometricHardware(
    //     ready: true,
    //     fingerprint: false,
    //     face: false,
    //   );
    // }
    // try {
    //   final raw = await _channel.invokeMethod<List<Object?>>('biometricKinds');
    //   if (raw == null) return AppBiometricHardware.pending;
    //   final kinds = raw.map((item) => '$item').toSet();
    //   return AppBiometricHardware(
    //     ready: true,
    //     fingerprint: kinds.contains('fingerprint'),
    //     face: kinds.contains('face'),
    //   );
    // } catch (_) {
    //   return const AppBiometricHardware(
    //     ready: true,
    //     fingerprint: false,
    //     face: false,
    //   );
    // }
  }

  /// Shows the system Windows Hello dialog.
  ///
  /// Windows does not allow a fingerprint-only prompt, so Hello may also
  /// offer a PIN that is already enrolled on the computer. Call this only
  /// when [detect] found fingerprint or face hardware.
  Future<AppBiometricStatus> prompt(String reason) async {
    return AppBiometricStatus.unavailable;
    // final message = reason.trim().isEmpty ? 'Unlock' : reason.trim();
    // try {
    //   final ok = await _auth.authenticate(
    //     localizedReason: message,
    //     biometricOnly: false,
    //     sensitiveTransaction: true,
    //   );
    //   return ok ? AppBiometricStatus.success : AppBiometricStatus.failed;
    // } on LocalAuthException catch (error) {
    //   return switch (error.code) {
    //     LocalAuthExceptionCode.userCanceled ||
    //     LocalAuthExceptionCode.systemCanceled ||
    //     LocalAuthExceptionCode.timeout => AppBiometricStatus.canceled,
    //     LocalAuthExceptionCode.noBiometricsEnrolled ||
    //     LocalAuthExceptionCode.noCredentialsSet ||
    //     LocalAuthExceptionCode.noBiometricHardware =>
    //       AppBiometricStatus.notReady,
    //     _ => AppBiometricStatus.unavailable,
    //   };
    // } catch (_) {
    //   return AppBiometricStatus.unavailable;
    // }
  }
}
