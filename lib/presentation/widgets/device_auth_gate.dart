import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../providers/device_authorization_provider.dart';
import 'unauthorized_device_screen.dart';

/// Shows [child] only when this workstation's MAC is on the authorized list.
class DeviceAuthGate extends StatelessWidget {
  const DeviceAuthGate({super.key, required this.child, this.frame = _identity});

  final Widget child;

  /// Wraps the blocking screens (theme, toast host) the same way as the app.
  final Widget Function(Widget screen) frame;

  static Widget _identity(Widget screen) => screen;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<DeviceAuthorizationProvider>();
    if (!auth.isReady) {
      return frame(
        Material(
          color: AppColors.background,
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }
    // Sits above the app Navigator, so tooltips and text selection need their own Overlay.
    if (!auth.isAuthorized) return frame(Overlay.wrap(child: const UnauthorizedDeviceScreen()));
    return child;
  }
}
