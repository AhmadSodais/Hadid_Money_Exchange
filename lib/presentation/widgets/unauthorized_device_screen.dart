import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_constants.dart';
import '../../core/security/authorized_devices.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_toast.dart';

/// Full-screen block when this workstation is not allowed to open the app.
class UnauthorizedDeviceScreen extends StatefulWidget {
  const UnauthorizedDeviceScreen({super.key});

  @override
  State<UnauthorizedDeviceScreen> createState() => _UnauthorizedDeviceScreenState();
}

class _UnauthorizedDeviceScreenState extends State<UnauthorizedDeviceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Widget _stagger(int index, Widget child) {
    final start = (index * 0.12).clamp(0.0, 0.7);
    final animation = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, math.min(start + 0.45, 1), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _AmbientBackground(animation: _ambient),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _stagger(0, const _Brand()),
                      const SizedBox(height: 22),
                      _GlassCard(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _stagger(1, _LockEmblem(animation: _ambient)),
                            const SizedBox(height: 18),
                            _stagger(2, const _Badge()),
                            const SizedBox(height: 14),
                            _stagger(3, const _Headline()),
                            const SizedBox(height: 26),
                            _stagger(4, const _SectionDivider()),
                            const SizedBox(height: 18),
                            _stagger(
                              5,
                              const _ContactTile(
                                name: AuthorizedDevices.supportName,
                                phone: AuthorizedDevices.supportPhone,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _stagger(
                        6,
                        Text(
                          AppConstants.appNameLatin,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMuted.withValues(alpha: 0.7),
                            letterSpacing: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final a = animation.value * 2 * math.pi;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.background, AppColors.backgroundEnd],
                ),
              ),
            ),
            _Glow(
              alignment: Alignment(-0.8 + 0.25 * math.cos(a), -0.7 + 0.2 * math.sin(a)),
              color: AppColors.primary,
              size: 520,
            ),
            _Glow(
              alignment: Alignment(0.85 + 0.2 * math.sin(a), 0.75 + 0.2 * math.cos(a)),
              color: AppColors.info,
              size: 460,
            ),
            _Glow(
              alignment: Alignment(0.6 * math.sin(a * 2), -0.1),
              color: AppColors.accent,
              size: 300,
              strength: 0.08,
            ),
            CustomPaint(painter: _DotGridPainter(AppColors.textMuted.withValues(alpha: 0.08))),
          ],
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.alignment,
    required this.color,
    required this.size,
    this.strength = 0.16,
  });

  final Alignment alignment;
  final Color color;
  final double size;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: strength), color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 26.0;
    final paint = Paint()..color = color;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => oldDelegate.color != color;
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            AppAssets.hadidLogo,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 44,
              height: 44,
              color: AppColors.primary.withValues(alpha: 0.15),
              child: Icon(Icons.hexagon_outlined, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          AppConstants.appName,
          style: AppTypography.localize(AppTypography.brand, context: context).copyWith(
            fontSize: 20,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
      decoration: BoxDecoration(
        color: AppColors.modal,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 48,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 60,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LockEmblem extends StatelessWidget {
  const _LockEmblem({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary;
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final pulse = Curves.easeOut.transform((animation.value * 6) % 1);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 84 + 56 * pulse,
                height: 84 + 56 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16 * (1 - pulse)),
                ),
              ),
              Transform.rotate(
                angle: animation.value * 2 * math.pi,
                child: CustomPaint(
                  size: const Size.square(118),
                  painter: _OrbitPainter(accent),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, Color.lerp(accent, AppColors.info, 0.55)!],
            ),
            boxShadow: [
              BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: Icon(Icons.lock_person_rounded, size: 40, color: AppColors.onPrimary),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.45);
    const segments = 24;
    const sweep = 2 * math.pi / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * 0.55,
        false,
        ring,
      );
    }
    canvas.drawCircle(
      center + Offset(radius, 0),
      4,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) => oldDelegate.color != color;
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    final tone = AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 14, color: tone),
          const SizedBox(width: 6),
          Text(
            'deviceAuth.badge'.tr(),
            style: AppTypography.localize(AppTypography.caption, context: context).copyWith(
              color: tone,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'deviceAuth.title'.tr(),
          textAlign: TextAlign.center,
          style: AppTypography.localize(AppTypography.display, context: context).copyWith(
            fontSize: 26,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'deviceAuth.message'.tr(),
          textAlign: TextAlign.center,
          style: AppTypography.localize(AppTypography.body, context: context).copyWith(
            color: AppColors.textSecondary,
            fontSize: 15,
            height: 1.7,
          ),
        ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    Widget line() => Expanded(
          child: Container(height: 1, color: AppColors.divider),
        );
    return Row(
      children: [
        line(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'deviceAuth.contactTitle'.tr(),
            style: AppTypography.localize(AppTypography.caption, context: context).copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        line(),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.name, required this.phone});

  final String name;
  final String phone;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!context.mounted) return;
    GfToast.success(context, 'deviceAuth.phoneCopied'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.primary;
    final radius = BorderRadius.circular(16);
    return Material(
      color: accent.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: accent.withValues(alpha: 0.22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.16),
                ),
                child: Icon(Icons.support_agent_rounded, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.localize(AppTypography.bodySemiBold, context: context)
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      textDirection: TextDirection.ltr,
                      style: AppTypography.localize(AppTypography.kpiValue, context: context).copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: () => _copy(context),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: Text(
                  'deviceAuth.copyPhone'.tr(),
                  style: AppTypography.localize(AppTypography.button, context: context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
