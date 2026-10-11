import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/rate_service.dart';
import '../../core/constants/app_assets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/money/decimal.dart';
import '../../domain/security/permissions.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/order_detail_info_card.dart';

/// Board rates are suggestions for the exchange form only. Each posted
/// transaction stores the rate actually used, so changing the board never
/// alters history.
class RatesPage extends StatefulWidget {
  const RatesPage({super.key});

  @override
  State<RatesPage> createState() => _RatesPageState();
}

class _RatesPageState extends State<RatesPage> with RevisionReload {
  bool _loading = true;
  List<BoardRate> _board = const [];

  @override
  Future<void> reload() async {
    final board = await session.services.rates.board();
    if (!mounted) return;
    setState(() {
      _board = board;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canManage = s.can(Permissions.ratesManage);
    return PageScaffold(
      title: 'نرخ ارز',
      subtitle: 'قرارداد نرخ: ۱ واحد ارز مبدأ = R واحد ارز مقابل. نرخ خرید و فروش جداگانه ثبت می‌شود.',
      actions: [
        if (canManage)
          GfPrimaryButton(
            label: 'ثبت نرخ',
            icon: Icons.add_chart,
            onPressed: () => _RateDialog.show(context),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GfCountBox(label: 'جفت ارزهای فعال', count: _board.length, icon: AppAssets.currenciesFilled),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: LedgerTable(
              title: 'تابلوی نرخ',
              subtitle: 'برای دیدن سابقه نرخ، روی ردیف کلیک کنید.',
              isLoading: _loading,
              minWidth: 900,
              itemLabel: 'نرخ',
              emptyText: 'هنوز نرخی ثبت نشده است.',
              emptyHint: 'نرخ‌ها هرگز به‌صورت پیش‌فرض در برنامه تعیین نمی‌شوند.',
              columns: const [
                LedgerColumn.dateTime('زمان ثبت'),
                LedgerColumn.text('ارز مبدأ'),
                LedgerColumn.text('ارز مقابل'),
                LedgerColumn.amount('نرخ خرید'),
                LedgerColumn.amount('نرخ فروش'),
                LedgerColumn.actions(),
              ],
              rows: [
                for (final r in _board)
                  [
                    Text(DateFormatFa.dateTime(r.effectiveAt), style: AppTypography.body),
                    Text(s.currency(r.base)?.nameFa ?? r.base, style: AppTypography.bodyMedium),
                    Text(s.currency(r.quote)?.nameFa ?? r.quote, style: AppTypography.body),
                    Text(MoneyFormat.decimal(r.buyRate), textDirection: TextDirection.ltr, style: AppTypography.bodyMedium),
                    Text(MoneyFormat.decimal(r.sellRate), textDirection: TextDirection.ltr, style: AppTypography.bodyMedium),
                    LedgerRowMenu(
                      onSelected: (a) {
                        if (a == 'edit') {
                          _RateDialog.show(context, base: s.currency(r.base), quote: s.currency(r.quote), current: r);
                        } else {
                          _HistoryDialog.show(context, r.base, r.quote);
                        }
                      },
                      items: [
                        if (canManage) gfPopupMenuItem(value: 'edit', label: 'ثبت نرخ جدید'),
                        gfPopupMenuItem(value: 'history', label: 'سابقه نرخ'),
                      ],
                    ),
                  ],
              ],
              onTapRow: (i) => _HistoryDialog.show(context, _board[i].base, _board[i].quote),
            ),
          ),
        ],
      ),
    );
  }
}

class _RateDialog extends StatefulWidget {
  const _RateDialog({this.base, this.quote, this.current});

  final Currency? base;
  final Currency? quote;
  final BoardRate? current;

  static Future<void> show(BuildContext context, {Currency? base, Currency? quote, BoardRate? current}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: _RateDialog(base: base, quote: quote, current: current),
      ),
    );
  }

  @override
  State<_RateDialog> createState() => _RateDialogState();
}

class _RateDialogState extends State<_RateDialog> {
  late Currency? _base = widget.base;
  late Currency? _quote = widget.quote;
  late final _buy = TextEditingController(text: widget.current?.buyRate.toCanonical());
  late final _sell = TextEditingController(text: widget.current?.sellRate.toCanonical());
  bool _saving = false;

