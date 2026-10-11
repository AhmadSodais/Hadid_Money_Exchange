/// GlassFlow animation duration tokens.
abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration sidebar = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration tooltip = Duration(milliseconds: 150);

  /// Light / dark circular reveal.
  static const Duration themeTransition = Duration(milliseconds: 700);

  /// Theme cross-fade when reduced motion is on.
  static const Duration themeTransitionReduced = Duration(milliseconds: 180);
}
