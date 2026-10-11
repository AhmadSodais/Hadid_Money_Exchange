import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../application/rate_service.dart';
import '../../application/read_models.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/shared/business_date.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/full_screen_toggle.dart';
import '../widgets/theme_mode_toggle.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with RevisionReload {
  bool _loading = true;
  Map<String, int> _cash = const {};
  Map<String, ({int liabilities, int receivables})> _customers = const {};
  List<DailyTypeSummary> _today = const [];
  List<BoardRate> _rates = const [];
  List<String> _problems = const [];
  String? _lastBackup;

  @override
  Future<void> reload() async {
    final s = session.services;
    final today = BusinessDate.today();
    final cash = await s.queries.cashBalances(asOf: today);
    final customers = await s.queries.customerTotals(asOf: today);
    final summary = await s.queries.typeSummary(today, today);
    final rates = await s.rates.board();
    final problems = await s.queries.integrityProblems();
    final history = await s.backups.history();
    if (!mounted) return;
    setState(() {
      _cash = cash;
      _customers = customers;
      _today = summary;
      _rates = rates;
      _problems = problems;
      _lastBackup = history.isEmpty ? null : history.first['created_at'] as String?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AppSession>();
    return PageScaffold(
      title: 'داشبورد',
      subtitle: 'امروز: ${DateFormatFa.business(BusinessDate.today())}',
      actions: const [
        FullScreenToggle(),
        ThemeModeToggle(),
      ],
      padBody: false,
      body: _loading
          ? const GfPageLoader()
          : ListView(
              padding: PageScaffold.pageBodyPadding(context),
              children: [
                if (_problems.isNotEmpty) ...[
                  InfoBanner(
                    'بررسی صحت دفاتر مشکل یافت: ${_problems.join(' — ')}',
                    tone: BannerTone.error,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_lastBackup == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: InfoBanner(
                      'هنوز هیچ نسخه پشتیبان تهیه نشده است.',
                      tone: BannerTone.warning,
                    ),
                  ),
                LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final columns = w >= 1200 ? 4 : (w >= 860 ? 3 : (w >= 520 ? 2 : 1));
                  const gap = AppSpacing.md;
                  final cardWidth = (w - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final c in session.activeCurrencies)
                        SizedBox(
                          width: cardWidth,
                          child: _CurrencyCard(
                            currency: c,
                            cash: _cash[c.code] ?? 0,
                            owedToCustomers: _customers[c.code]?.liabilities ?? 0,
                            owedByCustomers: _customers[c.code]?.receivables ?? 0,
                          ),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.md),
                LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth > 900;
                  final activity = _TodayActivity(rows: _today, session: session);
                  final rates = _RatesPreview(rates: _rates, session: session);
                  if (!wide) {
                    return Column(children: [activity, const SizedBox(height: AppSpacing.md), rates]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: activity),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: rates),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _lastBackup == null
                      ? 'آخرین پشتیبان: —'
                      : 'آخرین پشتیبان: ${DateFormatFa.dateTime(DateTime.parse(_lastBackup!))}',
                  style: AppTypography.caption,
                ),
              ],
            ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({
    required this.currency,
    required this.cash,
    required this.owedToCustomers,
    required this.owedByCustomers,
  });

  final Currency currency;
  final int cash;
  final int owedToCustomers;
  final int owedByCustomers;

  @override
  Widget build(BuildContext context) {
    return GfKpiCard(
      title: '${currency.nameFa} (${currency.code})',
      icon: AppAssets.currenciesFilled,
      tone: cash < 0 ? GfKpiTone.error : GfKpiTone.normal,
      onTap: () => context.go(AppRoutes.reports),
      currencies: [
        GfKpiCurrencyLine(
          amountText: MoneyFormat.amount(cash, currency),
          currencyLabel: 'نقد صندوق',
          color: cash < 0 ? AppColors.error : null,
        ),
        GfKpiCurrencyLine(
          amountText: MoneyFormat.amount(owedToCustomers, currency),
          currencyLabel: 'طلب مشتریان',
        ),
        GfKpiCurrencyLine(
          amountText: MoneyFormat.amount(owedByCustomers, currency),
          currencyLabel: 'بدهی مشتریان',
        ),
      ],
    );
  }
}

/// Rows per page of the dashboard tables; both share it so they stay the
/// same height side by side.
const int _dashboardTableRows = 5;

class _TodayActivity extends StatelessWidget {
  const _TodayActivity({required this.rows, required this.session});

  final List<DailyTypeSummary> rows;
  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LedgerTable(
      shrinkWrap: true,
      fixedRows: _dashboardTableRows,
      itemLabel: 'مورد',
      title: 'فعالیت امروز',
      subtitle: 'معاملات ثبت‌شده به تفکیک نوع و ارز',
      actions: [
        GfSecondaryButton(
          label: 'روزنامچه',
          icon: Icons.receipt_long_outlined,
          compact: true,
          onPressed: () => context.go(AppRoutes.journal),
        ),
      ],
      emptyText: 'امروز معامله‌ای ثبت نشده است.',
      columns: const [
        LedgerColumn.text('نوع'),
        LedgerColumn.text('ارز'),
        LedgerColumn.number('تعداد'),
        LedgerColumn.amount('مجموع'),
      ],
      rows: [
        for (final r in rows)
          [
            Text(r.type.labelFa, style: AppTypography.bodyMedium),
            Text(session.currency(r.currency)?.nameFa ?? r.currency, style: AppTypography.body),
            Text('${r.count}', style: AppTypography.body),
            AmountText(r.totalMinor, session.currency(r.currency)),
          ],
      ],
    );
  }
}

class _RatesPreview extends StatelessWidget {
  const _RatesPreview({required this.rates, required this.session});

  final List<BoardRate> rates;
  final AppSession session;

  @override
  Widget build(BuildContext context) {
    return LedgerTable(
      shrinkWrap: true,
      fixedRows: _dashboardTableRows,
      itemLabel: 'نرخ',
      title: 'نرخ‌های جاری',
      subtitle: 'نرخ پیشنهادی فرم تبادله',
      actions: [
        GfSecondaryButton(
          label: 'مدیریت نرخ‌ها',
          icon: Icons.show_chart,
          compact: true,
          onPressed: () => context.go(AppRoutes.rates),
        ),
      ],
      emptyText: 'هنوز نرخی ثبت نشده است.',
      columns: const [
        LedgerColumn.primary('جفت ارز'),
        LedgerColumn.amount('خرید'),
        LedgerColumn.amount('فروش'),
      ],
      rows: [
        for (final r in rates)
          [
            Text(
              '1 ${session.currency(r.base)?.nameFa ?? r.base} → ${session.currency(r.quote)?.nameFa ?? r.quote}',
              style: AppTypography.bodyMedium,
            ),
            Text(MoneyFormat.decimal(r.buyRate), textDirection: TextDirection.ltr, style: AppTypography.body),
            Text(MoneyFormat.decimal(r.sellRate), textDirection: TextDirection.ltr, style: AppTypography.body),
          ],
      ],
    );
  }
}
