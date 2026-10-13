import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/catalog_service.dart';
import '../../application/read_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/gf_pagination.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/errors/domain_errors.dart';
import '../../domain/money/currency.dart';
import '../../domain/shared/business_date.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import 'dialog_shared.dart';

export 'dialog_shared.dart';

// ---------------------------------------------------------------- actions

/// Runs a service call and reports the outcome. Success is reported only
/// after the service returned (i.e. after the database commit); every error
/// is shown — nothing is swallowed.
Future<T?> runAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) GfToast.success(context, success);
    return result;
  } on DomainError catch (e) {
    if (context.mounted) GfToast.error(context, e.message);
  } catch (e) {
    if (context.mounted) GfToast.error(context, 'خطای غیرمنتظره: $e');
  }
  return null;
}

/// Reloads page data whenever a committed change is broadcast.
mixin RevisionReload<T extends StatefulWidget> on State<T> {
  int _seenRevision = -1;

  AppSession get session => Provider.of<AppSession>(context, listen: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = Provider.of<AppSession>(context).revision;
    if (revision != _seenRevision) {
      _seenRevision = revision;
      reload();
    }
  }

  Future<void> reload();
}

// ------------------------------------------------------------------ table

/// Table column. Use the named constructors so the same kind of data gets the
/// same width and alignment on every page.
///
/// Columns are always ordered from the start (right) edge as:
///  1. row number (added by the table)
///  2. date / time — [LedgerColumn.date], [LedgerColumn.dateTime]
///  3. identifier — [LedgerColumn.reference], [LedgerColumn.code]
///  4. type / operation — [LedgerColumn.text]
///  5. main subject: customer, account, name, or the currency when the row
///     is about a currency — [LedgerColumn.primary]
///  6. secondary text (a qualifying currency, phone, file…), then free text —
///     [LedgerColumn.text], [LedgerColumn.description]
///  7. counts, then amounts in calculation order (opening → in → out →
///     closing, debit → credit → balance, buy → sell, expected → counted →
///     difference) — [LedgerColumn.number], [LedgerColumn.amount]
///  8. status — [LedgerColumn.status]
///  9. row actions — [LedgerColumn.actions]
class LedgerColumn {
  const LedgerColumn(this.label, {this.flex = 1, this.numeric = false, this.width});

  const LedgerColumn.date([this.label = 'تاریخ'])
      : flex = 1,
        numeric = false,
        width = GfColumnWidth.date;

  const LedgerColumn.dateTime([this.label = 'زمان'])
      : flex = 1,
        numeric = false,
        width = GfColumnWidth.dateTime;

  const LedgerColumn.reference([this.label = 'شماره سند'])
      : flex = 1,
        numeric = false,
        width = GfColumnWidth.reference;

  const LedgerColumn.code([this.label = 'کد'])
      : flex = 1,
        numeric = false,
        width = GfColumnWidth.code;

  const LedgerColumn.primary(this.label)
      : flex = GfColumnFlex.primary,
        numeric = false,
        width = null;

  const LedgerColumn.text(this.label)
      : flex = GfColumnFlex.text,
        numeric = false,
        width = null;

  const LedgerColumn.description(this.label)
      : flex = GfColumnFlex.description,
        numeric = false,
        width = null;

  /// Short integers: counts, decimal places, sizes.
  const LedgerColumn.number(this.label)
      : flex = GfColumnFlex.number,
        numeric = true,
        width = null;

  const LedgerColumn.amount(this.label)
      : flex = GfColumnFlex.amount,
        numeric = true,
        width = null;

  const LedgerColumn.status([this.label = 'وضعیت'])
      : flex = 1,
        numeric = false,
        width = GfColumnWidth.status;

  const LedgerColumn.actions({this.width = GfColumnWidth.menu})
      : label = '',
        flex = 1,
        numeric = false;

  final String label;
  final int flex;
  final bool numeric;
  final double? width;

  AlignmentDirectional get _alignment =>
      numeric ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart;

  GfTableColumn get tableColumn => GfTableColumn(
        label: label,
        flex: flex,
        width: width,
        alignment: _alignment,
      );

  Widget cell(Widget child) {
    final aligned = Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGfCellPadding),
      child: Align(
        alignment: _alignment,
        child: DefaultTextStyle.merge(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: child,
        ),
      ),
    );
    return width != null ? SizedBox(width: width, child: aligned) : Expanded(flex: flex, child: aligned);
  }
}

