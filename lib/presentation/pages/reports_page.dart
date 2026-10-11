import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/read_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_calendar.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/shared/business_date.dart';
import '../../infrastructure/export/excel_export.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/export_action.dart';
import '../widgets/transaction_detail_dialog.dart';

/// Every report reads posted journal lines only. Amounts of different
/// currencies are never added together, and no profit is computed without
/// an approved cost-basis policy.
class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  static const _tabs = [
    'موقعیت ارزی',
    'گزارش روزانه',
    'حسابات مشتریان',
    'فعالیت تبادله',
    'بیلانس آزمایشی',
    'عواید و مصارف',
    'دفتر کل',
    'سابقه بیلانس صندوق',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: PageScaffold(
        title: 'گزارش‌ها',
        subtitle: 'مبالغ هر ارز جداگانه گزارش می‌شود و هرگز با ارز دیگر جمع نمی‌شود.',
        headerExtra: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in _tabs) Tab(text: t)],
        ),
        body: const TabBarView(
          children: [
            _PositionReport(),
            _DailyReport(),
            _CustomerBalancesReport(),
            _ExchangeActivityReport(),
            _TrialBalanceReport(),
            _IncomeExpenseReport(),
            _GeneralLedgerReport(),
            _ReconciliationHistoryReport(),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- shared

/// "As of" date button for balance-type reports (inclusive end date).
class _AsOfButton extends StatelessWidget {
  const _AsOfButton({required this.value, required this.onChanged});

  final BusinessDate value;
  final ValueChanged<BusinessDate> onChanged;

  @override
  Widget build(BuildContext context) {
    return GfSecondaryButton(
      label: 'تا تاریخ ${DateFormatFa.business(value)}',
      icon: Icons.event_outlined,
      onPressed: () async {
        final picked = await AppCalendar.pickDate(context, initial: value.toDateTime(), title: 'تا تاریخ (شامل)');
        if (picked != null) onChanged(BusinessDate.fromDateTime(picked));
      },
    );
  }
}

String _cur(AppSession s, String code) => s.currency(code)?.nameFa ?? code;

/// Base state for report tabs: period / as-of date + reload on every
/// committed change.
abstract class _ReportState<T extends StatefulWidget> extends State<T> with RevisionReload {
  DateFilterValue period = DateFilterValue.today();
  BusinessDate asOf = BusinessDate.today();
  bool loading = true;

  BusinessDate get from => BusinessDate.fromDateTime(period.from);
  BusinessDate get to => BusinessDate.fromDateTime(period.to);

  Widget periodFilter() => GfDateFilter(
    value: period,
    onChanged: (v) {
      setState(() => period = v);
      reload();
    },
  );

  Widget asOfFilter() => _AsOfButton(
    value: asOf,
    onChanged: (d) {
      setState(() => asOf = d);
      reload();
    },
  );
}

// ------------------------------------------------------- currency position

class _PositionReport extends StatefulWidget {
  const _PositionReport();

  @override
  State<_PositionReport> createState() => _PositionReportState();
}

class _PositionReportState extends _ReportState<_PositionReport> {
  Map<String, int> _cash = const {};
  Map<String, ({int liabilities, int receivables})> _customers = const {};
  Map<String, int> _position = const {};

  @override
  Future<void> reload() async {
    final q = session.services.queries;
    final cash = await q.cashBalances(asOf: asOf);
    final customers = await q.customerTotals(asOf: asOf);
    final position = await q.exchangePosition(asOf: asOf);
    if (!mounted) return;
    setState(() {
      _cash = cash;
      _customers = customers;
      _position = position;
      loading = false;
    });
  }

  List<String> _codes(AppSession s) {
    final codes = {
      ..._cash.keys,
      ..._customers.keys,
      ..._position.keys,
      ...s.activeCurrencies.map((c) => c.code),
    }.toList()..sort((a, b) => (s.currency(a)?.sortOrder ?? 99).compareTo(s.currency(b)?.sortOrder ?? 99));
    return codes;
  }

  void _export(AppSession s) {
    exportSheets(context, 'currency_position_${asOf.iso}', [
      ExportSheet(
        name: 'موقعیت ارزی',
        notes: ['موقعیت ارزی تا تاریخ ${DateFormatFa.business(asOf)}'],
        headers: const [
          'ارز',
          'نقد صندوق',
          'طلب مشتریان',
          'بدهی مشتریان',
          'خالص پس از حسابات مشتریان',
          'حساب موقعیت ارزی',
        ],
        rows: [
          for (final code in _codes(s))
            [
              _cur(s, code),
              MoneyFormat.amount(_cash[code] ?? 0, s.currency(code)),
              MoneyFormat.amount(_customers[code]?.liabilities ?? 0, s.currency(code)),
              MoneyFormat.amount(_customers[code]?.receivables ?? 0, s.currency(code)),
              MoneyFormat.amount(
                (_cash[code] ?? 0) - (_customers[code]?.liabilities ?? 0) + (_customers[code]?.receivables ?? 0),
                s.currency(code),
              ),
              MoneyFormat.amount(_position[code] ?? 0, s.currency(code)),
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const InfoBanner(
          'خالص = نقد صندوق − طلب مشتریان + بدهی مشتریان (به همان ارز). '
          'حساب موقعیت ارزی مجموع ارز خریداری‌شده و فروخته‌شده را نشان می‌دهد و سود نیست.',
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LedgerTable(
            title: 'موقعیت ارزی',
            subtitle: 'تا پایان ${DateFormatFa.business(asOf)}',
            isLoading: loading,
            minWidth: 900,
            itemLabel: 'ارز',
            actions: [
              asOfFilter(),
              ExportButton(onPressed: () => _export(s)),
            ],
            columns: const [
              LedgerColumn('ارز', flex: 2),
              LedgerColumn('نقد صندوق', flex: 2, numeric: true),
              LedgerColumn('طلب مشتریان', flex: 2, numeric: true),
              LedgerColumn('بدهی مشتریان', flex: 2, numeric: true),
              LedgerColumn('خالص', flex: 2, numeric: true),
              LedgerColumn('موقعیت ارزی', flex: 2, numeric: true),
            ],
            rows: [
              for (final code in _codes(s))
                [
                  Text(_cur(s, code), style: AppTypography.bodyMedium),
                  AmountText(_cash[code] ?? 0, s.currency(code)),
                  AmountText(_customers[code]?.liabilities ?? 0, s.currency(code)),
                  AmountText(_customers[code]?.receivables ?? 0, s.currency(code)),
                  AmountText(
                    (_cash[code] ?? 0) - (_customers[code]?.liabilities ?? 0) + (_customers[code]?.receivables ?? 0),
                    s.currency(code),
                    signColor: true,
                    bold: true,
                  ),
                  AmountText(_position[code] ?? 0, s.currency(code)),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- daily

class _DailyReport extends StatefulWidget {
  const _DailyReport();

  @override
  State<_DailyReport> createState() => _DailyReportState();
}

class _DailyReportState extends _ReportState<_DailyReport> {
  List<CashMovement> _cash = const [];
  List<DailyTypeSummary> _types = const [];

  @override
  Future<void> reload() async {
    final q = session.services.queries;
    final cash = await q.cashMovement(from, to);
    final types = await q.typeSummary(from, to);
    if (!mounted) return;
    setState(() {
      _cash = cash;
      _types = types;
      loading = false;
    });
  }

  void _export(AppSession s) {
    exportSheets(context, 'daily_${from.iso}_${to.iso}', [
      ExportSheet(
        name: 'گردش صندوق',
        notes: ['گردش صندوق از ${DateFormatFa.business(from)} تا ${DateFormatFa.business(to)}'],
        headers: const ['ارز', 'مانده اول دوره', 'ورودی', 'خروجی', 'مانده پایان دوره'],
        rows: [
          for (final m in _cash)
            [
              _cur(s, m.currency),
              MoneyFormat.amount(m.openingMinor, s.currency(m.currency)),
              MoneyFormat.amount(m.inflowMinor, s.currency(m.currency)),
              MoneyFormat.amount(m.outflowMinor, s.currency(m.currency)),
              MoneyFormat.amount(m.closingMinor, s.currency(m.currency)),
            ],
        ],
      ),
      ExportSheet(
        name: 'معاملات به تفکیک نوع',
        headers: const ['نوع', 'ارز', 'تعداد', 'مجموع'],
        rows: [
          for (final t in _types)
            [
              t.type.labelFa,
              _cur(s, t.currency),
              '${t.count}',
              MoneyFormat.amount(t.totalMinor, s.currency(t.currency)),
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
      children: [
        if (loading)
          const SizedBox(height: 120, child: GfPageLoader())
        else
          LedgerTable(
            shrinkWrap: true,
            title: 'گردش نقد صندوق‌ها',
            subtitle: period.exportPeriodLabel,
            actions: [
              periodFilter(),
              ExportButton(onPressed: () => _export(s)),
            ],
            emptyText: 'گردشی ثبت نشده است.',
            columns: const [
              LedgerColumn('ارز', flex: 2),
              LedgerColumn('مانده اول دوره', flex: 2, numeric: true),
              LedgerColumn('ورودی', flex: 2, numeric: true),
              LedgerColumn('خروجی', flex: 2, numeric: true),
              LedgerColumn('مانده پایان دوره', flex: 2, numeric: true),
            ],
            rows: [
              for (final m in _cash)
                [
                  Text(_cur(s, m.currency)),
                  AmountText(m.openingMinor, s.currency(m.currency)),
                  AmountText(m.inflowMinor, s.currency(m.currency)),
                  AmountText(m.outflowMinor, s.currency(m.currency)),
                  AmountText(m.closingMinor, s.currency(m.currency), bold: true),
                ],
            ],
          ),
        const SizedBox(height: AppSpacing.md),
        LedgerTable(
          shrinkWrap: true,
          title: 'معاملات به تفکیک نوع',
          emptyText: 'در این دوره معامله‌ای ثبت نشده است.',
          columns: const [
            LedgerColumn('نوع', flex: 2),
            LedgerColumn('ارز'),
            LedgerColumn('تعداد'),
            LedgerColumn('مجموع', flex: 2, numeric: true),
          ],
          rows: [
            for (final t in _types)
              [
                Text(t.type.labelFa),
                Text(_cur(s, t.currency)),
                Text('${t.count}'),
                AmountText(t.totalMinor, s.currency(t.currency)),
              ],
          ],
        ),
      ],
    );
  }
}

// --------------------------------------------------------- customer totals

class _CustomerBalancesReport extends StatefulWidget {
  const _CustomerBalancesReport();

  @override
  State<_CustomerBalancesReport> createState() => _CustomerBalancesReportState();
}

class _CustomerBalancesReportState extends _ReportState<_CustomerBalancesReport> {
  Map<int, Map<String, int>> _positions = const {};
  Map<int, CustomerRecord> _customers = const {};

  @override
  Future<void> reload() async {
    final s = session.services;
    final positions = await s.queries.allCustomerPositions(asOf: asOf);
    final list = await s.customers.search('', includeInactive: true, includeWalkIn: true, limit: 1000000);
    if (!mounted) return;
    setState(() {
      _positions = positions;
      _customers = {for (final c in list) c.id: c};
      loading = false;
    });
  }

  List<String> _codes(AppSession s) {
    final codes = <String>{for (final m in _positions.values) ...m.keys}.toList()
      ..sort((a, b) => (s.currency(a)?.sortOrder ?? 99).compareTo(s.currency(b)?.sortOrder ?? 99));
    return codes;
  }

  void _export(AppSession s) {
    final codes = _codes(s);
    exportSheets(context, 'customer_balances_${asOf.iso}', [
      ExportSheet(
        name: 'حسابات مشتریان',
        notes: ['حسابات مشتریان تا ${DateFormatFa.business(asOf)} — مثبت = طلب مشتری، منفی = بدهی مشتری'],
        headers: ['کد', 'نام', for (final c in codes) _cur(s, c)],
        rows: [
          for (final e in _positions.entries)
            [
              _customers[e.key]?.code ?? '${e.key}',
              _customers[e.key]?.name ?? '${e.key}',
              for (final c in codes) e.value[c] == null ? '' : MoneyFormat.amount(e.value[c]!, s.currency(c)),
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final codes = _codes(s);
    final ids = _positions.keys.toList()
      ..sort((a, b) => (_customers[a]?.name ?? '').compareTo(_customers[b]?.name ?? ''));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LedgerTable(
            title: 'حسابات مشتریان',
            subtitle: 'مثبت = طلب مشتری، منفی = بدهی مشتری — تا پایان ${DateFormatFa.business(asOf)}',
            isLoading: loading,
            minWidth: 300.0 + codes.length * 160,
            itemLabel: 'مشتری',
            actions: [
              asOfFilter(),
              ExportButton(onPressed: () => _export(s)),
            ],
            emptyText: 'همه حسابات مشتریان تسویه است.',
            columns: [
              const LedgerColumn('مشتری', flex: 3),
              for (final c in codes) LedgerColumn(_cur(s, c), flex: 2, numeric: true),
            ],
            rows: [
              for (final id in ids)
                [
                  Text(_customers[id]?.name ?? '$id'),
                  for (final c in codes)
                    _positions[id]![c] == null
                        ? const Text('')
                        : AmountText(_positions[id]![c]!, s.currency(c), signColor: true),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------- exchange activity

class _ExchangeActivityReport extends StatefulWidget {
  const _ExchangeActivityReport();

  @override
  State<_ExchangeActivityReport> createState() => _ExchangeActivityReportState();
}

class _ExchangeActivityReportState extends _ReportState<_ExchangeActivityReport> {
  List<ExchangeActivityRow> _rows = const [];

  @override
  Future<void> reload() async {
    final rows = await session.services.queries.exchangeActivity(from, to);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      loading = false;
    });
  }

  void _export(AppSession s) {
    exportSheets(context, 'exchange_activity_${from.iso}_${to.iso}', [
      ExportSheet(
        name: 'فعالیت تبادله',
        notes: [
          'فعالیت خرید و فروش (فقط معاملات برگشت‌نشده) از ${DateFormatFa.business(from)} تا ${DateFormatFa.business(to)}',
        ],
        headers: const ['نوع', 'ارز', 'ارز مقابل', 'تعداد', 'مجموع ارز', 'مجموع مقابل', 'کمترین نرخ', 'بیشترین نرخ'],
        rows: [
          for (final r in _rows)
            [
              r.type.labelFa,
              _cur(s, r.baseCurrency),
              _cur(s, r.quoteCurrency),
              '${r.count}',
              MoneyFormat.amount(r.baseTotalMinor, s.currency(r.baseCurrency)),
              MoneyFormat.amount(r.quoteTotalMinor, s.currency(r.quoteCurrency)),
              r.minRate,
              r.maxRate,
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LedgerTable(
            title: 'فعالیت تبادله',
            subtitle: 'فقط معاملات برگشت‌نشده — ${period.exportPeriodLabel}',
            isLoading: loading,
            minWidth: 1000,
            itemLabel: 'ردیف',
            actions: [
              periodFilter(),
              ExportButton(onPressed: () => _export(s)),
            ],
            emptyText: 'در این دوره خرید یا فروشی ثبت نشده است.',
            columns: const [
              LedgerColumn('نوع'),
              LedgerColumn('ارز'),
              LedgerColumn('ارز مقابل'),
              LedgerColumn('تعداد'),
              LedgerColumn('مجموع ارز', flex: 2, numeric: true),
              LedgerColumn('مجموع مقابل', flex: 2, numeric: true),
              LedgerColumn('نرخ (کمترین – بیشترین)', flex: 2),
            ],
            rows: [
              for (final r in _rows)
                [
                  Text(r.type.labelFa),
                  Text(_cur(s, r.baseCurrency)),
                  Text(_cur(s, r.quoteCurrency)),
                  Text('${r.count}'),
                  AmountText(r.baseTotalMinor, s.currency(r.baseCurrency)),
                  AmountText(r.quoteTotalMinor, s.currency(r.quoteCurrency)),
                  Text(
                    '${MoneyFormat.rate(r.minRate)} – ${MoneyFormat.rate(r.maxRate)}',
                    textDirection: TextDirection.ltr,
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- trial balance

class _TrialBalanceReport extends StatefulWidget {
  const _TrialBalanceReport();

  @override
  State<_TrialBalanceReport> createState() => _TrialBalanceReportState();
}

class _TrialBalanceReportState extends _ReportState<_TrialBalanceReport> {
  List<TrialBalanceRow> _rows = const [];

  @override
  Future<void> reload() async {
    final rows = await session.services.queries.trialBalance(asOf: asOf);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      loading = false;
    });
  }

  Map<String, List<TrialBalanceRow>> get _byCurrency {
    final out = <String, List<TrialBalanceRow>>{};
    for (final r in _rows) {
      out.putIfAbsent(r.currency, () => []).add(r);
    }
    return out;
  }

  void _export(AppSession s) {
    exportSheets(context, 'trial_balance_${asOf.iso}', [
      for (final e in _byCurrency.entries)
        ExportSheet(
          name: 'بیلانس ${e.key}',
          notes: ['بیلانس آزمایشی ${_cur(s, e.key)} تا ${DateFormatFa.business(asOf)}'],
          headers: const ['کد حساب', 'نام حساب', 'نوع', 'بدهکار', 'بستانکار', 'مانده (بدهکار مثبت)'],
          rows: [
            for (final r in e.value)
              [
                r.accountCode,
                r.accountName,
                r.accountType,
                MoneyFormat.amount(r.debitMinor, s.currency(e.key)),
                MoneyFormat.amount(r.creditMinor, s.currency(e.key)),
                MoneyFormat.amount(r.netMinor, s.currency(e.key)),
              ],
          ],
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final groups = _byCurrency;
    final first = groups.isEmpty ? null : groups.keys.first;
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.md),
      children: [
        if (loading) const SizedBox(height: 120, child: GfPageLoader()),
        if (!loading && groups.isEmpty)
          LedgerTable(
            shrinkWrap: true,
            title: 'بیلانس آزمایشی',
            actions: [asOfFilter()],
            emptyText: 'هنوز سندی ثبت نشده است.',
            columns: const [LedgerColumn('حساب')],
            rows: const [],
          ),
        for (final e in groups.entries) ...[
          LedgerTable(
            shrinkWrap: true,
            title: 'بیلانس آزمایشی ${_cur(s, e.key)}',
            subtitle: 'تا پایان ${DateFormatFa.business(asOf)}',
            actions: [
              () {
                final dr = e.value.fold<int>(0, (a, r) => a + r.debitMinor);
                final cr = e.value.fold<int>(0, (a, r) => a + r.creditMinor);
                return GfStatusBadge(
                  label: dr == cr ? 'تراز ✓' : 'ناتراز!',
                  color: dr == cr ? AppColors.success : AppColors.error,
                );
              }(),
              if (e.key == first) ...[asOfFilter(), ExportButton(onPressed: () => _export(s))],
            ],
            columns: const [
              LedgerColumn('کد', width: 120),
              LedgerColumn('حساب', flex: 3),
              LedgerColumn('بدهکار', flex: 2, numeric: true),
              LedgerColumn('بستانکار', flex: 2, numeric: true),
              LedgerColumn('مانده', flex: 2, numeric: true),
            ],
            rows: [
              for (final r in e.value)
                [
                  Text(r.accountCode, style: AppTypography.caption),
                  Text(r.accountName),
                  AmountText(r.debitMinor, s.currency(e.key)),
                  AmountText(r.creditMinor, s.currency(e.key)),
                  AmountText(r.netMinor, s.currency(e.key), bold: true),
                ],
              [
                const SizedBox.shrink(),
                Text('جمع', style: AppTypography.bodySemiBold),
                AmountText(e.value.fold<int>(0, (a, r) => a + r.debitMinor), s.currency(e.key), bold: true),
                AmountText(e.value.fold<int>(0, (a, r) => a + r.creditMinor), s.currency(e.key), bold: true),
                const SizedBox.shrink(),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------- income/expense

class _IncomeExpenseReport extends StatefulWidget {
  const _IncomeExpenseReport();

  @override
  State<_IncomeExpenseReport> createState() => _IncomeExpenseReportState();
}

class _IncomeExpenseReportState extends _ReportState<_IncomeExpenseReport> {
  List<TrialBalanceRow> _rows = const [];

  @override
  Future<void> reload() async {
    final rows = await session.services.queries.incomeAndExpense(from, to);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      loading = false;
    });
  }

  /// Revenue shown credit-positive, expense debit-positive.
  int _amount(TrialBalanceRow r) => r.accountType == 'revenue' ? -r.netMinor : r.netMinor;

  void _export(AppSession s) {
    exportSheets(context, 'income_expense_${from.iso}_${to.iso}', [
      ExportSheet(
        name: 'عواید و مصارف',
        notes: [
          'عواید و مصارف ثبت‌شده از ${DateFormatFa.business(from)} تا ${DateFormatFa.business(to)} (به تفکیک ارز)',
        ],
        headers: const ['ارز', 'کد حساب', 'حساب', 'نوع', 'مبلغ'],
        rows: [
          for (final r in _rows)
            [
              _cur(s, r.currency),
              r.accountCode,
              r.accountName,
              r.accountType == 'revenue' ? 'عاید' : 'مصرف',
              MoneyFormat.amount(_amount(r), s.currency(r.currency)),
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const InfoBanner(
          'فقط عواید و مصارف ثبت‌شده (کمیشن، مصارف، اضافه/کسر صندوق) نمایش داده می‌شود. '
          'سود تبادله بدون سیاست تأییدشده قیمت تمام‌شده محاسبه نمی‌شود.',
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LedgerTable(
            title: 'عواید و مصارف',
            subtitle: period.exportPeriodLabel,
            isLoading: loading,
            minWidth: 800,
            itemLabel: 'حساب',
            actions: [
              periodFilter(),
              ExportButton(onPressed: () => _export(s)),
            ],
            emptyText: 'در این دوره عاید یا مصرفی ثبت نشده است.',
            columns: const [
              LedgerColumn('ارز'),
              LedgerColumn('حساب', flex: 3),
              LedgerColumn('نوع'),
              LedgerColumn('مبلغ', flex: 2, numeric: true),
            ],
            rows: [
              for (final r in _rows)
                [
                  Text(_cur(s, r.currency)),
                  Text('${r.accountCode}  ${r.accountName}'),
                  Text(r.accountType == 'revenue' ? 'عاید' : 'مصرف'),
                  AmountText(_amount(r), s.currency(r.currency)),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- general ledger

class _GeneralLedgerReport extends StatefulWidget {
  const _GeneralLedgerReport();

  @override
  State<_GeneralLedgerReport> createState() => _GeneralLedgerReportState();
}

class _GeneralLedgerReportState extends _ReportState<_GeneralLedgerReport> {
  List<Map<String, Object?>> _accounts = const [];
  Map<String, Object?>? _account;
  Currency? _currency;
  List<({PostedTransaction tx, int debit, int credit, int running})> _lines = const [];

  @override
  Future<void> reload() async {
    final q = session.services.queries;
    final accounts = (await q.accounts()).where((a) => a['role'] != 'control').toList();
    _currency ??= session.activeCurrencies.isEmpty ? null : session.activeCurrencies.first;
    final account = _account == null
        ? (accounts.isEmpty ? null : accounts.first)
        : accounts.firstWhere((a) => a['id'] == _account!['id'], orElse: () => accounts.first);
    final lines = account == null || _currency == null
        ? const <({PostedTransaction tx, int debit, int credit, int running})>[]
        : await q.accountLedger(account['id'] as int, _currency!.code, from: from, to: to);
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _account = account;
      _lines = lines;
      loading = false;
    });
  }

  void _export(AppSession s) {
    final a = _account, c = _currency;
    if (a == null || c == null) return;
    exportSheets(context, 'ledger_${a['code']}_${c.code}', [
      ExportSheet(
        name: 'دفتر کل',
        notes: [
          'دفتر کل ${a['code']} ${a['name_fa']} — ${c.nameFa} — ${DateFormatFa.business(from)} تا ${DateFormatFa.business(to)}',
        ],
        headers: const ['تاریخ', 'شماره سند', 'نوع', 'مشتری', 'بدهکار', 'بستانکار', 'مانده (بدهکار مثبت)'],
        rows: [
          for (final l in _lines)
            [
              DateFormatFa.business(l.tx.effectiveDate),
              l.tx.referenceNo,
              l.tx.type.labelFa,
              l.tx.customerName ?? '',
              MoneyFormat.amount(l.debit, c),
              MoneyFormat.amount(l.credit, c),
              MoneyFormat.amount(l.running, c),
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final c = _currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LedgerTable(
            title: _account == null ? 'دفتر کل' : 'دفتر کل ${_account!['code']}  ${_account!['name_fa']}',
            subtitle: '${c?.nameFa ?? ''} — ${period.exportPeriodLabel}',
            isLoading: loading,
            minWidth: 1000,
            itemLabel: 'ردیف',
            actions: [
              GfDropdown<Map<String, Object?>>(
                width: 280,
                hint: 'حساب',
                prefixIcon: Icons.account_tree_outlined,
                items: _accounts,
                value: _account,
                searchable: true,
                labelBuilder: (a) => '${a['code']}  ${a['name_fa']}',
                onChanged: (a) {
                  _account = a;
                  reload();
                },
              ),
              GfDropdown<Currency>(
                width: 170,
                hint: 'ارز',
                prefixIcon: Icons.currency_exchange,
                items: s.activeCurrencies,
                value: c,
                labelBuilder: (v) => v.nameFa,
                onChanged: (v) {
                  if (v == null) return;
                  _currency = v;
                  reload();
                },
              ),
              periodFilter(),
              ExportButton(onPressed: () => _export(s)),
            ],
            emptyText: 'برای این حساب و ارز در این دوره گردشی نیست.',
            columns: const [
              LedgerColumn('تاریخ', width: 110),
              LedgerColumn('شماره سند', width: 130),
              LedgerColumn('نوع', flex: 2),
              LedgerColumn('مشتری', flex: 2),
              LedgerColumn('بدهکار', flex: 2, numeric: true),
              LedgerColumn('بستانکار', flex: 2, numeric: true),
              LedgerColumn('مانده', flex: 2, numeric: true),
            ],
            rows: [
              for (final l in _lines)
                [
                  Text(DateFormatFa.business(l.tx.effectiveDate)),
                  Text(l.tx.referenceNo, style: AppTypography.caption),
                  Text(l.tx.type.labelFa),
                  Text(l.tx.customerName ?? '—'),
                  l.debit == 0 ? const Text('') : AmountText(l.debit, c),
                  l.credit == 0 ? const Text('') : AmountText(l.credit, c),
                  AmountText(l.running, c, bold: true),
                ],
            ],
            onTapRow: (i) => TransactionDetailDialog.show(context, _lines[i].tx.id),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------- reconciliation history

class _ReconciliationHistoryReport extends StatefulWidget {
  const _ReconciliationHistoryReport();

  @override
  State<_ReconciliationHistoryReport> createState() => _ReconciliationHistoryReportState();
}

class _ReconciliationHistoryReportState extends _ReportState<_ReconciliationHistoryReport> {
  List<ReconciliationRecord> _rows = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    period = DateFilterValue.custom(from: now.subtract(const Duration(days: 30)), to: now);
  }

  @override
  Future<void> reload() async {
    final rows = await session.services.reconciliation.records(from: from, to: to);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      loading = false;
    });
  }

  String _status(ReconciliationRecord r) => switch (r.status) {
    'closed' => 'بسته',
    'open' => 'باز',
    _ => r.status,
  };

  void _export(AppSession s) {
    exportSheets(context, 'reconciliation_${from.iso}_${to.iso}', [
      ExportSheet(
        name: 'بیلانس صندوق',
        headers: const [
          'تاریخ',
          'صندوق',
          'ارز',
          'مانده اول',
          'ورودی',
          'خروجی',
          'مورد انتظار',
          'شمارش',
          'اختلاف',
          'وضعیت',
        ],
        rows: [
          for (final r in _rows)
            [
              DateFormatFa.business(r.businessDate),
              s.drawers.where((d) => d.id == r.drawerId).map((d) => d.nameFa).firstOrNull ?? '${r.drawerId}',
              _cur(s, r.currency),
              MoneyFormat.amount(r.openingMinor, s.currency(r.currency)),
              MoneyFormat.amount(r.inflowMinor, s.currency(r.currency)),
              MoneyFormat.amount(r.outflowMinor, s.currency(r.currency)),
              MoneyFormat.amount(r.expectedMinor, s.currency(r.currency)),
              MoneyFormat.amount(r.countedMinor, s.currency(r.currency)),
              MoneyFormat.amount(r.differenceMinor, s.currency(r.currency)),
              _status(r),
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: LedgerTable(
            title: 'سابقه بیلانس صندوق',
            subtitle: period.exportPeriodLabel,
            isLoading: loading,
            minWidth: 860,
            itemLabel: 'بیلانس',
            actions: [
              periodFilter(),
              ExportButton(onPressed: () => _export(s)),
            ],
            emptyText: 'در این دوره بیلانسی ثبت نشده است.',
            columns: const [
              LedgerColumn('تاریخ', width: 110),
              LedgerColumn('ارز'),
              LedgerColumn('مورد انتظار', flex: 2, numeric: true),
              LedgerColumn('شمارش', flex: 2, numeric: true),
              LedgerColumn('اختلاف', flex: 2, numeric: true),
              LedgerColumn('وضعیت'),
            ],
            rows: [
              for (final r in _rows)
                [
                  Text(DateFormatFa.business(r.businessDate)),
                  Text(_cur(s, r.currency)),
                  AmountText(r.expectedMinor, s.currency(r.currency)),
                  AmountText(r.countedMinor, s.currency(r.currency)),
                  AmountText(r.differenceMinor, s.currency(r.currency), signColor: true),
                  Text(_status(r)),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
