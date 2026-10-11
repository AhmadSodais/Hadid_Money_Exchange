import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Shared button sizing helper.
ButtonStyle _gfButtonStyle({
  required BuildContext context,
  required Color foreground,
  required Color background,
  Color? hoverBackground,
  Color? borderColor,
  EdgeInsetsGeometry? padding,
  double minHeight = AppSpacing.controlHeight,
}) {
  final fontFamily = AppTypography.fontFamilyOf(context);
  return ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return AppColors.textMuted;
      }
      return foreground;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return AppColors.input;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return hoverBackground ??
            Color.alphaBlend(AppColors.hover, background);
      }
      return background;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: AppColors.borderActive, width: 2);
      }
      return borderColor != null
          ? BorderSide(color: borderColor)
          : BorderSide.none;
    }),
    minimumSize: WidgetStatePropertyAll(Size(0, minHeight)),
    maximumSize: WidgetStatePropertyAll(Size(double.infinity, minHeight)),
    fixedSize: WidgetStatePropertyAll(Size.fromHeight(minHeight)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: WidgetStatePropertyAll(
      padding ?? const EdgeInsets.symmetric(horizontal: 16),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: AppRadius.button),
    ),
    elevation: const WidgetStatePropertyAll(0),
    textStyle: WidgetStatePropertyAll(
      AppTypography.button.copyWith(fontFamily: fontFamily),
    ),
    overlayColor: WidgetStateProperty.all(AppColors.hover),
  );
}

/// Primary lime filled button.
class GfPrimaryButton extends StatelessWidget {
  const GfPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    this.isLoading = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonLabel(
      label: label,
      icon: icon,
      isLoading: isLoading,
      spinnerColor: AppColors.onPrimary,
      foreground: AppColors.onPrimary,
      iconSize: compact ? 16 : 18,
    );

    final button = FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: _gfButtonStyle(
        context: context,
        foreground: AppColors.onPrimary,
        background: AppColors.primary,
        hoverBackground: AppColors.primaryHover,
        minHeight: compact ? 36 : AppSpacing.controlHeight,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10)
            : null,
      ),
      child: child,
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Outlined secondary button.
class GfSecondaryButton extends StatelessWidget {
  const GfSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    this.isLoading = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonLabel(
      label: label,
      icon: icon,
      isLoading: isLoading,
      spinnerColor: AppColors.isLight
          ? AppColors.lightPrimary900
          : AppColors.textPrimary,
      foreground: AppColors.isLight
          ? AppColors.lightPrimary900
          : AppColors.textPrimary,
      iconSize: compact ? 16 : 18,
    );

    final button = OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: _gfButtonStyle(
        context: context,
        foreground: AppColors.isLight
            ? AppColors.lightPrimary900
            : AppColors.textPrimary,
        background: Colors.transparent,
        borderColor: AppColors.secondaryBorder,
        minHeight: compact ? 36 : AppSpacing.controlHeight,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10)
            : null,
      ),
      child: child,
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Danger outlined button (destructive actions).
class GfDangerButton extends StatelessWidget {
  const GfDangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = false,
    this.isLoading = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final bool isLoading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = _ButtonLabel(
      label: label,
      icon: icon,
      isLoading: isLoading,
      spinnerColor: AppColors.error,
      foreground: AppColors.error,
      iconSize: compact ? 16 : 18,
    );

    final button = OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: _gfButtonStyle(
        context: context,
        foreground: AppColors.error,
        background: AppColors.dangerZoneBg,
        borderColor: AppColors.dangerZoneBorder,
        minHeight: compact ? 36 : AppSpacing.controlHeight,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 10)
            : null,
      ),
      child: child,
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Compact icon-only button.
class GfIconButton extends StatelessWidget {
  const GfIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = AppSpacing.controlHeight,
    this.iconSize = 20,
    this.color,
    this.backgroundColor,
    this.border = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? backgroundColor;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: backgroundColor ?? Colors.transparent,
      borderRadius: AppRadius.button,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.button,
        hoverColor: AppColors.hover,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.button,
            border: border ? Border.all(color: AppColors.border) : null,
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: color ?? AppColors.textSecondary,
          ),
        ),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({
    required this.label,
    required this.isLoading,
    required this.spinnerColor,
    required this.foreground,
    this.icon,
    this.iconSize = 18,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;
  final Color spinnerColor;
  final Color foreground;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: spinnerColor,
        ),
      );
    }

    final textStyle = AppTypography.button.copyWith(
      fontFamily: AppTypography.fontFamilyOf(context),
      color: foreground,
    );

    if (icon == null) {
      return Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ],
      ),
    );
  }
}