/// Row-actions popup used in the last table column.
class LedgerRowMenu extends StatelessWidget {
  const LedgerRowMenu({super.key, required this.items, required this.onSelected});

  final List<PopupMenuEntry<String>> items;
  final ValueChanged<String> onSelected;

  static const double width = GfColumnWidth.menu;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      color: AppColors.modal,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (_) => items,
    );
  }
}

/// Ledger data table built on [GfDataTable]: card chrome, row numbers,
/// header strip and pagination bar.
///
/// Without [onPageChanged] the rows are paginated client-side. With
/// [shrinkWrap] the table sizes to its rows (no pagination) for small
/// embedded lists; adding [fixedRows] keeps it at a constant height of that
/// many rows and paginates client-side instead. [totalRow] (shrink-wrapped
/// tables only) is appended after the data rows without a row number.
class LedgerTable extends StatelessWidget {
  const LedgerTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onTapRow,
    this.emptyText = 'موردی یافت نشد.',
    this.emptyHint,
    this.shrinkWrap = false,
    this.title,
    this.titleCount,
    this.subtitle,
    this.actions = const [],
    this.tabs,
    this.itemLabel = 'ردیف',
    this.minWidth,
    this.isLoading = false,
    this.page = 1,
    this.pageSize = 20,
    this.total,
    this.onPageChanged,
    this.onPageSizeChanged,
    this.showRowNumbers = true,
    this.fixedRows,
    this.totalRow,
  }) : assert(totalRow == null || shrinkWrap);

  final List<LedgerColumn> columns;
  final List<List<Widget>> rows;
  final List<Widget>? totalRow;
  final ValueChanged<int>? onTapRow;
  final String emptyText;
  final String? emptyHint;
  final bool shrinkWrap;
  final String? title;

  /// Shown as a badge right after [title].
  final int? titleCount;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? tabs;
  final String itemLabel;
  final double? minWidth;
  final bool isLoading;
  final int page;
  final int pageSize;
  final int? total;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final bool showRowNumbers;
  final int? fixedRows;

  List<Widget> _cells(List<Widget> cells) => [
        for (var c = 0; c < columns.length; c++)
          columns[c].cell(c < cells.length ? cells[c] : const SizedBox.shrink()),
      ];

  Widget _row(BuildContext context, int i) {
    return GfTableRow(
      onTap: onTapRow == null ? null : () => onTapRow!(i),
      children: _cells(rows[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = GfEmptyState(title: emptyText, subtitle: emptyHint, compact: true);
    if (shrinkWrap) {
      return _CompactLedgerTable(
        columns: columns,
        rowCount: rows.length,
        rowBuilder: _row,
        totalCells: totalRow == null ? null : _cells(totalRow!),
        empty: empty,
        title: title,
        titleCount: titleCount,
        subtitle: subtitle,
        actions: actions,
        minWidth: minWidth,
        showRowNumbers: showRowNumbers,
        fixedRows: fixedRows,
        itemLabel: itemLabel,
      );
    }
    final server = onPageChanged != null;
    return GfDataTable(
      title: title,
      titleCount: titleCount,
      subtitle: subtitle,
      actions: actions,
      tabs: tabs,
      isLoading: isLoading,
      minWidth: minWidth == null ? null : gfTableMinWidth(context, preferred: minWidth!),
      columns: [for (final c in columns) c.tableColumn],
      rowCount: rows.length,
      total: total ?? rows.length,
      page: page,
      pageSize: pageSize,
      clientSide: !server,
      autoPageSize: true,
      onPageChanged: onPageChanged,
      onPageSizeChanged: onPageSizeChanged,
      itemLabel: itemLabel,
      showRowNumbers: showRowNumbers,
      empty: empty,
      rowBuilder: _row,
    );
  }
}

/// Table with the same header/row styling as [GfDataTable] that sizes to its
/// content. With [fixedRows] the body always reserves that many rows and the
/// rows are paginated, so the card height does not depend on the data.
class _CompactLedgerTable extends StatefulWidget {
  const _CompactLedgerTable({
    required this.columns,
    required this.rowCount,
    required this.rowBuilder,
    required this.empty,
    required this.showRowNumbers,
    required this.itemLabel,
    this.totalCells,
    this.title,
    this.titleCount,
    this.subtitle,
    this.actions = const [],
    this.minWidth,
    this.fixedRows,
  });

  final List<LedgerColumn> columns;
  final int rowCount;
  final Widget Function(BuildContext, int) rowBuilder;
  final List<Widget>? totalCells;
  final Widget empty;
  final bool showRowNumbers;
  final String itemLabel;
  final String? title;
  final int? titleCount;
  final String? subtitle;
  final List<Widget> actions;
  final double? minWidth;
  final int? fixedRows;

  @override
  State<_CompactLedgerTable> createState() => _CompactLedgerTableState();
}

class _CompactLedgerTableState extends State<_CompactLedgerTable> {
  static const double _numberWidth = GfColumnWidth.rowNumber;

  int _page = 1;

  Widget _total(List<Widget> cells) {
    return GfTableRow(
      children: [
        if (widget.showRowNumbers) const SizedBox(width: _numberWidth),
        ...cells,
      ],
    );
  }

  Widget _numbered(BuildContext context, int i) {
    final row = widget.rowBuilder(context, i) as GfTableRow;
    if (!widget.showRowNumbers) return row;
    return GfTableRow(
      onTap: row.onTap,
      children: [
        SizedBox(
          width: _numberWidth,
          child: Center(
            child: Text(
              '${i + 1}',
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

  @override
  Widget build(BuildContext context) {
    final headerStyle = AppTypography.caption.copyWith(
      color: AppColors.isLight ? AppColors.lightPrimary900 : AppColors.textSecondary,
      fontWeight: FontWeight.w500,
      fontSize: 13,
    );
    Widget headerCell(LedgerColumn c) {
      final text = Text(
        c.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: c.numeric ? TextAlign.end : TextAlign.start,
        style: headerStyle,
      );
      final padded = Padding(
        padding: const EdgeInsets.symmetric(horizontal: kGfCellPadding),
        child: SizedBox(width: double.infinity, child: text),
      );
      return c.width != null ? SizedBox(width: c.width, child: padded) : Expanded(flex: c.flex, child: padded);
    }

    final fixedRows = widget.fixedRows;
    final rowCount = widget.rowCount;
    final pages = fixedRows == null ? 1 : GfPagination.totalPages(totalItems: rowCount, pageSize: fixedRows);
    final page = GfPagination.clampPage(_page, pages);
    final first = fixedRows == null ? 0 : (page - 1) * fixedRows;
    final last = fixedRows == null ? rowCount : (first + fixedRows).clamp(0, rowCount);

    final totalCells = widget.totalCells;
    Widget body;
    if (fixedRows == null) {
      body = rowCount == 0
          ? Padding(padding: const EdgeInsets.all(24), child: widget.empty)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rowCount; i++) _numbered(context, i),
                if (totalCells != null) _total(totalCells),
              ],
            );
    } else {
      // The empty state also takes the pagination footer's slot.
      final rowsHeight = fixedRows * AppSpacing.tableRowHeight;
      body = SizedBox(
        height: rowCount == 0 ? rowsHeight + GfPagination.footerMinHeight : rowsHeight,
        child: rowCount == 0
            ? Center(child: widget.empty)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (var i = first; i < last; i++) _numbered(context, i)],
              ),
      );
    }

    final table = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: GfPagination.tableHeaderHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: AppColors.tableHeader,
          child: Row(
            children: [
              if (widget.showRowNumbers)
                SizedBox(
                  width: _numberWidth,
                  child: Text('common.rowNumber'.tr(), textAlign: TextAlign.center, style: headerStyle),
                ),
              for (final c in widget.columns) headerCell(c),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.divider),
        body,
      ],
    );

    final title = widget.title;
    final subtitle = widget.subtitle;
    final actions = widget.actions;
    final minWidth = widget.minWidth;
    final hasChrome = title != null || actions.isNotEmpty;
    return GfCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasChrome)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: AppTypography.sectionTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.titleCount != null) ...[
                                const SizedBox(width: 10),
                                GfCountBadge(count: widget.titleCount!),
                              ],
                            ],
                          ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                            maxLines: fixedRows == null ? null : 1,
                            overflow: fixedRows == null ? null : TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) GfActionBar(alignment: WrapAlignment.end, children: actions),
                ],
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(fixedRows != null && rowCount > 0 ? 0 : 8)),
            child: minWidth == null
                ? table
                : LayoutBuilder(
                    builder: (context, c) {
                      if (c.maxWidth >= minWidth) return table;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(width: minWidth, child: table),
                      );
                    },
                  ),
          ),
          if (fixedRows != null && rowCount > 0)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              child: GfPaginationBar(
                page: page,
                pageSize: fixedRows,
                totalItems: rowCount,
                itemLabel: widget.itemLabel,
                onPageChanged: (p) => setState(() => _page = p),
              ),
            ),
        ],
      ),
    );
  }
}

