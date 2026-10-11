import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Two columns on wide dialogs, one column when narrow.
class DialogResponsiveRow extends StatelessWidget {
  const DialogResponsiveRow({
    super.key,
    required this.children,
    this.gap = 12,
    this.breakpoint = 420,
  });

  final List<Widget> children;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final width = maxW.isFinite ? maxW : MediaQuery.sizeOf(context).width;
        if (width < breakpoint || children.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

enum DialogBannerTone { info, warning, error, success }

class DialogInfoBanner extends StatelessWidget {
  const DialogInfoBanner({
    super.key,
    required this.message,
    this.tone = DialogBannerTone.info,
  });

  final String message;
  final DialogBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (tone) {
      DialogBannerTone.info => (AppColors.infoBg, AppColors.info, Icons.info_outline),
      DialogBannerTone.warning => (
          AppColors.warningBg,
          AppColors.warning,
          Icons.warning_amber_rounded
        ),
      DialogBannerTone.error => (AppColors.errorBg, AppColors.error, Icons.error_outline),
      DialogBannerTone.success => (
          AppColors.successBg,
          AppColors.success,
          Icons.check_circle_outline
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + caption title + large value box used inside form dialogs.
class DialogMetricBox extends StatelessWidget {
  const DialogMetricBox({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.hint,
    this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? hint;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  textDirection: TextDirection.ltr,
                  style: AppTypography.bodySemiBold
                      .copyWith(fontSize: 18, color: valueColor),
                ),
                if (hint != null)
                  Text(hint!, style: AppTypography.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Selectable filter chip (primary fill when selected).
class GfFilterChip extends StatelessWidget {
  const GfFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Fill the parent's constraints and center the label.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.onPrimary : AppColors.textPrimary;
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: expanded ? Alignment.center : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: AppTypography.label.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class GfChoiceOption<T> {
  const GfChoiceOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Single-choice row of [GfFilterChip]s.
class GfChoiceChips<T> extends StatelessWidget {
  const GfChoiceChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.expand = false,
  });

  final List<GfChoiceOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;

  /// Stretch the chips to share the full width equally.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    Widget chip(GfChoiceOption<T> o) => GfFilterChip(
          label: o.label,
          icon: o.icon,
          selected: o.value == value,
          onTap: onChanged == null ? null : () => onChanged!(o.value),
        );
    if (expand) {
      return Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 40,
                child: GfFilterChip(
                  label: options[i].label,
                  icon: options[i].icon,
                  selected: options[i].value == value,
                  expanded: true,
                  onTap: onChanged == null ? null : () => onChanged!(options[i].value),
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final o in options) chip(o)],
    );
  }
}
