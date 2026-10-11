import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../utils/window_title_bar.dart';
import 'app_colors.dart';
import 'app_durations.dart';

/// Animates theme changes as a circular reveal.
///
/// Switching to light grows a circle of daylight outward from the origin;
/// switching to dark shrinks the remaining daylight inward onto the origin.
/// The origin is the screen center unless a control calls [revealFrom] just
/// before changing the theme (e.g. the Overview sun / moon toggle).
///
/// The theme actually on screen is snapshotted first. Only then does the app
/// rebuild in the new theme, underneath a copy of the previous frame that is
/// clipped by the moving circle. The app below the overlay is not rebuilt per
/// frame, and the static [AppColors] palette always matches [ThemeData].
class DayNightThemeTransition extends StatefulWidget {
  const DayNightThemeTransition({
    super.key,
    required this.variant,
    required this.builder,
    this.reduceMotion = false,
  });

  final AppThemeVariant variant;

  /// Shortens the transition to a plain cross-fade. The platform
  /// "disable animations" accessibility flag has the same effect.
  final bool reduceMotion;

  /// Builds the app for the theme variant currently on screen.
  final Widget Function(BuildContext context, AppThemeVariant variant) builder;

  /// Centers the next theme transition on [globalCenter] (global coordinates),
  /// starting from a circle of [radius] so it grows out of the tapped control.
  /// Call immediately before changing the theme mode.
  static void revealFrom(
    BuildContext context, {
    required Offset globalCenter,
    double radius = 0,
  }) {
    context
        .findAncestorStateOfType<_DayNightThemeTransitionState>()
        ?._requestOrigin(globalCenter, radius);
  }

  @override
  State<DayNightThemeTransition> createState() =>
      _DayNightThemeTransitionState();
}

