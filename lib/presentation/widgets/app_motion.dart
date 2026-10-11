import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';

/// The single source of truth for motion throughout the client.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 320);
  static const medium = Duration(milliseconds: 520);
  static const slow = Duration(milliseconds: 720);

  /// Length of each step of the page entrance in [PageScaffold].
  static const page = Duration(milliseconds: 500);

  static const fastCurve = Curves.easeOutCubic;
  static const standardCurve = Curves.easeInOutCubic;
  static const emphasizedCurve = Curves.easeOutBack;

  static bool reduced(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return true;
    try {
      return context.read<AppSettingsProvider>().reducedMotion;
    } catch (_) {
      return false;
    }
  }

  static Duration duration(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}

class AppPageRoute<T> extends PageRouteBuilder<T> {
  AppPageRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: AppMotion.normal,
          reverseTransitionDuration: AppMotion.normal,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (AppMotion.reduced(context)) {
              return FadeTransition(opacity: animation, child: child);
            }
            final curved = CurvedAnimation(
              parent: animation,
              curve: AppMotion.fastCurve,
              reverseCurve: AppMotion.standardCurve,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(.035, .015),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
