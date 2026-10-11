import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import 'app_lock_screen.dart';

/// Covers the app when the lock is on, and re-locks after the user leaves.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      context.read<AppLockProvider>().lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = context.watch<AppLockProvider>().isLocked;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: locked,
          child: ExcludeFocus(excluding: locked, child: widget.child),
        ),
        if (locked)
          const Positioned.fill(
            child: Navigator(
              onGenerateRoute: _lockRoute,
            ),
          ),
      ],
    );
  }
}

Route<void> _lockRoute(RouteSettings settings) {
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => const AppLockScreen(),
  );
}
