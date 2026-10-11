import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Shared GlassFlow page transitions.
///
/// Route swaps are instant so the outgoing page is removed immediately instead
/// of staying on screen under the incoming one. The visible entrance is the
/// top-to-bottom ladder played by `PageScaffold`.
abstract final class AppPageTransitions {
  /// Primary sidebar page switches.
  static Page<void> fadeSlide({required LocalKey key, required Widget child}) =>
      NoTransitionPage<void>(key: key, child: child);

  /// Nested detail screens.
  static Page<void> slideForward({
    required LocalKey key,
    required Widget child,
  }) => NoTransitionPage<void>(key: key, child: child);
}
