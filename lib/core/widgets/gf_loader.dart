import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Animated GlassFlow loader with orbiting pulses and soft entrance motion.
///
/// Use for page / section / dialog loading — **not** for button spinners.
class GfLoader extends StatefulWidget {
  const GfLoader({
    super.key,
    this.size = 64,
    this.color,
    this.message,
    this.messageStyle,
  });

  /// Compact loader for dense UI (tables, dialogs).
  const GfLoader.compact({
    super.key,
    this.color,
    this.message,
    this.messageStyle,
  }) : size = 32;

  /// Large hero loader (auth / full-screen checks).
  const GfLoader.hero({
    super.key,
    this.color,
    this.message,
    this.messageStyle,
  }) : size = 88;

  final double size;
  final Color? color;
  final String? message;
  final TextStyle? messageStyle;

  @override
  State<GfLoader> createState() => _GfLoaderState();
}

class _GfLoaderState extends State<GfLoader> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.primary;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final isHero = widget.size >= 80;

    final loader = SizedBox(
      width: widget.size,
      height: widget.size,
      child: reduce
          ? CircularProgressIndicator(
              strokeWidth: widget.size < 40 ? 2.5 : 3.5,
              color: color,
            )
          : AnimatedBuilder(
              animation: Listenable.merge([_spin, _pulse]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _GfLoaderPainter(
                    progress: _spin.value,
                    pulse: Curves.easeInOut.transform(_pulse.value),
                    color: color,
                  ),
                );
              },
            ),
    );

    final messageStyle = widget.messageStyle ??
        (isHero
            ? AppTypography.localize(
                AppTypography.sectionTitle,
                context: context,
              ).copyWith(
                color: AppColors.textPrimary,
                fontSize: 20,
                height: 1.35,
                fontWeight: FontWeight.w600,
              )
            : AppTypography.localize(
                AppTypography.subtitle,
                context: context,
              ).copyWith(
                color: AppColors.textSecondary,
                fontSize: 15,
              ));

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        loader,
        if (widget.message != null && widget.message!.trim().isNotEmpty) ...[
          SizedBox(height: isHero ? 22 : (widget.size < 40 ? 10 : 16)),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isHero ? 320 : 260),
            child: Text(
              widget.message!,
              style: messageStyle,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );

    if (reduce) return content;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _enter, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.86, end: 1).animate(
          CurvedAnimation(parent: _enter, curve: Curves.easeOutBack),
        ),
        child: content,
      ),
    );
  }
}

/// Centered page / section loading body.
class GfPageLoader extends StatelessWidget {
  const GfPageLoader({super.key, this.message, this.size = 64});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GfLoader(size: size, message: message),
    );
  }
}

class _GfLoaderPainter extends CustomPainter {
  _GfLoaderPainter({
    required this.progress,
    required this.pulse,
    required this.color,
  });

  final double progress;
  final double pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    // Soft outer glow ring
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.12 + pulse * 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12;
    canvas.drawCircle(center, radius * (0.72 + pulse * 0.06), glowPaint);

    // Arc track
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.1
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius * 0.62, trackPaint);

    // Sweeping arc
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.05),
          color,
          color.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.55, 1.0],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.62),
      progress * math.pi * 2,
      math.pi * 1.15,
      false,
      sweepPaint,
    );

    // Orbiting dots
    const dots = 3;
    for (var i = 0; i < dots; i++) {
      final t = (progress + i / dots) % 1.0;
      final angle = t * math.pi * 2;
      final orbit = radius * (0.62 + (i == 0 ? pulse * 0.04 : 0));
      final pos = Offset(
        center.dx + math.cos(angle) * orbit,
        center.dy + math.sin(angle) * orbit,
      );
      final dotR = radius * (0.11 - i * 0.02) * (0.85 + pulse * 0.2);
      final dotPaint = Paint()
        ..color = color.withValues(alpha: 1 - i * 0.25);
      canvas.drawCircle(pos, dotR, dotPaint);
    }

    // Breathing core
    final corePaint = Paint()
      ..color = color.withValues(alpha: 0.22 + pulse * 0.2);
    canvas.drawCircle(center, radius * (0.16 + pulse * 0.05), corePaint);
    canvas.drawCircle(
      center,
      radius * 0.08,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _GfLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.color != color;
  }
}
