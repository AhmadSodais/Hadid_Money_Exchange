import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/gf_pagination.dart';
import 'gf_empty_state.dart';
import 'gf_pagination_bar.dart';

/// Card panel with client-side pagination.
///
/// Rows-per-page comes from the measured list-body height after subtracting the
/// title and fixed pagination footer from the panel height.
class GfPaginatedListPanel extends StatefulWidget {
  const GfPaginatedListPanel({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.height,
    this.itemHeight = 56,
    this.itemLabel,
    this.empty,
  });

  final String title;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double? height;
  final double itemHeight;
  final String? itemLabel;
  final Widget? empty;

  @override
  State<GfPaginatedListPanel> createState() => _GfPaginatedListPanelState();
}

class _GfPaginatedListPanelState extends State<GfPaginatedListPanel> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final panelHeight = widget.height ??
        GfPagination.overviewListPanelHeight(MediaQuery.sizeOf(context).height);

    return SizedBox(
      height: panelHeight,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.card,
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.isLight ? AppShadows.card : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: AppTypography.sectionTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ClipRect(
                child: widget.itemCount == 0
                    ? (widget.empty ??
                        GfEmptyState(
                          title: 'common.noData'.tr(),
                          compact: true,
                        ))
                    : LayoutBuilder(
                      builder: (context, constraints) {
                        final showFooter = widget.itemCount > 0;
                        final footerH =
                            showFooter ? GfPagination.footerMinHeight : 0.0;
                        final bodyHeight =
                            (constraints.maxHeight - footerH).clamp(0.0, double.infinity);
                        final pageSize = GfPagination.rowsPerPageFromHeight(
                          bodyHeight: bodyHeight,
                          rowHeight: widget.itemHeight,
                        );
                        final pages = GfPagination.totalPages(
                          totalItems: widget.itemCount,
                          pageSize: pageSize,
                        );
                        final page = GfPagination.clampPage(_page, pages);
                        if (page != _page) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _page = page);
                          });
                        }

                        final start = (page - 1) * pageSize;
                        final end =
                            (start + pageSize).clamp(0, widget.itemCount);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (var i = start; i < end; i++)
                                        SizedBox(
                                          height: widget.itemHeight,
                                          child: ClipRect(
                                            child: widget.itemBuilder(
                                              context,
                                              i,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (showFooter)
                              GfPaginationBar(
                                page: page,
                                pageSize: pageSize,
                                totalItems: widget.itemCount,
                                itemLabel: widget.itemLabel,
                                onPageChanged: (p) =>
                                    setState(() => _page = p),
                              ),
                          ],
                        );
                      },
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
