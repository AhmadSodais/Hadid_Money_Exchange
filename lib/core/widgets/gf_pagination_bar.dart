import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/gf_pagination.dart';

class GfPaginationBar extends StatelessWidget {
  const GfPaginationBar({
    super.key,
    required this.page,
    required this.pageSize,
    required this.totalItems,
    this.itemLabel,
    this.onPageChanged,
    this.compact = false,
  });

  final int page;
  final int pageSize;
  final int totalItems;
  final String? itemLabel;
  final ValueChanged<int>? onPageChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (totalItems <= 0 || onPageChanged == null) {
      return const SizedBox.shrink();
    }

    final pages = GfPagination.totalPages(totalItems: totalItems, pageSize: pageSize);
    final current = GfPagination.clampPage(page, pages);
    final range = GfPagination.itemRange(
      page: current,
      pageSize: pageSize,
      totalItems: totalItems,
    );

    final rangeText = itemLabel != null && itemLabel!.isNotEmpty
        ? 'common.showingRangeItems'.tr(
            namedArgs: {
              'from': '${range.from}',
              'to': '${range.to}',
              'total': '$totalItems',
              'items': itemLabel!,
            },
          )
        : 'common.showingRange'.tr(
            namedArgs: {
              'from': '${range.from}',
              'to': '${range.to}',
              'total': '$totalItems',
            },
          );

    final buttons = GfPagination.pageButtons(
      currentPage: current,
      totalPages: pages,
    );

    // Keep a stable single-row footer so body height math stays accurate.
    return Container(
      height: GfPagination.footerMinHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: GfPagination.footerHorizontalPadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 420;
          final controls = _Controls(
            current: current,
            pages: pages,
            buttons: buttons,
            onPageChanged: onPageChanged!,
          );

          if (narrow || compact) {
            return Row(
              children: [
                Expanded(
                  child: Text(
                    rangeText,
                    style: _rangeStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: controls,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Text(
                  rangeText,
                  style: _rangeStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              controls,
            ],
          );
        },
      ),
    );
  }

  TextStyle get _rangeStyle => AppTypography.body.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.current,
    required this.pages,
    required this.buttons,
    required this.onPageChanged,
  });

  final int current;
  final int pages;
  final List<int?> buttons;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavButton(
          icon: Icons.chevron_left,
          enabled: current > 1,
          tooltip: 'common.previousPage'.tr(),
          onTap: () => onPageChanged(current - 1),
        ),
        ...buttons.map((p) {
          if (p == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '…',
                style: AppTypography.caption.copyWith(color: AppColors.textMuted),
              ),
            );
          }
          return _PageNumberButton(
            page: p,
            selected: p == current,
            onTap: () => onPageChanged(p),
          );
        }),
        _NavButton(
          icon: Icons.chevron_right,
          enabled: current < pages,
          tooltip: 'common.nextPage'.tr(),
          onTap: () => onPageChanged(current + 1),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: enabled ? AppColors.card : AppColors.hover,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                icon,
                size: 20,
                color: enabled ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final int page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: 'common.goToPage'.tr(namedArgs: {'page': '$page'}),
        child: Material(
          color: selected ? AppColors.primary : Colors.transparent,
          elevation: selected ? 0 : 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: selected
                ? BorderSide.none
                : BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: selected ? null : AppColors.primary.withValues(alpha: 0.08),
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    )
                  : null,
              child: Text(
                '$page',
                style: AppTypography.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? AppColors.onPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
