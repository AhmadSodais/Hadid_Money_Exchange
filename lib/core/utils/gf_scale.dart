import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Window-driven UI scale so typography and shared controls shrink on smaller
/// screens instead of truncating with ellipsis.
///
/// Design reference is the **main development display** logical size
/// (1920×1080 physical at 125% DPI → [referenceWidth] × [referenceHeight]).
/// At that size (or larger), layout scale stays **1.0** so the layout matches
/// the look that already worked on that laptop. Only windows smaller than the
/// reference shrink, down to [minFactor].
///
/// Text gets an extra [textBoost] on top of the layout factor, so type reads
/// a little larger everywhere (e.g. 14 → 15.4 at full scale) without widening
/// controls or the sidebar.
abstract final class GfScale {
  /// Logical width of the main 1920×1080 @ 125% screen.
  static const double referenceWidth = 1536;

  /// Logical height of the main 1920×1080 @ 125% screen.
  static const double referenceHeight = 864;

  /// Smallest scale used on very tight windows.
  static const double minFactor = 0.78;

  /// Cap at 1.0 so larger monitors keep the designed density.
  static const double maxFactor = 1.0;

  /// Text-only boost over the layout factor ("a few bigger": +10%).
  /// Applied to [TextScaler] only — controls/sidebar keep the layout factor.
  static const double textBoost = 1.10;

  /// Treat sizes within this ratio of the reference as full scale (title bar /
  /// taskbar / rounding should not shrink the "good" laptop layout).
  static const double fullScaleTolerance = 0.96;

  static double factorForSize(Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return 1.0;
    }
    final byWidth = size.width / referenceWidth;
    final byHeight = size.height / referenceHeight;
    final raw = math.min(byWidth, byHeight);
    if (raw >= fullScaleTolerance) return 1.0;
    return raw.clamp(minFactor, maxFactor);
  }

  /// Effective text scale for a window [size]: layout factor × [textBoost].
  static double textFactorForSize(Size size) =>
      factorForSize(size) * textBoost;

  /// Current UI scale from [GfScaleScope], or computed from [MediaQuery].
  static double of(BuildContext context) {
    final scoped = GfScaleScope.maybeOf(context);
    if (scoped != null) return scoped.factor;
    return factorForSize(MediaQuery.sizeOf(context));
  }

  /// Scales a design-pixel [value] by the current UI factor.
  static double s(BuildContext context, double value) => value * of(context);
}

/// Provides the active [factor] to descendants (set by [GfScaleHost]).
class GfScaleScope extends InheritedWidget {
  const GfScaleScope({
    super.key,
    required this.factor,
    required super.child,
  });

  final double factor;

  static GfScaleScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GfScaleScope>();
  }

  static GfScaleScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'GfScaleScope not found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(GfScaleScope oldWidget) => factor != oldWidget.factor;
}

/// Applies [GfScale] to [MediaQuery.textScaler] and exposes [GfScaleScope].
///
/// Place once under [MaterialApp.builder] so every page, dialog, and overlay
/// inherits the same scale.
class GfScaleHost extends StatelessWidget {
  const GfScaleHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final factor = GfScale.factorForSize(mq.size);
    // Preserve OS / accessibility text scale, then multiply by the UI text
    // factor (layout factor plus the small text boost).
    final userFactor = mq.textScaler.scale(14) / 14;
    final combined = TextScaler.linear(
      (userFactor * factor * GfScale.textBoost)
          .clamp(GfScale.minFactor * 0.85, 2.0),
    );

    return MediaQuery(
      data: mq.copyWith(textScaler: combined),
      child: GfScaleScope(
        factor: factor,
        child: child,
      ),
    );
  }
}
