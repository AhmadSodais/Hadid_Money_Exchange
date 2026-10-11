import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../providers/app_lock_provider.dart';
import 'app_lock_screen.dart';

/// Covers the app when the lock is on, re-locks after the user leaves the
/// window, and locks automatically after [AppConstants.idleLockAfter] of
/// keyboard/mouse inactivity.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child, this.idleAfter});

  final Widget child;
  final Duration? idleAfter;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  Timer? _idle;

  Duration get _idleAfter => widget.idleAfter ?? AppConstants.idleLockAfter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _restartIdle();
  }

  @override
  void dispose() {
    _idle?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _restartIdle();
    return false;
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = Timer(_idleAfter, () {
      if (mounted) context.read<AppLockProvider>().lock();
    });
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restartIdle(),
      onPointerSignal: (_) => _restartIdle(),
      child: Stack(
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
      ),
    );
  }
}

Route<void> _lockRoute(RouteSettings settings) {
  return MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => const AppLockScreen(),
  );
}
