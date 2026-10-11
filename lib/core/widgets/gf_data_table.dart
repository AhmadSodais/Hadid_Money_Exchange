import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keyboard/gf_keyboard.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/gf_pagination.dart';
import 'gf_card.dart';
import 'gf_loader.dart';
import 'gf_pagination_bar.dart';
import 'gf_responsive.dart';

class GfTableColumn {
  const GfTableColumn({
    required this.label,
    this.flex = 1,
    this.width,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final String label;
  final int flex;
  final double? width;
  final AlignmentGeometry alignment;
}

class GfDataTable extends StatefulWidget {
  const GfDataTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.rowBuilder,
    this.title,
    this.subtitle,
    this.actions = const [],
    this.tabs,
    this.empty,
    this.isLoading = false,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.onPageChanged,
    this.onPageSizeChanged,
    this.autoPageSize = false,
    this.clientSide = false,
    this.itemLabel,
    this.minWidth,
    this.rowHeight = AppSpacing.tableRowHeight,
    this.showRowNumbers = true,
  });

  final List<GfTableColumn> columns;
  final int rowCount;
  final Widget Function(BuildContext context, int index) rowBuilder;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? tabs;
  final Widget? empty;
  final bool isLoading;
  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final bool autoPageSize;
  final bool clientSide;
  final String? itemLabel;
  final double? minWidth;
  final double rowHeight;
  /// When true, prepends a 1-based row index column on every page.
  final bool showRowNumbers;

  @override
  State<GfDataTable> createState() => _GfDataTableState();
}

class _GfDataTableState extends State<GfDataTable> {
  int _clientPage = 1;
  int? _lastReportedPageSize;
  int _layoutCapacity = 20;
  bool _hasMeasuredCapacity = false;

  @override
  void didUpdateWidget(covariant GfDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Filter/tab/search changes shrink or replace the dataset; keep page 1
    // so the table does not look "stuck" on an empty later page.
    if (widget.clientSide &&
        (oldWidget.total != widget.total ||
            oldWidget.rowCount != widget.rowCount)) {
      _clientPage = 1;
    }
  }

  bool get _serverPaginated =>
      !widget.clientSide && widget.onPageChanged != null && widget.total > 0;

  bool get _clientPaginated => widget.clientSide && widget.total > 0;

  bool get _showPagination => _serverPaginated || _clientPaginated;

  /// Client-side tables always size pages to the visible body so rows are never
  /// clipped and pagination can advance through the full filtered set.
  bool get _useAutoPageSize =>
      widget.autoPageSize ||
      (widget.clientSide && widget.onPageSizeChanged == null);

  int get _effectiveTotal => widget.total;

  int get _effectivePage => widget.clientSide ? _clientPage : widget.page;

  /// Page size used for paging math (footer + slice).
  int get _pageSize {
    if (_useAutoPageSize) {
      if (widget.onPageSizeChanged != null) {
        // Prefer live layout capacity so UI never waits on a stale VM value.
        return _hasMeasuredCapacity
            ? _layoutCapacity
            : widget.pageSize.clamp(1, GfPagination.maxRowsPerPage);
      }
      return _hasMeasuredCapacity
          ? _layoutCapacity
          : widget.pageSize.clamp(1, GfPagination.maxRowsPerPage);
    }
    return widget.pageSize.clamp(1, GfPagination.maxRowsPerPage);
  }