/// Monospace-like amount cell; negative values are shown in the error color
/// when [signColor] is set.
class AmountText extends StatelessWidget {
  const AmountText(this.minor, this.currency,
      {super.key, this.signColor = false, this.bold = false, this.showName = false});

  final int minor;
  final Currency? currency;
  final bool signColor;
  final bool bold;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final color = !signColor || minor == 0
        ? AppColors.textPrimary
        : (minor > 0 ? AppColors.success : AppColors.error);
    return Text(
      showName ? MoneyFormat.withName(minor, currency) : MoneyFormat.amount(minor, currency),
      textDirection: TextDirection.ltr,
      style: (bold ? AppTypography.bodySemiBold : AppTypography.body).copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// One fixed hue per transaction type, the same on every page and in both
/// themes, so a type is recognised by colour before its label is read.
Color transactionTypeColor(TransactionType type) => switch (type) {
      TransactionType.receipt => const Color(0xFF2E9E5B),
      TransactionType.payment => const Color(0xFFD64545),
      TransactionType.buy => const Color(0xFF2F7FE0),
      TransactionType.sell => const Color(0xFFE07B1F),
      TransactionType.openingCustomer || TransactionType.openingCash => const Color(0xFF159A9C),
      TransactionType.customerAdjustment || TransactionType.cashAdjustment => const Color(0xFF8559D6),
      TransactionType.expense => const Color(0xFFB8860B),
      TransactionType.reversal => const Color(0xFF7F8A8C),
    };

/// Coloured pill with the transaction type; reversed transactions get an
/// undo mark after it.
class TransactionTypeBadge extends StatelessWidget {
  const TransactionTypeBadge(this.type, {super.key, this.reversed = false});

  final TransactionType type;
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final color = transactionTypeColor(type);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.pill,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    type.labelFa,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      decoration: reversed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (reversed) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: 'برگشت‌شده',
            child: Icon(Icons.undo_rounded, size: 16, color: AppColors.warning),
          ),
        ],
      ],
    );
  }
}

