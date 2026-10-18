import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/ledger_queries.dart';
import '../../application/read_models.dart';
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
  active('معاملات فعال', 'معاملاتی که در موجودی‌ها حساب می‌شوند', Icons.check_circle_outline_rounded),
  removed('حذف یا ویرایش‌شده', 'معاملات حذف‌شده و نسخه قبلی معاملات ویرایش‌شده', Icons.history_rounded),
  all('همه (با اسناد برگشت)', 'همه معاملات همراه با اسناد برگشت', Icons.list_alt_rounded);

  const _View(this.label, this.hint, this.icon);

  final String label;
  final String hint;
  final IconData icon;
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

  /// Positive = money in / won; negative = money out / lost. Buy/sell use the
  /// traded (source) side. Rate and counter amount stay in the detail dialog.
  int? _signedDetailMinor(PostedTransaction t) {
    final source = t.sourceAmountMinor;
    return switch (t.type) {
      TransactionType.receipt ||
      TransactionType.openingCash ||
      TransactionType.buy =>
        source,
      TransactionType.payment ||
      TransactionType.expense ||
      TransactionType.sell =>
        source == null ? null : -source,
      TransactionType.openingCustomer ||
      TransactionType.customerAdjustment ||
      TransactionType.cashAdjustment =>
        t.signedAmountMinor ?? source,
      TransactionType.reversal => source == null ? null : -source.abs(),
    };
  }

  Widget _details(PostedTransaction t, AppSession s) {
    final signed = _signedDetailMinor(t);
    if (signed == null) {
      return Text(
        t.description ?? '—',
        style: AppTypography.body.copyWith(color: AppColors.textMuted),
      );
    }
    final src = s.currency(t.sourceCurrency);
    final sign = signed > 0 ? '+' : (signed < 0 ? '−' : '');
    final color = !t.isActive
        ? AppColors.textMuted
        : signed > 0
            ? AppColors.success
            : signed < 0
                ? AppColors.error
                : AppColors.textPrimary;
    return Text(
      '$sign${MoneyFormat.withName(signed.abs(), src, fallbackCode: t.sourceCurrency)}',
      textDirection: TextDirection.ltr,
      style: AppTypography.bodySemiBold.copyWith(
        color: color,
        decoration: t.status == TransactionStatus.reversed ? TextDecoration.lineThrough : null,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
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
        // GfMenuFilter<_TypeFilter>(
        //   value: _typeFilter,
        //   width: 170,
        //   options: [
        //     for (final f in _TypeFilter.values)
        //       GfMenuFilterOption(value: f, label: f.label, icon: f.icon, subtitle: f.hint),
        //   ],
        //   onChanged: (f) {
        //     setState(() => _typeFilter = f);
        //     _refilter();
        //   },
        // ),
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
          Expanded(
            child: LedgerTable(
              title: 'معاملات ثبت‌شده',
              titleCount: _total,
              subtitle: 'برای جزئیات روی ردیف کلیک کنید؛ ویرایش و حذف از منوی ⋮ انتهای ردیف.',
              isLoading: _loading,
              minWidth: 1050,
              itemLabel: 'معامله',
              emptyText: 'معامله‌ای یافت نشد.',
              emptyHint: 'بازه تاریخ یا فیلترها را تغییر دهید.',
              actions: [
                // Scroll when filters are wider than the title action slot.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GfMenuFilter<_TypeFilter>(
                        value: _typeFilter,
                        width: 170,
                        options: [
                          for (final f in _TypeFilter.values)
                            GfMenuFilterOption(
                              value: f,
                              label: f.label,
                              icon: f.icon,
                              subtitle: f.hint,
                            ),
                        ],
                        onChanged: (f) {
                          setState(() => _typeFilter = f);
                          _refilter();
                        },
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      GfMenuFilter<_View>(
                        value: _view,
                        width: 210,
                        options: [
                          for (final v in _View.values)
                            GfMenuFilterOption(
                              value: v,
                              label: v.label,
                              icon: v.icon,
                              subtitle: v.hint,
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _view = v);
                          _refilter();
                        },
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      GfMenuFilter<String?>(
                        value: _currency?.code,
                        width: 160,
                        options: [
                          const GfMenuFilterOption(
                            value: null,
                            label: 'همه ارزها',
                            icon: Icons.public_rounded,
                            subtitle: 'معاملات همه ارزها',
                          ),
                          for (final c in s.activeCurrencies)
                            GfMenuFilterOption(
                              value: c.code,
                              label: c.nameFa,
                              icon: Icons.payments_outlined,
                              subtitle: c.code,
                            ),
                        ],
                        onChanged: (code) {
                          setState(() => _currency = s.currency(code));
                          _refilter();
                        },
                      ),
                    ],
                  ),
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
                    TransactionTypeBadge(t.type),
                    Text(t.customerName ?? '—', style: AppTypography.body),
                    _details(t, s),
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
  all('همه معاملات', 'همه انواع معامله', Icons.list_alt_rounded, null),
  receipt('رسید', 'پول دریافت‌شده از مشتری', Icons.south_west_rounded, {TransactionType.receipt}),
  payment('برد', 'پول پرداخت‌شده به مشتری', Icons.north_east_rounded, {TransactionType.payment}),
  buy('خرید', 'خرید ارز از مشتری', Icons.shopping_cart_outlined, {TransactionType.buy}),
  sell('فروش', 'فروش ارز به مشتری', Icons.sell_outlined, {TransactionType.sell}),
  expense('مصرف', 'مصارف پرداخت‌شده از صندوق', Icons.receipt_long_outlined, {TransactionType.expense}),
  other('سایر', 'بیلانس افتتاحیه، اصلاحات و اسناد برگشت', Icons.more_horiz_rounded, {
    TransactionType.openingCash,
    TransactionType.openingCustomer,
    TransactionType.cashAdjustment,
    TransactionType.customerAdjustment,
    TransactionType.reversal,
  });

  const _TypeFilter(this.label, this.hint, this.icon, this.types);

  final String label;
  final String hint;
  final IconData icon;
  final Set<TransactionType>? types;
}