  void _reportCapacity(int capacity) {
    // Keep page-size math valid even when the viewport is too short for a row.
    final safe = capacity < 1 ? 1 : capacity;
    if (!_hasMeasuredCapacity || _layoutCapacity != safe) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _hasMeasuredCapacity = true;
            _layoutCapacity = safe;
          });
        }
      });
    }

    if (!_useAutoPageSize || widget.onPageSizeChanged == null) return;
    if (_lastReportedPageSize == safe && widget.pageSize == safe) {
      return;
    }
    if (widget.pageSize == safe) {
      _lastReportedPageSize = safe;
      return;
    }
    _lastReportedPageSize = safe;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPageSizeChanged!(safe);
    });
  }

  Widget _emptyBody() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: widget.empty ??
          Text(
            'common.noData'.tr(),
            style: AppTypography.subtitle,
            textAlign: TextAlign.center,
          ),
    );
  }

  Widget _withRowNumber(Widget row, int rowNumber) {
    if (!widget.showRowNumbers) return row;
    if (row is! GfTableRow) return row;
    return GfTableRow(
      onTap: row.onTap,
      height: row.height,
      selected: row.selected,
      children: [
        SizedBox(
          width: 52,
          child: Align(
            alignment: AlignmentDirectional.center,
            child: Text(
              '$rowNumber',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ...row.children,
      ],
    );
  }

  double _resolveMaxHeight(BoxConstraints constraints) {
    if (constraints.maxHeight.isFinite) return constraints.maxHeight;
    return MediaQuery.sizeOf(context).height * 0.55;
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.locale;
    final pageSize = _pageSize;
    final totalItems = _effectiveTotal;
    final pages = GfPagination.totalPages(totalItems: totalItems, pageSize: pageSize);
    final currentPage = GfPagination.clampPage(_effectivePage, pages);

    if (widget.clientSide && _clientPage != currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _clientPage = currentPage);
      });
    }

    int indexOffset;
    int dataRows;
    if (widget.clientSide) {
      indexOffset = (currentPage - 1) * pageSize;
      dataRows = totalItems == 0
          ? 0
          : (totalItems - indexOffset).clamp(0, pageSize);
    } else {
      // Server-paginated pages already sliced; number from global position.
      indexOffset = (currentPage - 1) * pageSize;
      dataRows = widget.rowCount;
    }

    final columns = widget.showRowNumbers
        ? <GfTableColumn>[
            GfTableColumn(
              label: 'common.rowNumber'.tr(),
              width: 52,
              alignment: AlignmentDirectional.center,
            ),
            ...widget.columns,
          ]
        : widget.columns;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = _resolveMaxHeight(constraints);
        final hasFiniteHeight = constraints.maxHeight.isFinite;
        final cardHeight = hasFiniteHeight ? constraints.maxHeight : maxH;
        final hasChrome = widget.title != null ||
            widget.actions.isNotEmpty ||
            widget.tabs != null;

        Widget? chrome;
        if (hasChrome) {
          chrome = Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, headerConstraints) {
                    final stackActions = headerConstraints.maxWidth < 960 ||
                        widget.actions.length >= 2;
                    final titleBlock = widget.title != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title!,
                                style: AppTypography.sectionTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle!,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          )
                        : null;
                    final actionsBar = widget.actions.isEmpty
                        ? null
                        : GfActionBar(
                            alignment: stackActions
                                ? WrapAlignment.start
                                : WrapAlignment.end,
                            children: widget.actions,
                          );

                    if (stackActions && actionsBar != null) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (titleBlock != null) titleBlock,
                          const SizedBox(height: 10),
                          actionsBar,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        if (titleBlock != null)
                          Expanded(child: titleBlock)
                        else
                          const Spacer(),
                        if (actionsBar != null) actionsBar,
                      ],
                    );
                  },
                ),
                if (widget.tabs != null) ...[
                  const SizedBox(height: 10),
                  widget.tabs!,
                ],
              ],
            ),
          );
        }

        Widget bodyChild;
        if (widget.isLoading) {
          bodyChild = const GfPageLoader(size: 44);
        } else if ((!widget.clientSide && widget.rowCount == 0) ||
            (widget.clientSide && totalItems == 0)) {
          bodyChild = _emptyBody();
        } else {
          bodyChild = LayoutBuilder(
            builder: (context, viewport) {
              final direction = Directionality.of(context);
              final tableWidth = math.max(
                viewport.maxWidth,
                widget.minWidth ?? 0,
              );
              final table = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    columns: columns,
                    textDirection: direction,
                    locale: locale,
                  ),
                  Divider(height: 1, color: AppColors.divider),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bodyConstraints) {
                        final capacity =
                            GfPagination.rowsPerPageFromHeight(
                          bodyHeight: bodyConstraints.maxHeight,
                          rowHeight: widget.rowHeight,
                        );
                        _reportCapacity(capacity);

                        final renderCount =
                            dataRows.clamp(0, capacity).toInt();
                        if (renderCount <= 0) {
                          return const SizedBox.shrink();
                        }

                        return GfArrowFocusGroup(
                          includeHorizontal: false,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            itemExtent: widget.rowHeight,
                            itemCount: renderCount,
                            itemBuilder: (context, i) {
                              final dataIndex = widget.clientSide
                                  ? indexOffset + i
                                  : i;
                              final rowNumber = indexOffset + i + 1;
                              final row = widget.rowBuilder(
                                context,
                                dataIndex,
                              );
                              return _withRowNumber(row, rowNumber);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );

              final sized = SizedBox(
                width: tableWidth,
                height: viewport.maxHeight,
                child: table,
              );
              if (tableWidth > viewport.maxWidth + 0.5) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: sized,
                );
              }
              return sized;
            },
          );
        }

        return GfCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: cardHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chrome != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(72, cardHeight * 0.42),
                    ),
                    child: SingleChildScrollView(
                      child: chrome,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: bodyChild),
                      if (_showPagination)
                        GfPaginationBar(
                          page: currentPage,
                          pageSize: pageSize,
                          totalItems: totalItems,
                          itemLabel: widget.itemLabel,
                          compact: constraints.maxWidth < 640,
                          onPageChanged: (p) {
                            if (widget.clientSide) {
                              setState(() => _clientPage = p);
                            } else {
                              widget.onPageChanged!(p);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.columns,
    required this.textDirection,
    required this.locale,
  });

  final List<GfTableColumn> columns;
  final TextDirection textDirection;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final useUppercase = locale.languageCode == 'en';
    return Directionality(
      textDirection: textDirection,
      child: Container(
        height: GfPagination.tableHeaderHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: AppColors.tableHeader,
        child: Row(
          textDirection: textDirection,
          children: [
            for (final column in columns)
              _cell(
                column,
                Text(
                  useUppercase ? column.label.toUpperCase() : column.label,
                  textAlign: _textAlign(column.alignment),
                  textDirection: textDirection,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.isLight
                        ? AppColors.lightPrimary900
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(GfTableColumn column, Widget child) {
    final aligned = Align(
      alignment: column.alignment,
      child: SizedBox(width: double.infinity, child: child),
    );
    if (column.width != null) {
      return SizedBox(width: column.width, child: aligned);
    }
    return Expanded(flex: column.flex, child: aligned);
  }

  TextAlign _textAlign(AlignmentGeometry alignment) {
    if (alignment is AlignmentDirectional) {
      if (alignment.start < -0.3) return TextAlign.start;
      if (alignment.start > 0.3) return TextAlign.end;
      return TextAlign.center;
    }
    if (alignment is Alignment) {
      if (alignment.x < -0.3) return TextAlign.start;
      if (alignment.x > 0.3) return TextAlign.end;
      return TextAlign.center;
    }
    return TextAlign.start;
  }
}

class GfTableRow extends StatefulWidget {
  const GfTableRow({
    super.key,
    required this.children,
    this.onTap,
    this.height = AppSpacing.tableRowHeight,
    this.selected = false,
  });

  final List<Widget> children;
  final VoidCallback? onTap;
  final double height;
  final bool selected;

  @override
  State<GfTableRow> createState() => _GfTableRowState();
}

class _MoveCellIntent extends Intent {
  const _MoveCellIntent(this.delta);
  final int delta;
}

class _GfTableRowState extends State<GfTableRow> {
  bool _hover = false;
  bool _focused = false;
  int _cellIndex = 0;

  void _activate() {
    widget.onTap?.call();
  }

  void _moveCell(int delta) {
    if (widget.children.isEmpty) return;
    setState(() {
      _cellIndex =
          (_cellIndex + delta).clamp(0, widget.children.length - 1).toInt();
    });
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.selected
        ? AppColors.surface
        : (AppColors.isLight ? AppColors.card : Colors.transparent);
    final showCellFocus = _focused && widget.children.length > 1;

    return FocusableActionDetector(
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) {
        if (mounted) setState(() => _focused = value);
      },
      onShowHoverHighlight: (value) {
        if (mounted) setState(() => _hover = value);
      },
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.enter):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.space):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const _MoveCellIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const _MoveCellIntent(1),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
        _MoveCellIntent: CallbackAction<_MoveCellIntent>(
          onInvoke: (intent) {
            _moveCell(intent.delta);
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _hover || _focused ? AppColors.rowHover : base,
              border: Border(
                bottom: BorderSide(color: AppColors.divider),
                left: widget.selected || _focused
                    ? BorderSide(
                        color: AppColors.primary,
                        width: _focused ? 3 : 3,
                      )
                    : BorderSide.none,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              textDirection: Directionality.of(context),
              children: [
                for (var i = 0; i < widget.children.length; i++)
                  _wrapCell(widget.children[i], i, showCellFocus),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapCell(Widget child, int index, bool showCellFocus) {
    final focusedCell = showCellFocus && index == _cellIndex;
    if (!focusedCell) return child;

    final highlight = BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.primary, width: 1.5),
      color: AppColors.primary.withValues(alpha: 0.06),
    );

    if (child is Expanded) {
      return Expanded(
        flex: child.flex,
        child: DecoratedBox(decoration: highlight, child: child.child),
      );
    }
    if (child is Flexible) {
      return Flexible(
        flex: child.flex,
        fit: child.fit,
        child: DecoratedBox(decoration: highlight, child: child.child),
      );
    }
    return DecoratedBox(decoration: highlight, child: child);
  }
}