class _DayNightThemeTransitionState extends State<DayNightThemeTransition>
    with SingleTickerProviderStateMixin {
  static const int _maxCaptureAttempts = 10;

  /// An origin request older than this is ignored (the theme never changed).
  static const Duration _originRequestTtl = Duration(seconds: 2);

  final GlobalKey _boundaryKey = GlobalKey();
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addListener(_syncTitleBar)
    ..addStatusListener(_onStatus);

  late AppThemeVariant _displayed = widget.variant;
  AppThemeVariant? _pendingTarget;
  int _generation = 0;

  Offset? _requestedOrigin;
  double _requestedRadius = 0;
  final Stopwatch _requestAge = Stopwatch();

  ui.Image? _snapshot;
  AppThemeVariant _fromVariant = AppThemeVariant.light;
  AppThemeVariant _toVariant = AppThemeVariant.light;
  bool _minimal = false;
  _Reveal _reveal = const _Reveal(contract: false);
  CurvedAnimation? _curve;

  Animation<double> get _progress => _curve ?? _controller;

  bool get _platformDisablesAnimations => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  void _requestOrigin(Offset globalCenter, double radius) {
    final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    _requestedOrigin = box != null && box.hasSize
        ? box.globalToLocal(globalCenter)
        : globalCenter;
    _requestedRadius = radius;
    _requestAge
      ..reset()
      ..start();
  }

  _Reveal _takeReveal({required bool toDark}) {
    final fresh =
        _requestedOrigin != null && _requestAge.elapsed < _originRequestTtl;
    final reveal = _Reveal(
      contract: toDark,
      origin: fresh ? _requestedOrigin : null,
      startRadius: fresh ? _requestedRadius : 0,
    );
    _requestedOrigin = null;
    _requestAge.stop();
    return reveal;
  }

  @override
  void didUpdateWidget(DayNightThemeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.variant;
    if (target == _pendingTarget) return;
    if (target == _displayed && _snapshot == null) {
      _pendingTarget = null;
      _generation++;
      return;
    }
    if (target == _displayed) return;
    _scheduleTransition(target);
  }

  void _scheduleTransition(AppThemeVariant target) {
    _pendingTarget = target;
    final generation = ++_generation;
    _captureAfterFrame(generation, target, 0);
  }

  void _captureAfterFrame(int generation, AppThemeVariant target, int attempt) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _capture(generation, target, attempt);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _capture(int generation, AppThemeVariant target, int attempt) {
    if (!mounted || generation != _generation) return;

    final boundary = _boundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        !boundary.attached ||
        !boundary.hasSize ||
        boundary.size.isEmpty ||
        // `debugNeedsPaint` throws outside debug builds.
        (kDebugMode && boundary.debugNeedsPaint)) {
      _retryOrGiveUp(generation, target, attempt);
      return;
    }

    final pixelRatio = View.of(context).devicePixelRatio;
    _readSnapshot(boundary, pixelRatio, generation, target, attempt);
  }

  Future<void> _readSnapshot(
    RenderRepaintBoundary boundary,
    double pixelRatio,
    int generation,
    AppThemeVariant target,
    int attempt,
  ) async {
    ui.Image? image;
    try {
      image = await boundary.toImage(pixelRatio: pixelRatio);
    } catch (e, st) {
      if (!mounted || generation != _generation) return;
      if (attempt + 1 >= _maxCaptureAttempts) {
        debugPrint('Theme transition snapshot failed: $e\n$st');
      }
      _retryOrGiveUp(generation, target, attempt);
      return;
    }

    if (!mounted || generation != _generation) {
      image.dispose();
      return;
    }
    _commit(target, image);
  }

  void _retryOrGiveUp(int generation, AppThemeVariant target, int attempt) {
    if (!mounted || generation != _generation) return;
    if (attempt + 1 < _maxCaptureAttempts) {
      _captureAfterFrame(generation, target, attempt + 1);
      return;
    }
    _commit(target, null);
  }

  void _commit(AppThemeVariant target, ui.Image? image) {
    _pendingTarget = null;
    if (!mounted) {
      image?.dispose();
      return;
    }
    final toDark = !target.isLight;
    final reveal = _takeReveal(toDark: toDark);
    if (image == null) {
      _endTransition();
      setState(() => _displayed = target);
      _rebuildAll(target);
      return;
    }

    final previous = _snapshot;
    _controller.stop();
    _controller.value = 0;
    _curve?.dispose();
    _fromVariant = _displayed;
    _toVariant = target;
    _reveal = reveal;
    _minimal = widget.reduceMotion || _platformDisablesAnimations;
    _controller.duration = _minimal
        ? AppDurations.themeTransitionReduced
        : AppDurations.themeTransition;
    _curve = CurvedAnimation(
      parent: _controller,
      curve: _minimal ? Curves.easeOut : Curves.easeInOutCubic,
    );

    WindowTitleBar.hold(
      color: AppColors.backgroundFor(_fromVariant),
      brightness: _fromVariant.brightness,
    );
    setState(() {
      _displayed = target;
      _snapshot = image;
    });
    previous?.dispose();
    _rebuildAll(target);

    // Start after the full rebuild frame so its cost doesn't skip the
    // opening of the reveal.
    final generation = _generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation || _snapshot != image) return;
      _controller.forward(from: 0);
    });
  }

  /// Widgets that read the static [AppColors] palette (rather than
  /// `Theme.of`) don't depend on anything that changes with the theme, so
  /// Flutter would otherwise leave them in the old colors until something
  /// else rebuilds them. Marks every descendant dirty so the whole app
  /// rebuilds once, in the new palette, under the snapshot.
  void _rebuildAll(AppThemeVariant target) {
    AppColors.applyVariant(target);
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    (context as Element).visitChildren(markDirty);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    // A newer switch is waiting on its own snapshot; don't tear this one down.
    if (_pendingTarget != null) return;
    setState(_endTransition);
  }

  void _endTransition() {
    _controller.stop();
    _snapshot?.dispose();
    _snapshot = null;
    _curve?.dispose();
    _curve = null;
    WindowTitleBar.release();
  }

  void _syncTitleBar() {
    if (_snapshot == null) return;
    final box = _boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;

    final size = box.size;
    final t = _progress.value;
    final revealed = _minimal
        ? t >= 0.5
        : _reveal.showsNewAt(Offset(size.width / 2, 0), size, t);
    final shown = revealed ? _toVariant : _fromVariant;
    WindowTitleBar.hold(
      color: AppColors.backgroundFor(shown),
      brightness: shown.brightness,
    );
  }

  @override
  void dispose() {
    _generation++;
    _endTransition();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return RepaintBoundary(
      key: _boundaryKey,
      child: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          // Cached on its own so the circle redraw does not repaint the app.
          RepaintBoundary(child: widget.builder(context, _displayed)),
          if (snapshot != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  isComplex: true,
                  willChange: true,
                  painter: _CircleRevealPainter(
                    snapshot: snapshot,
                    progress: _progress,
                    reveal: _reveal,
                    minimal: _minimal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Extra pixels past the farthest corner so the end state fully covers it.
const double _cornerSlop = 2;

/// Circle geometry. Expanding: the new theme is inside the circle. Contracting:
/// the old theme is inside the circle, which shrinks onto the origin.
@immutable
class _Reveal {
  const _Reveal({required this.contract, this.origin, this.startRadius = 0});

  final bool contract;

  /// Local to the transition; `null` means the screen center.
  final Offset? origin;
  final double startRadius;

  Offset center(Size size) => origin ?? size.center(Offset.zero);

  double maxRadius(Size size) {
    final c = center(size);
    final farthest = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((corner) => (corner - c).distance).reduce(math.max);
    return farthest + _cornerSlop;
  }

  double radius(Size size, double t) {
    final max = maxRadius(size);
    return contract
        ? ui.lerpDouble(max, 0, t)!
        : ui.lerpDouble(math.min(startRadius, max), max, t)!;
  }

  bool showsNewAt(Offset point, Size size, double t) {
    final inside = (point - center(size)).distance <= radius(size, t);
    return contract ? !inside : inside;
  }

  @override
  bool operator ==(Object other) =>
      other is _Reveal &&
      other.contract == contract &&
      other.origin == origin &&
      other.startRadius == startRadius;

  @override
  int get hashCode => Object.hash(contract, origin, startRadius);
}

class _CircleRevealPainter extends CustomPainter {
  _CircleRevealPainter({
    required this.snapshot,
    required this.progress,
    required this.reveal,
    required this.minimal,
  }) : super(repaint: progress);

  final ui.Image snapshot;
  final Animation<double> progress;
  final _Reveal reveal;
  final bool minimal;

  static const Color _sunlight = Color(0xFFFFC66B);
  static const Color _moonlight = Color(0xFF8FA8FF);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = progress.value.clamp(0.0, 1.0);
    final rect = Offset.zero & size;
    final src = Rect.fromLTWH(
      0,
      0,
      snapshot.width.toDouble(),
      snapshot.height.toDouble(),
    );
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;

    if (minimal) {
      imagePaint.color = Color.fromRGBO(0, 0, 0, 1 - t);
      canvas.drawImageRect(snapshot, src, rect, imagePaint);
      return;
    }

    final c = reveal.center(size);
    final r = reveal.radius(size, t);
    final circle = Rect.fromCircle(center: c, radius: r);

    if (reveal.contract) {
      // The previous (light) frame survives only inside the shrinking circle.
      if (r > 0) {
        canvas.save();
        canvas.clipPath(Path()..addOval(circle));
        canvas.drawImageRect(snapshot, src, rect, imagePaint);
        canvas.restore();
      }
    } else if (r < reveal.maxRadius(size)) {
      // The previous (dark) frame survives only outside the growing circle.
      canvas.save();
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect)
          ..addOval(circle),
      );
      canvas.drawImageRect(snapshot, src, rect, imagePaint);
      canvas.restore();
    }

    _paintEdgeGlow(canvas, c, r, t);
  }

  /// Soft sunlight / moonlight halo riding the edge of the circle.
  void _paintEdgeGlow(Canvas canvas, Offset c, double r, double t) {
    final strength = math.sin(math.pi * t);
    if (strength <= 0.01 || r <= 1) return;
    const spread = 26.0;
    final outer = r + spread;
    final inner = math.max(0.0, r - spread);
    final color = reveal.contract ? _moonlight : _sunlight;
    canvas.drawCircle(
      c,
      (inner + outer) / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outer - inner
        ..shader = ui.Gradient.radial(
          c,
          outer,
          [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.32 * strength),
            color.withValues(alpha: 0),
          ],
          [inner / outer, r / outer, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_CircleRevealPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.progress != progress ||
      oldDelegate.reveal != reveal ||
      oldDelegate.minimal != minimal;
}