enum BannerTone { info, warning, error, success }

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.tone = BannerTone.info});

  final String text;
  final BannerTone tone;

  @override
  Widget build(BuildContext context) {
    return DialogInfoBanner(
      message: text,
      tone: switch (tone) {
        BannerTone.info => DialogBannerTone.info,
        BannerTone.warning => DialogBannerTone.warning,
        BannerTone.error => DialogBannerTone.error,
        BannerTone.success => DialogBannerTone.success,
      },
    );
  }
}

// ----------------------------------------------------------------- fields

class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.enabled = true,
    this.allowNegative = false,
    this.errorText,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool allowNegative;
  final String? errorText;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return GfTextField(
      label: label,
      controller: controller,
      enabled: enabled,
      hint: hint ?? '0',
      errorText: errorText,
      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: allowNegative),
      inputFormatters: [
        if (!allowNegative) FilteringTextInputFormatter.deny(RegExp('-')),
        const ThousandsSeparatorInputFormatter(),
      ],
      textAlign: TextAlign.end,
      onChanged: onChanged,
    );
  }
}

class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'ارز',
    this.currencies,
    this.enabled = true,
  });

  final Currency? value;
  final ValueChanged<Currency> onChanged;
  final String label;
  final List<Currency>? currencies;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final items = currencies ?? context.watch<AppSession>().activeCurrencies;
    return GfDropdown<Currency>(
      label: label,
      items: items,
      value: value,
      enabled: enabled,
      labelBuilder: (c) => '${c.nameFa} (${c.code})',
      onChanged: (c) {
        if (c != null) onChanged(c);
      },
    );
  }
}

