import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_durations.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/window_full_screen.dart';

/// Enters / exits full screen for the app window.
class FullScreenToggle extends StatefulWidget {
  const FullScreenToggle({super.key});

  @override
  State<FullScreenToggle> createState() => _FullScreenToggleState();
}

class _FullScreenToggleState extends State<FullScreenToggle> {
  @override
  void initState() {
    super.initState();
    WindowFullScreen.sync();
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowFullScreen.isSupported) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: WindowFullScreen.state,
      builder: (context, isFullScreen, _) {
        final tooltip = isFullScreen
            ? 'common.exitFullScreen'.tr()
            : 'common.fullScreen'.tr();
        return Container(
          height: AppSpacing.controlHeight,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.pill,
            border: Border.all(color: AppColors.border),
          ),
          child: Tooltip(
            message: tooltip,
            child: Semantics(
              button: true,
              toggled: isFullScreen,
              label: tooltip,
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: WindowFullScreen.toggle,
                  customBorder: const CircleBorder(),
                  hoverColor: AppColors.hover,
                  child: AnimatedContainer(
                    duration: AppDurations.normal,
                    curve: Curves.easeOut,
                    width: AppSpacing.controlHeight - 8,
                    height: AppSpacing.controlHeight - 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFullScreen
                          ? AppColors.primary.withValues(alpha: 0.16)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      isFullScreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      size: 20,
                      color: isFullScreen
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
