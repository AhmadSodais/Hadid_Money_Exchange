import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_durations.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/day_night_transition.dart';
import '../providers/app_settings_provider.dart';

/// Sun / moon switch. The theme transition grows out of (sun) or closes in on
/// (moon) the tapped icon.
class ThemeModeToggle extends StatelessWidget {
  const ThemeModeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final isLight = context.select<AppSettingsProvider, bool>(
      (s) => s.isLightMode,
    );
    return Container(
      height: AppSpacing.controlHeight,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.pill,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThemeIconButton(
            mode: ThemeMode.light,
            selected: isLight,
            tooltip: 'settings.lightMode'.tr(),
          ),
          const SizedBox(width: 2),
          _ThemeIconButton(
            mode: ThemeMode.dark,
            selected: !isLight,
            tooltip: 'settings.darkMode'.tr(),
          ),
        ],
      ),
    );
  }
}

class _ThemeIconButton extends StatelessWidget {
  const _ThemeIconButton({
    required this.mode,
    required this.selected,
    required this.tooltip,
  });

  final ThemeMode mode;
  final bool selected;
  final String tooltip;

  static const Color _sunColor = Color(0xFFE8A317);

  bool get _isSun => mode == ThemeMode.light;

  void _select(BuildContext context) {
    final settings = context.read<AppSettingsProvider>();
    if (settings.themeMode == mode) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      DayNightThemeTransition.revealFrom(
        context,
        globalCenter: box.localToGlobal(box.size.center(Offset.zero)),
        radius: box.size.shortestSide / 2,
      );
    }
    settings.setThemeMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _isSun ? _sunColor : AppColors.primary;
    final icon = _isSun
        ? (selected ? Icons.light_mode_rounded : Icons.light_mode_outlined)
        : (selected ? Icons.dark_mode_rounded : Icons.dark_mode_outlined);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _select(context),
            customBorder: const CircleBorder(),
            hoverColor: AppColors.hover,
            child: AnimatedContainer(
              duration: AppDurations.normal,
              curve: Curves.easeOut,
              width: AppSpacing.controlHeight - 8,
              height: AppSpacing.controlHeight - 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? activeColor.withValues(alpha: 0.16)
                    : Colors.transparent,
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected ? activeColor : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
