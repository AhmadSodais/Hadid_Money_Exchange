import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/ledger_queries.dart';
import '../../application/read_models.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/shared/business_date.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/transaction_actions.dart';
import '../widgets/transaction_detail_dialog.dart';

/// روزنامچه: every transaction of every type in one place. Filters combine
/// (AND); none overrides another. Edit and delete never change a posted row:
/// both go through [TransactionActions] (reversal on the original date, plus
/// the corrected version for an edit), so every balance stays consistent.
class JournalPage extends StatefulWidget {
  const JournalPage({super.key});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

enum _View {
  active('معاملات فعال'),
  removed('حذف یا ویرایش‌شده'),
  all('همه (با اسناد برگشت)');

  const _View(this.label);

  final String label;
}

enum _RowAction { details, edit, delete }

class _JournalPageState extends State<JournalPage> with RevisionReload {
  final _search = TextEditingController();
  DateFilterValue _dateFilter = DateFilterValue.thisMonth();
  _TypeFilter _typeFilter = _TypeFilter.all;
  _View _view = _View.active;
  Currency? _currency;
  int _page = 1;
  int _pageSize = 20;
  int _total = 0;
  bool _loading = true;
  List<PostedTransaction> _rows = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  JournalFilter get _filter => JournalFilter(
        from: BusinessDate.fromDateTime(_dateFilter.from),
        to: BusinessDate.fromDateTime(_dateFilter.to),
        types: _typeFilter.types,
        status: _view == _View.removed ? TransactionStatus.reversed : null,
        activeOnly: _view == _View.active,
        currency: _currency?.code,
        text: _search.text,
      );