  @override
  void dispose() {
    _buy.dispose();
    _sell.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final base = _base, quote = _quote;
    final buy = Decimal.tryParse(_buy.text.replaceAll(',', ''));
    final sell = Decimal.tryParse(_sell.text.replaceAll(',', ''));
    if (base == null || quote == null || buy == null || sell == null) {
      GfToast.error(context, 'ارزها و هر دو نرخ را وارد کنید.');
      return;
    }
    setState(() => _saving = true);
    final s = context.read<AppSession>();
    final ok = await runAction(
      context,
      () async {
        await s.services.rates.setRate(base: base.code, quote: quote.code, buyRate: buy, sellRate: sell, actor: s.actor);
        return true;
      },
      success: 'نرخ ثبت شد.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.show_chart,
      iconColor: AppColors.primary,
      title: widget.current == null ? 'ثبت نرخ ارز' : 'ثبت نرخ جدید',
      subtitle: 'نرخ قبلی در سابقه می‌ماند و معاملات ثبت‌شده تغییر نمی‌کنند.',
      cancelLabel: 'انصراف',
      onCancel: () => Navigator.of(context).pop(),
      primaryLabel: 'ثبت',
      primaryIcon: Icons.save_outlined,
      onPrimary: _save,
      saving: _saving,
      maxWidth: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogResponsiveRow(
            children: [
              CurrencyPicker(label: 'ارز مبدأ (۱ واحد)', value: _base, onChanged: (c) => setState(() => _base = c)),
              CurrencyPicker(label: 'ارز مقابل', value: _quote, onChanged: (c) => setState(() => _quote = c)),
            ],
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                label: 'نرخ خرید (صرافی می‌خرد)',
                controller: _buy,
                textAlign: TextAlign.end,
                inputFormatters: const [ThousandsSeparatorInputFormatter()],
                onChanged: (_) => setState(() {}),
              ),
              GfTextField(
                label: 'نرخ فروش (صرافی می‌فروشد)',
                controller: _sell,
                textAlign: TextAlign.end,
                inputFormatters: const [ThousandsSeparatorInputFormatter()],
              ),
            ],
          ),
          if (_base != null && _quote != null) ...[
            const SizedBox(height: 14),
            DialogInfoBanner(
              message: '۱ ${_base!.nameFa} = ${_buy.text.isEmpty ? 'R' : _buy.text} ${_quote!.nameFa} '
                  '(حداکثر ${_base!.rateScale} رقم اعشار)',
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({required this.base, required this.quote});

  final String base;
  final String quote;

  static Future<void> show(BuildContext context, String base, String quote) {
    return OrderDetailDialogFrame.show<void>(
      context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: _HistoryDialog(base: base, quote: quote),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppSession>();
    return FutureBuilder<List<BoardRate>>(
      future: s.services.rates.history(base, quote, limit: 100),
      builder: (context, snap) {
        final history = snap.data ?? const <BoardRate>[];
        final latest = history.isEmpty ? null : history.first;
        return OrderDetailDialogFrame(
          icon: Icons.history,
          title: 'سابقه نرخ ${s.currency(base)?.nameFa ?? base} → ${s.currency(quote)?.nameFa ?? quote}',
          subtitle: '۱ ${s.currency(base)?.nameFa ?? base} = R ${s.currency(quote)?.nameFa ?? quote}',
          body: !snap.hasData
              ? const SizedBox(height: 200, child: GfPageLoader())
              : OrderDetailLinesTable(
                  emptyText: 'سابقه‌ای ثبت نشده است.',
                  columns: const [
                    LedgerColumn.dateTime(),
                    LedgerColumn.amount('خرید'),
                    LedgerColumn.amount('فروش'),
                  ],
                  rows: [
                    for (final r in history)
                      [
                        Text(DateFormatFa.dateTime(r.effectiveAt)),
                        Text(MoneyFormat.decimal(r.buyRate), textDirection: TextDirection.ltr),
                        Text(MoneyFormat.decimal(r.sellRate), textDirection: TextDirection.ltr),
                      ],
                  ],
                ),
          summary: latest == null
              ? null
              : OrderDetailStatPanel(
                  stats: [
                    OrderDetailStat('تعداد ثبت', '${history.length}'),
                    OrderDetailStat('آخرین ثبت', DateFormatFa.dateTime(latest.effectiveAt)),
                  ],
                  highlights: [
                    OrderDetailStat('نرخ خرید فعلی', MoneyFormat.decimal(latest.buyRate)),
                    OrderDetailStat('نرخ فروش فعلی', MoneyFormat.decimal(latest.sellRate)),
                  ],
                ),
        );
      },
    );
  }
}