class DrawerPicker extends StatelessWidget {
  const DrawerPicker({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final drawers = context.watch<AppSession>().activeDrawers;
    CashDrawer? selected;
    for (final d in drawers) {
      if (d.id == value) selected = d;
    }
    return GfDropdown<CashDrawer>(
      label: 'صندوق',
      items: drawers,
      value: selected,
      labelBuilder: (d) => d.nameFa,
      onChanged: (d) {
        if (d != null) onChanged(d.id);
      },
    );
  }
}

class BusinessDateField extends StatelessWidget {
  const BusinessDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'تاریخ',
  });

  final BusinessDate value;
  final ValueChanged<BusinessDate> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GfShamsiDateField(
      label: label,
      value: value.toDateTime(),
      clearable: false,
      onChanged: (d) {
        if (d != null) onChanged(BusinessDate.fromDateTime(d));
      },
    );
  }
}

/// Shows the selected customer and opens a search dialog to change it.
class CustomerPickerField extends StatelessWidget {
  const CustomerPickerField({
    super.key,
    required this.selected,
    required this.onSelected,
    this.allowWalkIn = false,
    this.label = 'مشتری',
  });

  final CustomerRecord? selected;
  final ValueChanged<CustomerRecord> onSelected;
  final bool allowWalkIn;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: AppRadius.input,
          onTap: () async {
            final picked = await CustomerSearchDialog.show(context, allowWalkIn: allowWalkIn);
            if (picked != null) onSelected(picked);
          },
          child: Container(
            height: AppSpacing.controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: AppRadius.input,
              border: Border.all(color: AppColors.inputBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.person_search_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    selected == null ? 'انتخاب مشتری…' : '${selected!.name}  ·  ${selected!.code}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: selected == null ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CustomerSearchDialog extends StatefulWidget {
  const CustomerSearchDialog({super.key, required this.allowWalkIn});

  final bool allowWalkIn;

  static Future<CustomerRecord?> show(BuildContext context, {bool allowWalkIn = false}) {
    return showDialog<CustomerRecord>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: CustomerSearchDialog(allowWalkIn: allowWalkIn),
      ),
    );
  }

  @override
  State<CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<CustomerSearchDialog> {
  final _query = TextEditingController();
  List<CustomerRecord> _results = const [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final session = context.read<AppSession>();
    final list = await session.services.customers
        .search(q, includeWalkIn: widget.allowWalkIn, limit: 100);
    if (mounted) setState(() => _results = list);
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.person_search_outlined,
      iconColor: AppColors.primary,
      title: 'جستجوی مشتری',
      subtitle: 'برای انتخاب، روی مشتری کلیک کنید.',
      cancelLabel: 'بستن',
      onCancel: () => Navigator.of(context).pop(),
      maxWidth: 480,
      maxHeight: 600,
      fixedHeight: true,
      scrollBody: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfTextField(
            controller: _query,
            autofocus: true,
            hint: 'نام، شماره تماس، کد یا شماره مشتری',
            prefixIcon: Icons.search,
            onChanged: _search,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: GfEmptyState(
                      title: 'مشتری یافت نشد.',
                      subtitle: 'عبارت جستجو را تغییر دهید.',
                      compact: true,
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (_, i) {
                      final c = _results[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          c.isWalkIn ? Icons.directions_walk : Icons.person_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        title: Text('${i + 1}. ${c.name}', style: AppTypography.bodyMedium),
                        subtitle: Text(
                          [c.code, if (c.phone != null) c.phone!].join('  ·  '),
                          style: AppTypography.caption,
                        ),
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a mandatory reason (reversal, adjustment, reopen…).
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأیید',
  bool danger = true,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final text = controller.text.trim();
          if (text.isEmpty) return;
          Navigator.of(ctx).pop(text);
        }

        return GfDialogShell(
          icon: danger ? Icons.warning_amber_rounded : Icons.edit_note_outlined,
          iconColor: danger ? AppColors.error : AppColors.primary,
          title: title,
          subtitle: 'ثبت دلیل برای سوابق ممیزی الزامی است.',
          cancelLabel: 'انصراف',
          onCancel: () => Navigator.of(ctx).pop(),
          primaryLabel: confirmLabel,
          primaryIcon: danger ? Icons.undo_rounded : Icons.check_rounded,
          dangerPrimary: danger,
          onPrimary: submit,
          maxWidth: 420,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogInfoBanner(
                message: message,
                tone: danger ? DialogBannerTone.warning : DialogBannerTone.info,
              ),
              const SizedBox(height: 14),
              GfTextField(
                controller: controller,
                label: 'دلیل',
                required: true,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
              ),
            ],
          ),
        );
      },
    ),
  );
}
