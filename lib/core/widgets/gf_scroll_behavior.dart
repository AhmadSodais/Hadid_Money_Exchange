import 'package:flutter/material.dart';

/// Width of the strip beside a scroll view that holds its scrollbar.
const double kGfScrollbarGutter = 14;

/// App-wide scroll behavior (set on [MaterialApp.scrollBehavior]).
///
/// On desktop, a vertical list, grid or scroll view whose content overflows
/// gets a [kGfScrollbarGutter] strip on its end side (left in RTL), and the
/// scrollbar is drawn in that strip instead of on top of the content.
class GfScrollBehavior extends MaterialScrollBehavior {
  const GfScrollBehavior({this.reserveGutter = true});

  /// Set to `false` for a scroll view whose own padding (inside the
  /// viewport) already leaves room for the scrollbar.
  final bool reserveGutter;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (!reserveGutter ||
        axisDirectionToAxis(details.direction) != Axis.vertical) {
      return super.buildScrollbar(context, child, details);
    }
    switch (getPlatform(context)) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return Scrollbar(
          controller: details.controller,
          child: _ScrollbarGutter(child: child),
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return child;
    }
  }

  @override
  bool shouldNotify(covariant GfScrollBehavior oldDelegate) =>
      reserveGutter != oldDelegate.reserveGutter;
}

/// Turns off the automatic scrollbar gutter for the scroll views in [child]
/// (their own padding already leaves room for the scrollbar).
class GfNoScrollbarGutter extends StatelessWidget {
  const GfNoScrollbarGutter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const GfScrollBehavior(reserveGutter: false),
      child: child,
    );
  }
}

class _ScrollbarGutter extends StatefulWidget {
  const _ScrollbarGutter({required this.child});

  final Widget child;

  @override
  State<_ScrollbarGutter> createState() => _ScrollbarGutterState();
}

class _ScrollbarGutterState extends State<_ScrollbarGutter> {
  bool _reserved = false;
  double? _viewportExtent;

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    final overflows =
        metrics.maxScrollExtent - metrics.minScrollExtent > 0.5;
    final viewportGrew = _viewportExtent != null &&
        metrics.viewportDimension > _viewportExtent! + 0.5;
    _viewportExtent = metrics.viewportDimension;

    // Narrowing the content can make it shorter (e.g. fixed-ratio grid
    // tiles), so dropping the gutter as soon as it stops overflowing could
    // flip it back and forth. Only release it when the viewport itself grows.
    final reserve = overflows || (_reserved && !viewportGrew);
    if (reserve != _reserved) setState(() => _reserved = reserve);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          end: _reserved ? kGfScrollbarGutter : 0,
        ),
        child: widget.child,
      ),
    );
  }
}