  @override
  Future<void> reload() async {
    final q = session.services.queries;
    final filter = _filter;
    final total = await q.journalCount(filter);
    final pages = total == 0 ? 1 : (total - 1) ~/ _pageSize + 1;
    if (_page > pages) _page = pages;
    final rows = await q.journal(filter, limit: _pageSize, offset: (_page - 1) * _pageSize);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _total = total;
      _loading = false;
    });
  }

  void _refilter() {
    _page = 1;
    reload();
  }

  Future<void> _runRow(_RowAction action, PostedTransaction t) async {
    switch (action) {
      case _RowAction.details:
        await TransactionDetailDialog.show(context, t.id);
      case _RowAction.edit:
        await TransactionActions.edit(context, t);
      case _RowAction.delete:
        await TransactionActions.delete(context, t);
    }
  }

  Widget _rowMenu(PostedTransaction t, AppSession s) {
    final canEdit = TransactionActions.canEdit(t, s);
    final canDelete = TransactionActions.canDelete(t, s);
    return LedgerRowMenu(
      onSelected: (v) => _runRow(_RowAction.values.byName(v), t),
      items: [
        gfPopupMenuItem(value: _RowAction.details.name, label: 'جزئیات'),
        if (canEdit) gfPopupMenuItem(value: _RowAction.edit.name, label: 'ویرایش'),
        if (canDelete) gfPopupMenuItem(value: _RowAction.delete.name, label: 'حذف', danger: true),
      ],
    );
  }

  String _details(PostedTransaction t, AppSession s) {
    final src = s.currency(t.sourceCurrency);
    if (t.isExchange) {
      return '${MoneyFormat.withName(t.sourceAmountMinor ?? 0, src)} × ${MoneyFormat.rate(t.rate ?? '')} = '
          '${MoneyFormat.withName(t.destAmountMinor ?? 0, s.currency(t.destCurrency))}';
    }
    if (t.signedAmountMinor != null) {
      return MoneyFormat.withName(t.signedAmountMinor!, src);
    }
    if (t.sourceAmountMinor != null) return MoneyFormat.withName(t.sourceAmountMinor!, src);
    return t.description ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    return PageScaffold(
      title: 'روزنامچه معاملات',
      subtitle: 'همه معاملات؛ ویرایش و حذف از منوی هر ردیف — موجودی‌ها خودکار اصلاح و سابقه حفظ می‌شود',
      searchController: _search,
      searchHint: 'شماره سند، شرح یا نام مشتری',
      onSearch: (_) => _refilter(),
      actions: [
        GfDateFilter(
          value: _dateFilter,
          onChanged: (v) {
            setState(() => _dateFilter = v);
            _refilter();
          },
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GfCountBox(label: 'تعداد معاملات', count: _total, icon: AppAssets.invoiceFilled),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in _TypeFilter.values) ...[
                        if (f != _TypeFilter.values.first) const SizedBox(width: 8),
                        GfFilterChip(
                          label: f.label,
                          selected: _typeFilter == f,
                          onTap: () {
                            setState(() => _typeFilter = f);
                            _refilter();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: LedgerTable(
              title: 'معاملات ثبت‌شده',
              subtitle: 'برای جزئیات روی ردیف کلیک کنید؛ ویرایش و حذف از منوی ⋮ انتهای ردیف.',
              isLoading: _loading,
              minWidth: 1050,
              itemLabel: 'معامله',
              emptyText: 'معامله‌ای یافت نشد.',
              emptyHint: 'بازه تاریخ یا فیلترها را تغییر دهید.',
              actions: [
                GfDropdown<_View>(
                  width: 210,
                  prefixIcon: Icons.flag_outlined,
                  items: _View.values,
                  value: _view,
                  labelBuilder: (v) => v.label,
                  onChanged: (v) {
                    if (v == null) return;
                    _view = v;
                    _refilter();
                  },
                ),
                GfDropdown<Currency?>(
                  width: 150,
                  hint: 'همه ارزها',
                  prefixIcon: Icons.currency_exchange,
                  items: [null, ...s.activeCurrencies],
                  value: _currency,
                  labelBuilder: (c) => c == null ? 'همه ارزها' : c.nameFa,
                  onChanged: (c) {
                    _currency = c;
                    _refilter();
                  },
                ),
              ],
              columns: const [
                LedgerColumn.date(),
                LedgerColumn.reference(),
                LedgerColumn.text('نوع'),
                LedgerColumn.primary('مشتری'),
                LedgerColumn.description('جزئیات'),
                LedgerColumn.status(),
                LedgerColumn.actions(),
              ],
              rows: [
                for (final t in _rows)
                  [
                    Text(DateFormatFa.business(t.effectiveDate), style: AppTypography.body),
                    Text(t.referenceNo, style: AppTypography.caption, textDirection: TextDirection.ltr),
                    Text(t.type.labelFa, style: AppTypography.bodyMedium),
                    Text(t.customerName ?? '—', style: AppTypography.body),
                    Text(
                      _details(t, s),
                      style: AppTypography.body.copyWith(
                        color: t.isActive ? null : AppColors.textMuted,
                        decoration: t.status == TransactionStatus.reversed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      TransactionActions.statusLabel(t),
                      style: AppTypography.caption.copyWith(
                        color: TransactionActions.statusColor(t),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    _rowMenu(t, s),
                  ],
              ],
              total: _total,
              page: _page,
              pageSize: _pageSize,
              onPageChanged: (p) {
                _page = p;
                reload();
              },
              onPageSizeChanged: (size) {
                if (size == _pageSize) return;
                _pageSize = size;
                _page = 1;
                reload();
              },
              onTapRow: (i) => TransactionDetailDialog.show(context, _rows[i].id),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TypeFilter {
  all('همه', null),
  receipt('رسید', {TransactionType.receipt}),
  payment('برد', {TransactionType.payment}),
  buy('خرید', {TransactionType.buy}),
  sell('فروش', {TransactionType.sell}),
  expense('مصرف', {TransactionType.expense}),
  other('سایر', {
    TransactionType.openingCash,
    TransactionType.openingCustomer,
    TransactionType.cashAdjustment,
    TransactionType.customerAdjustment,
    TransactionType.reversal,
  });

  const _TypeFilter(this.label, this.types);

  final String label;
  final Set<TransactionType>? types;
}
