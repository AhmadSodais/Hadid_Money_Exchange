import 'dart:async';

import 'package:flutter/material.dart';

import 'app_motion.dart';

class MotionEntrance extends StatefulWidget {
  const MotionEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    /// Pixels; negative = enter from above (top → bottom).
    this.fromY = -24,
  });

  /// Staggered entrance from page header (index 0) toward the bottom.
  factory MotionEntrance.stagger({
    Key? key,
    required int index,
    required Widget child,
    int stepMs = 120,
    int maxIndex = 10,
    double fromY = -24,
  }) {
    final clamped = index < 0 ? 0 : (index > maxIndex ? maxIndex : index);
    return MotionEntrance(
      key: key,
      delay: Duration(milliseconds: clamped * stepMs),
      fromY: fromY,
      child: child,
    );
  }

  final Widget child;
  final Duration delay;
  final double fromY;

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.page);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _curve,
      child: AnimatedBuilder(
        animation: _curve,
        // Whole pixels only: fractional offsets make text and borders shimmer.
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (widget.fromY * (1 - _curve.value)).roundToDouble()),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class MotionPress extends StatefulWidget {
  const MotionPress({super.key, required this.child});
  final Widget child;
  @override
  State<MotionPress> createState() => _MotionPressState();
}

class _MotionPressState extends State<MotionPress> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => _pressed = true),
    onPointerUp: (_) => setState(() => _pressed = false),
    onPointerCancel: (_) => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed && !AppMotion.reduced(context) ? .975 : 1,
      duration: AppMotion.duration(context, AppMotion.fast),
      curve: AppMotion.fastCurve,
      child: widget.child,
    ),
  );
}

class AnimatedValue extends StatelessWidget {
  const AnimatedValue(this.value, {super.key, this.style, this.textAlign});
  final String value;
  final TextStyle? style;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.duration(context, AppMotion.normal),
    switchInCurve: AppMotion.fastCurve,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .15),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: Text(
      value,
      key: ValueKey(value),
      style: style,
      textAlign: textAlign,
    ),
  );
}

class AnimatedStatusIndicator extends StatefulWidget {
  const AnimatedStatusIndicator({super.key, required this.state});
  final String state;
  @override
  State<AnimatedStatusIndicator> createState() =>
      _AnimatedStatusIndicatorState();
}

class _AnimatedStatusIndicatorState extends State<AnimatedStatusIndicator>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _visible = true;
  bool get _active => widget.state == 'TRACKING' || widget.state == 'READY';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
  }

  @override
  void didUpdateWidget(covariant AnimatedStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    final reduced = AppMotion.reduced(context);
    if (_active && _visible && !reduced) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  Color _color() => switch (widget.state) {
    'ERROR' || 'OFF' => Colors.red,
    'TRACKING' || 'SEARCHING' => Colors.orange,
    _ => Colors.green,
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, _) => Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: _color(),
        shape: BoxShape.circle,
        boxShadow: _active
            ? [
                BoxShadow(
                  color: _color().withValues(
                    alpha: .25 + _controller.value * .25,
                  ),
                  blurRadius: 4 + _controller.value * 5,
                ),
              ]
            : null,
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }
}

class AnimatedGpsIcon extends StatefulWidget {
  const AnimatedGpsIcon({super.key, required this.state, this.size = 24});
  final String state;
  final double size;
  @override
  State<AnimatedGpsIcon> createState() => _AnimatedGpsIconState();
}

class _AnimatedGpsIconState extends State<AnimatedGpsIcon>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  void _sync() {
    if (widget.state == 'SEARCHING' &&
        _visible &&
        !AppMotion.reduced(context)) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AnimatedGpsIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.duration(context, AppMotion.normal),
    transitionBuilder: (child, animation) => ScaleTransition(
      scale: animation,
      child: FadeTransition(opacity: animation, child: child),
    ),
    child: RotationTransition(
      key: ValueKey(widget.state),
      turns: widget.state == 'SEARCHING'
          ? _controller
          : const AlwaysStoppedAnimation(0),
      child: Icon(
        widget.state == 'READY'
            ? Icons.gps_fixed
            : widget.state == 'SEARCHING'
            ? Icons.gps_not_fixed
            : Icons.gps_off,
        size: widget.size,
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }
}
