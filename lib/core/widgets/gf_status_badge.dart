import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';

/// Semantic status variants for inventory, payments, and orders.
enum GfStatusVariant {
  inStock,
  lowStock,
  outOfStock,
  paid,
  partial,
  unpaid,
  draft,
  confirmed,
  completed,
  cancelled,
  pending,
  processing,
  custom,
}

/// Colored pill badge for status labels.
class GfStatusBadge extends StatelessWidget {
  const GfStatusBadge({
    super.key,
    required this.label,
    this.variant = GfStatusVariant.custom,
    this.color,
    this.compact = false,
  });

  /// Convenience constructors for common statuses.
  const GfStatusBadge.inStock({super.key, this.label = '', this.compact = false})
      : variant = GfStatusVariant.inStock,
        color = null;

  const GfStatusBadge.lowStock({super.key, this.label = '', this.compact = false})
      : variant = GfStatusVariant.lowStock,
        color = null;

  const GfStatusBadge.outOfStock({
    super.key,
    this.label = '',
    this.compact = false,
  })  : variant = GfStatusVariant.outOfStock,
        color = null;

  const GfStatusBadge.paid({super.key, this.label = '', this.compact = false})
      : variant = GfStatusVariant.paid,
        color = null;

  const GfStatusBadge.partial({super.key, this.label = '', this.compact = false})
      : variant = GfStatusVariant.partial,
        color = null;

  const GfStatusBadge.unpaid({super.key, this.label = '', this.compact = false})
      : variant = GfStatusVariant.unpaid,
        color = null;

  final String label;
  final GfStatusVariant variant;
  final Color? color;
  final bool compact;

  Color get _tone {
    if (color != null) return color!;
    return switch (variant) {
      GfStatusVariant.inStock ||
      GfStatusVariant.paid ||
      GfStatusVariant.completed ||
      GfStatusVariant.confirmed =>
        AppColors.success,
      GfStatusVariant.lowStock ||
      GfStatusVariant.partial ||
      GfStatusVariant.pending ||
      GfStatusVariant.processing =>
        AppColors.warning,
      GfStatusVariant.outOfStock ||
      GfStatusVariant.unpaid ||
      GfStatusVariant.cancelled =>
        AppColors.error,
      GfStatusVariant.draft => AppColors.textMuted,
      GfStatusVariant.custom => AppColors.info,
    };
  }

  String get _displayLabel {
    if (label.isNotEmpty && variant == GfStatusVariant.custom) return label;
    if (label.isNotEmpty) return label;
    return switch (variant) {
      GfStatusVariant.inStock => 'status.inStock'.tr(),
      GfStatusVariant.lowStock => 'status.lowStock'.tr(),
      GfStatusVariant.outOfStock => 'status.outOfStock'.tr(),
      GfStatusVariant.paid => 'status.paid'.tr(),
      GfStatusVariant.partial => 'status.partial'.tr(),
      GfStatusVariant.unpaid => 'status.unpaid'.tr(),
      GfStatusVariant.draft => 'status.draft'.tr(),
      GfStatusVariant.confirmed => 'status.confirmed'.tr(),
      GfStatusVariant.completed => 'status.completed'.tr(),
      GfStatusVariant.cancelled => 'status.cancelled'.tr(),
      GfStatusVariant.pending => 'status.pending'.tr(),
      GfStatusVariant.processing => 'status.processing'.tr(),
      GfStatusVariant.custom => label,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tone;
    final bg = color != null
        ? color!.withValues(alpha: 0.14)
        : AppColors.isLight
            ? switch (variant) {
                GfStatusVariant.inStock ||
                GfStatusVariant.paid ||
                GfStatusVariant.completed ||
                GfStatusVariant.confirmed =>
                  AppColors.successBg,
                GfStatusVariant.lowStock ||
                GfStatusVariant.partial ||
                GfStatusVariant.pending ||
                GfStatusVariant.processing =>
                  AppColors.warningBg,
                GfStatusVariant.outOfStock ||
                GfStatusVariant.unpaid ||
                GfStatusVariant.cancelled =>
                  AppColors.errorBg,
                GfStatusVariant.draft => AppColors.surface,
                GfStatusVariant.custom => AppColors.infoBg,
              }
            : tone.withValues(alpha: 0.14);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.pill,
        border: Border.all(
          color: tone.withValues(alpha: AppColors.isLight ? 0.25 : 0.35),
        ),
      ),
      child: Text(
        _displayLabel,
        style: AppTypography.localize(
          AppTypography.caption.copyWith(
            color: tone,
            fontWeight: FontWeight.w600,
            fontSize: compact ? 11 : 12,
            height: 1.2,
          ),
          context: context,
        ),
      ),
    );
  }
}

/// Maps a free-form status string to a [GfStatusBadge].
GfStatusBadge gfStatusBadgeFromString(String status, {bool compact = false}) {
  final key = status.trim().toLowerCase().replaceAll('_', ' ');
  return switch (key) {
    'in stock' || 'instock' => GfStatusBadge.inStock(compact: compact),
    'low stock' || 'lowstock' => GfStatusBadge.lowStock(compact: compact),
    'out of stock' || 'outofstock' || 'out ofstock' =>
      GfStatusBadge.outOfStock(compact: compact),
    'paid' => GfStatusBadge.paid(compact: compact),
    'partial' || 'partially paid' => GfStatusBadge.partial(compact: compact),
    'unpaid' => GfStatusBadge.unpaid(compact: compact),
    'draft' => GfStatusBadge(
        label: 'status.draft'.tr(),
        variant: GfStatusVariant.draft,
        compact: compact,
      ),
    'confirmed' => GfStatusBadge(
        label: 'status.confirmed'.tr(),
        variant: GfStatusVariant.confirmed,
        compact: compact,
      ),
    'completed' || 'complete' => GfStatusBadge(
        label: 'status.completed'.tr(),
        variant: GfStatusVariant.completed,
        compact: compact,
      ),
    'cancelled' || 'canceled' => GfStatusBadge(
        label: 'status.cancelled'.tr(),
        variant: GfStatusVariant.cancelled,
        compact: compact,
      ),
    'pending' => GfStatusBadge(
        label: 'status.pending'.tr(),
        variant: GfStatusVariant.pending,
        compact: compact,
      ),
    'processing' => GfStatusBadge(
        label: 'status.processing'.tr(),
        variant: GfStatusVariant.processing,
        compact: compact,
      ),
    'ready' => GfStatusBadge(
        label: 'status.ready'.tr(),
        compact: compact,
      ),
    'returned' => GfStatusBadge(
        label: 'status.returned'.tr(),
        compact: compact,
      ),
    'in production' || 'inproduction' => GfStatusBadge(
        label: 'status.inProduction'.tr(),
        variant: GfStatusVariant.processing,
        compact: compact,
      ),
    'cutting' => GfStatusBadge(
        label: 'status.cutting'.tr(),
        variant: GfStatusVariant.processing,
        compact: compact,
      ),
    'delivered' => GfStatusBadge(
        label: 'status.delivered'.tr(),
        variant: GfStatusVariant.completed,
        compact: compact,
      ),
    _ => GfStatusBadge(label: status, compact: compact),
  };
}
