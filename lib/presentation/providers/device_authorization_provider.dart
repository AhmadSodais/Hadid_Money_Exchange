import 'package:flutter/foundation.dart';

import '../../core/security/authorized_devices.dart';
import '../../core/security/device_mac_service.dart';

enum DeviceAuthStatus {
  checking,
  authorized,
  unauthorized,
}

/// Verifies the workstation MAC against [AuthorizedDevices] at startup.
class DeviceAuthorizationProvider extends ChangeNotifier {
  DeviceAuthorizationProvider({DeviceMacService? macService})
      : _macService = macService ?? DeviceMacService() {
    _verify();
  }

  final DeviceMacService _macService;

  DeviceAuthStatus _status = DeviceAuthStatus.checking;
  List<String> _detectedMacs = const [];
  String? _error;

  DeviceAuthStatus get status => _status;
  bool get isReady => _status != DeviceAuthStatus.checking;
  bool get isAuthorized => _status == DeviceAuthStatus.authorized;
  List<String> get detectedMacs => _detectedMacs;
  String? get error => _error;

  Future<void> _verify() async {
    _status = DeviceAuthStatus.checking;
    _error = null;
    notifyListeners();

    try {
      final macs = await _macService.readLocalMacs();
      _detectedMacs = macs
          .map(AuthorizedDevices.formatMac)
          .toList(growable: false);

      final allowed = AuthorizedDevices.isAuthorized(macs);
      _status =
          allowed ? DeviceAuthStatus.authorized : DeviceAuthStatus.unauthorized;
      if (!allowed) {
        debugPrint(
          'DeviceAuthorization: blocked. Detected MACs: $_detectedMacs',
        );
      }
    } catch (e, st) {
      debugPrint('DeviceAuthorization failed: $e\n$st');
      _error = e.toString();
      _detectedMacs = const [];
      _status = DeviceAuthStatus.unauthorized;
    }

    notifyListeners();
  }

  Future<void> retry() => _verify();
}
