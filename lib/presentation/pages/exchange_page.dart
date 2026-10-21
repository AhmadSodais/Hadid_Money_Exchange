import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/posting_service.dart';
import '../../application/rate_service.dart';
import '../../application/read_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/errors/domain_errors.dart';
import '../../domain/exchange/exchange_rate.dart';
import '../../domain/money/currency.dart';
import '../../domain/money/decimal.dart';
import '../../domain/shared/business_date.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/order_detail_info_card.dart';
import '../widgets/settings_kit.dart';
import '../widgets/transaction_detail_dialog.dart';
import '../widgets/workbench_kit.dart';

/// خرید و فروش ارز. One submission = one atomic transaction with both
/// currency legs (and the optional fee); nothing is saved partially.
class ExchangePage extends StatefulWidget {
  const ExchangePage({super.key});

  @override
  State<ExchangePage> createState() => _ExchangePageState();
}

typedef _Preview = ({int? quoteMinor, String? error, int? baseMinor, Decimal? rate});

class _ExchangePageState extends State<ExchangePage> with RevisionReload {
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _fee = TextEditingController();
  final _description = TextEditingController();

  ExchangeDirection _direction = ExchangeDirection.buy;
  CustomerRecord? _customer;
  int? _drawerId;
  Currency? _base;
  Currency? _quote;
  Settlement _baseSettlement = Settlement.cash;
  Settlement _quoteSettlement = Settlement.cash;
  bool _feeEnabled = false;
  Currency? _feeCurrency;
  Settlement _feeSettlement = Settlement.cash;
  BusinessDate _date = BusinessDate.today();
  bool _rateEdited = false;
  bool _saving = false;
  String _key = PostingService.newIdempotencyKey();
  BoardRate? _board;

  List<CustomerBalance> _customerBalances = const [];
  Map<String, int> _drawerCash = const {};
  PostedTransaction? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDefaults());
  }

  Future<void> _initDefaults() async {
    final s = context.read<AppSession>();
    final settings = context.read<AppSettingsProvider>();
    final walkIn = await s.services.customers.walkIn();
    final currencies = s.activeCurrencies;
    Currency? find(String code) {
      for (final c in currencies) {
        if (c.code == code) return c;
      }
      return null;
    }

    if (!mounted) return;
    setState(() {
      _customer = walkIn;
      final drawers = s.activeDrawers;
      _drawerId = drawers.any((d) => d.id == settings.selectedDrawerId)
          ? settings.selectedDrawerId
          : (drawers.isEmpty ? null : drawers.first.id);
      _base = find('USD') ?? (currencies.isEmpty ? null : currencies.first);
      _quote = find('AFN') ?? (currencies.length > 1 ? currencies[1] : null);
      _feeCurrency = _quote;
    });
    await _loadBoardRate();
    await reload();
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _fee.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final s = session.services;
    final customer = _customer;
    final balances = customer == null || customer.isWalkIn
        ? const <CustomerBalance>[]
        : await s.queries.customerBalances(customer.id);
    final cash = _drawerId == null
        ? const <String, int>{}
        : await s.queries.cashBalances(drawerId: _drawerId);
    if (!mounted) return;
    setState(() {
      _customerBalances = balances;
      _drawerCash = cash;
    });
  }

  Decimal? get _boardRate {
    final b = _board;
    if (b == null) return null;
    return _direction == ExchangeDirection.buy ? b.buyRate : b.sellRate;
  }

  Future<void> _loadBoardRate() async {
    final base = _base, quote = _quote;
    if (base == null || quote == null || base == quote) {
      setState(() => _board = null);
      return;
    }
    final board = await session.services.rates.latest(base.code, quote.code);
    if (!mounted) return;
    setState(() {
      _board = board;
      if (!_rateEdited) _rate.text = _boardRate?.toCanonical() ?? '';
    });
  }

  void _useBoardRate() {
    setState(() {
      _rateEdited = false;
      _rate.text = _boardRate?.toCanonical() ?? '';
    });
  }

  void _swapCurrencies() {
    setState(() {
      final base = _base;
      _base = _quote;
      _quote = base;
      _rateEdited = false;
    });
    _loadBoardRate();
  }

  bool get _isWalkIn => _customer?.isWalkIn ?? true;

  void _onCustomer(CustomerRecord c) {
    setState(() {
      _customer = c;
      if (c.isWalkIn) {
        _baseSettlement = Settlement.cash;
        _quoteSettlement = Settlement.cash;
        _feeSettlement = Settlement.cash;
      }
    });
    reload();
  }

  _Preview _preview() {
    final base = _base, quote = _quote;
    if (base == null || quote == null) return (quoteMinor: null, error: null, baseMinor: null, rate: null);
    if (base == quote) {
      return (quoteMinor: null, error: 'ارز مبدأ و مقابل نباید یکی باشند.', baseMinor: null, rate: null);
    }
    if (_amount.text.trim().isEmpty || _rate.text.trim().isEmpty) {
      return (quoteMinor: null, error: null, baseMinor: null, rate: null);
    }
    try {
      final baseMinor = MoneyFormat.parse(_amount.text, base);
      if (baseMinor <= 0) {
        return (quoteMinor: null, error: 'مبلغ باید بزرگتر از صفر باشد.', baseMinor: null, rate: null);
      }
      final rate = Decimal.parse(_rate.text.replaceAll(',', ''));
      final quoteMinor = ExchangeRate.of(base, quote, rate).convert(baseMinor);
      return (quoteMinor: quoteMinor, error: null, baseMinor: baseMinor, rate: rate);
    } on DomainError catch (e) {
      return (quoteMinor: null, error: e.message, baseMinor: null, rate: null);
    }
  }

  int? get _feeMinor {
    final c = _feeCurrency;
    if (!_feeEnabled || c == null) return null;
    final minor = MoneyFormat.tryParse(_fee.text, c);
    return minor == null || minor <= 0 ? null : minor;
  }

  String _receiveLabel(Settlement s) =>
      s == Settlement.cash ? 'نقد دریافت می‌شود' : 'از حساب مشتری برداشت می‌شود';

  String _deliverLabel(Settlement s) =>
      s == Settlement.cash ? 'نقد پرداخت می‌شود' : 'به حساب مشتری واریز می‌شود';

  Future<void> _submit() async {
    final p = _preview();
    final base = _base, quote = _quote, customer = _customer, drawer = _drawerId;
    if (p.error != null || p.quoteMinor == null || base == null || quote == null ||
        customer == null || drawer == null) {
      GfToast.error(context, p.error ?? 'لطفاً همه فیلدهای الزامی را کامل کنید.');
      return;
    }
    ExchangeFee? fee;
    if (_feeEnabled) {
      final feeCur = _feeCurrency;
      final feeMinor = _feeMinor;
      if (feeCur == null || feeMinor == null) {
        GfToast.error(context, 'مبلغ کمیشن معتبر نیست.');
        return;
      }
      fee = ExchangeFee(currency: feeCur.code, amountMinor: feeMinor, settlement: _feeSettlement);
    }

    final buy = _direction == ExchangeDirection.buy;
    final confirmed = await _confirm(
      base: base,
      quote: quote,
      baseMinor: p.baseMinor!,
      quoteMinor: p.quoteMinor!,
      rate: p.rate!,
      customer: customer,
      fee: fee,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final cmd = ExchangeCommand(
      idempotencyKey: _key,
      effectiveDate: _date,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      direction: _direction,
      customerId: customer.id,
      drawerId: drawer,
      baseCurrency: base.code,
      quoteCurrency: quote.code,
      baseAmountMinor: p.baseMinor!,
      rate: p.rate!,
      baseSettlement: _baseSettlement,
      quoteSettlement: _quoteSettlement,
      fee: fee,
    );
    final s = context.read<AppSession>();
    final posted = await runAction(context, () => s.services.posting.post(cmd, s.actor));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (posted != null) {
        _last = posted;
        _key = PostingService.newIdempotencyKey();
        _amount.clear();
        _fee.clear();
        _description.clear();
      }
    });
    if (posted != null) {
      GfToast.success(context, '${buy ? 'خرید' : 'فروش'} ثبت شد — شماره سند ${posted.referenceNo}');
    }
  }

  Future<bool?> _confirm({
    required Currency base,
    required Currency quote,
    required int baseMinor,
    required int quoteMinor,
    required Decimal rate,
    required CustomerRecord customer,
    ExchangeFee? fee,
  }) {
    final buy = _direction == ExchangeDirection.buy;
    final s = context.read<AppSession>();
    final feeCur = fee == null ? null : s.currency(fee.currency);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => GfDialogShell(
        icon: Icons.fact_check_outlined,
        iconColor: AppColors.primary,
        title: 'تأیید ${buy ? 'خرید' : 'فروش'} ارز',
        subtitle: 'جزئیات را پیش از ثبت نهایی بررسی کنید.',
        cancelLabel: 'بازگشت',
        onCancel: () => Navigator.of(ctx).pop(false),
        primaryLabel: 'ثبت نهایی',
        primaryIcon: Icons.save_outlined,
        onPrimary: () => Navigator.of(ctx).pop(true),
        maxWidth: 480,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogResponsiveRow(
              children: [
                DialogMetricBox(
                  icon: Icons.south_west,
                  title: 'صرافی دریافت می‌کند',
                  value: buy ? MoneyFormat.withName(baseMinor, base) : MoneyFormat.withName(quoteMinor, quote),
                  hint: buy ? _receiveLabel(_baseSettlement) : _receiveLabel(_quoteSettlement),
                ),
                DialogMetricBox(
                  icon: Icons.north_east,
                  title: 'صرافی پرداخت می‌کند',
                  value: buy ? MoneyFormat.withName(quoteMinor, quote) : MoneyFormat.withName(baseMinor, base),
                  hint: buy ? _deliverLabel(_quoteSettlement) : _deliverLabel(_baseSettlement),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OrderDetailSummaryCard(
              rows: [
                OrderDetailSummaryRow(label: 'مشتری', value: customer.name, dense: true),
                OrderDetailSummaryRow(
                  label: 'نرخ',
                  value: '1 ${base.nameFa} = ${MoneyFormat.decimal(rate)} ${quote.nameFa}',
                  dense: true,
                ),
                if (fee != null)
                  OrderDetailSummaryRow(
                    label: 'کمیشن',
                    value: '${MoneyFormat.withName(fee.amountMinor, feeCur)} — ${_receiveLabel(fee.settlement)}',
                    dense: true,
                  ),
                OrderDetailSummaryRow(label: 'تاریخ', value: DateFormatFa.business(_date), dense: true),
              ],
            ),
            const SizedBox(height: 14),
            const DialogInfoBanner(
              message: 'در صورت اشتباه، معامله را بعداً از روزنامچه ویرایش یا حذف کنید؛ موجودی‌ها خودکار اصلاح می‌شوند.',
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ form

  Widget _partySection(SettingsMetrics m, AppSession s) {
    return WorkbenchSection(
      step: 1,
      title: 'طرف معامله',
      subtitle: 'مشتری، صندوق و تاریخ معامله',
      padding: m.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkbenchPartyFields(
            gap: m.fieldGap,
            customer: CustomerPickerField(selected: _customer, allowWalkIn: true, onSelected: _onCustomer),
            drawer: DrawerPicker(
              value: _drawerId,
              onChanged: (id) {
                setState(() => _drawerId = id);
                context.read<AppSettingsProvider>().setSelectedDrawerId(id);
                reload();
              },
            ),
            date: BusinessDateField(value: _date, onChanged: (d) => setState(() => _date = d)),
          ),
          if (!_isWalkIn) ...[
            SizedBox(height: m.fieldGap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('مانده فعلی حساب:', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                if (_customerBalances.isEmpty)
                  GfStatusBadge(label: 'تسویه', color: AppColors.textMuted, compact: true)
                else
                  for (final b in _customerBalances)
                    GfStatusBadge(
                      label: MoneyFormat.position(b.positionMinor, s.currency(b.currency)),
                      color: b.positionMinor > 0 ? AppColors.success : AppColors.error,
                      compact: true,
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _amountSection(SettingsMetrics m, _Preview p, bool buy) {
    final base = _base, quote = _quote;
    final board = _boardRate;

    final basePicker = CurrencyPicker(
      label: buy ? 'ارزی که خریده می‌شود' : 'ارزی که فروخته می‌شود',
      value: base,
      onChanged: (c) {
        setState(() {
          _base = c;
          _rateEdited = false;
        });
        _loadBoardRate();
      },
    );
    final quotePicker = CurrencyPicker(
      label: 'ارز مقابل',
      value: quote,
      onChanged: (c) {
        setState(() {
          _quote = c;
          _rateEdited = false;
        });
        _loadBoardRate();
      },
    );
    final amount = AmountField(
      controller: _amount,
      label: 'مبلغ ${base?.nameFa ?? ''}',
      onChanged: (_) => setState(() {}),
    );
    final rate = GfTextField(
      label: 'نرخ',
      hint: '۱ ${base?.nameFa ?? ''} = ? ${quote?.nameFa ?? ''}',
      controller: _rate,
      required: true,
      textAlign: TextAlign.end,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [ThousandsSeparatorInputFormatter()],
      onChanged: (_) => setState(() => _rateEdited = true),
    );
    final result = _ResultField(
      label: 'مبلغ ${quote?.nameFa ?? 'مقابل'} (محاسبه خودکار)',
      value: p.quoteMinor == null ? null : MoneyFormat.amount(p.quoteMinor!, quote),
    );
    final swap = GfIconButton(
      icon: Icons.swap_horiz_rounded,
      tooltip: 'جابه‌جایی ارزها',
      onPressed: _swapCurrencies,
    );
    final rateHint = Row(
      children: [
        Icon(Icons.info_outline, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            board == null
                ? 'برای این جفت ارز نرخ تابلو ثبت نشده است.'
                : 'نرخ تابلو (${buy ? 'خرید' : 'فروش'}): ۱ ${base?.nameFa ?? ''} = '
                    '${MoneyFormat.decimal(board)} ${quote?.nameFa ?? ''}',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
        if (board != null && _rateEdited && _rate.text != board.toCanonical())
          TextButton.icon(
            onPressed: _useBoardRate,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('استفاده از نرخ تابلو'),
          ),
      ],
    );
    final description = GfTextField(
      label: 'شرح (اختیاری)',
      controller: _description,
      maxLines: 2,
      minLines: 1,
    );

    return WorkbenchSection(
      step: 2,
      title: 'مبلغ و نرخ',
      subtitle: 'مبلغ مقابل = مبلغ × نرخ؛ نرخ تابلو خودکار پر می‌شود و قابل تغییر است.',
      padding: m.cardPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = m.fieldGap;
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                basePicker,
                SizedBox(height: gap),
                amount,
                SizedBox(height: gap),
                rate,
                const SizedBox(height: 6),
                rateHint,
                SizedBox(height: gap),
                quotePicker,
                SizedBox(height: gap),
                result,
                SizedBox(height: gap),
                description,
              ],
            );
          }
          final middle = constraints.maxWidth < 720 ? 140.0 : 200.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: basePicker),
                  SizedBox(width: gap),
                  SizedBox(width: middle, child: Center(child: swap)),
                  SizedBox(width: gap),
                  Expanded(child: quotePicker),
                ],
              ),
              SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: amount),
                  SizedBox(width: gap),
                  SizedBox(width: middle, child: rate),
                  SizedBox(width: gap),
                  Expanded(child: result),
                ],
              ),
              const SizedBox(height: 8),
              rateHint,
              SizedBox(height: gap),
              description,
            ],
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------- summary

  /// Change of the customer's position per currency if this deal is posted.
  Map<String, int> _customerEffect(_Preview p, bool buy) {
    final effect = <String, int>{};
    void add(Currency? c, int delta) {
      if (c == null) return;
      effect[c.code] = (effect[c.code] ?? 0) + delta;
    }

    if (p.baseMinor == null || p.quoteMinor == null) return effect;
    if (_baseSettlement == Settlement.customer) add(_base, buy ? -p.baseMinor! : p.baseMinor!);
    if (_quoteSettlement == Settlement.customer) add(_quote, buy ? p.quoteMinor! : -p.quoteMinor!);
    final fee = _feeMinor;
    if (fee != null && _feeSettlement == Settlement.customer) add(_feeCurrency, -fee);
    return effect;
  }

  Widget _summary(AppSession s, _Preview p, bool buy) {
    final base = _base, quote = _quote;
    final ready = p.error == null && p.baseMinor != null && p.quoteMinor != null && base != null && quote != null;
    String? drawerName;
    for (final d in s.activeDrawers) {
      if (d.id == _drawerId) drawerName = d.nameFa;
    }

    final children = <Widget>[];
    if (p.error != null) {
      children.add(InfoBanner(p.error!, tone: BannerTone.error));
    } else if (!ready) {
      children.add(const WorkbenchHint(
        icon: Icons.calculate_outlined,
        text: 'ارز، مبلغ و نرخ را وارد کنید تا خلاصه معامله این‌جا نمایش داده شود.',
      ));
    } else {
      final baseMinor = p.baseMinor!, quoteMinor = p.quoteMinor!;
      // The currency leaving the drawer as cash, if any.
      final (Currency? outCur, int outMinor) = buy
          ? (_quoteSettlement == Settlement.cash ? (quote, quoteMinor) : (null, 0))
          : (_baseSettlement == Settlement.cash ? (base, baseMinor) : (null, 0));
      final available = outCur == null ? null : (_drawerCash[outCur.code] ?? 0);
      final short = available != null && available < outMinor;
      final fee = _feeMinor;

      children.addAll([
        WorkbenchFlowLine(
          incoming: true,
          label: 'صرافی دریافت می‌کند',
          amount: buy ? MoneyFormat.withName(baseMinor, base) : MoneyFormat.withName(quoteMinor, quote),
          hint: buy ? _receiveLabel(_baseSettlement) : _receiveLabel(_quoteSettlement),
        ),
        WorkbenchFlowLine(
          incoming: false,
          label: 'صرافی پرداخت می‌کند',
          amount: buy ? MoneyFormat.withName(quoteMinor, quote) : MoneyFormat.withName(baseMinor, base),
          hint: buy ? _deliverLabel(_quoteSettlement) : _deliverLabel(_baseSettlement),
          amountColor: short ? AppColors.error : null,
        ),
        if (fee != null)
          WorkbenchFlowLine(
            incoming: true,
            label: 'کمیشن',
            amount: MoneyFormat.withName(fee, _feeCurrency),
            hint: _receiveLabel(_feeSettlement),
          ),
        Divider(height: 1, color: AppColors.divider),
        WorkbenchValueRow(
          label: 'نرخ',
          value: '۱ ${base.nameFa} = ${MoneyFormat.decimal(p.rate!)} ${quote.nameFa}',
          bold: true,
        ),
        WorkbenchValueRow(label: 'مشتری', value: _customer?.name ?? '—'),
        WorkbenchValueRow(label: 'صندوق اصلی', value: drawerName ?? '—'),
        WorkbenchValueRow(label: 'تاریخ', value: DateFormatFa.business(_date)),
        if (outCur != null)
          WorkbenchBalanceChange(
            icon: Icons.point_of_sale_outlined,
            label: 'موجودی نقد ${outCur.nameFa} در صندوق',
            before: MoneyFormat.amount(available!, outCur),
            after: MoneyFormat.amount(available - outMinor, outCur),
            afterColor: short ? AppColors.error : null,
          ),
        if (short)
          const InfoBanner(
            'این پرداخت نمی‌تواند از موجودی فعلی صندوق اصلی مشترک بیشتر باشد.',
            tone: BannerTone.error,
          ),
        for (final e in _customerEffect(p, buy).entries)
          if (e.value != 0)
            Builder(builder: (context) {
              final c = s.currency(e.key);
              var before = 0;
              for (final b in _customerBalances) {
                if (b.currency == e.key) before = b.positionMinor;
              }
              return WorkbenchBalanceChange(
                icon: Icons.account_balance_wallet_outlined,
                label: 'حساب ${_customer?.name ?? ''} — ${c?.nameFa ?? e.key}',
                before: MoneyFormat.position(before, c),
                after: MoneyFormat.position(before + e.value, c),
                afterColor: before + e.value < 0 ? AppColors.error : AppColors.success,
              );
            }),
      ]);
    }

    return WorkbenchSummaryPanel(
      icon: buy ? Icons.south_west_rounded : Icons.north_east_rounded,
      title: buy ? 'خلاصه خرید ارز' : 'خلاصه فروش ارز',
      subtitle: _isWalkIn ? 'مشتری متفرقه — تسویه نقدی' : _customer?.name,
      accent: buy ? AppColors.success : AppColors.info,
      height: 640,
      centerChildren: !ready,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfPrimaryButton(
            label: buy ? 'ثبت خرید' : 'ثبت فروش',
            icon: Icons.check,
            expanded: true,
            isLoading: _saving,
            onPressed: _saving || !ready ? null : _submit,
          ),
          const SizedBox(height: 8),
          Text(
            'پس از ثبت، از روزنامچه قابل ویرایش یا حذف است.',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
      children: children,
    );
  }

  Widget _lastCard(AppSession s, SettingsMetrics m) {
    final last = _last!;
    return SettingsSectionCard(
      icon: Icons.history,
      title: 'آخرین معامله ثبت‌شده',
      padding: m.cardPadding,
      trailing: GfStatusBadge(label: last.referenceNo, color: AppColors.success, compact: true),
      actions: [
        GfSecondaryButton(
          label: 'جزئیات',
          icon: Icons.receipt_long_outlined,
          compact: true,
          onPressed: () => TransactionDetailDialog.show(context, last.id),
        ),
      ],
      child: Text(
        '${last.type.labelFa} ${MoneyFormat.withName(last.sourceAmountMinor ?? 0, s.currency(last.sourceCurrency))} '
        'در برابر ${MoneyFormat.withName(last.destAmountMinor ?? 0, s.currency(last.destCurrency))}',
        style: AppTypography.body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final p = _preview();
    final buy = _direction == ExchangeDirection.buy;

    return PageScaffold(
      title: 'خرید و فروش ارز',
      subtitle: 'خرید یا فروش ارز با مشتری؛ ارز، مبلغ و نرخ را وارد کنید و معامله را ثبت کنید.',
      body: WorkbenchLayout(
        main: (m) => [
          WorkbenchModeSelector<ExchangeDirection>(
            gap: m.fieldGap,
            value: _direction,
            onChanged: (v) {
              setState(() {
                _direction = v;
                _rateEdited = false;
              });
              _loadBoardRate();
            },
            options: [
              WorkbenchModeOption(
                ExchangeDirection.buy,
                'خرید ارز',
                'صرافی از مشتری ارز می‌گیرد و پول مقابل می‌پردازد.',
                Icons.south_west_rounded,
                color: AppColors.success,
              ),
              WorkbenchModeOption(
                ExchangeDirection.sell,
                'فروش ارز',
                'صرافی به مشتری ارز می‌دهد و پول مقابل می‌گیرد.',
                Icons.north_east_rounded,
                color: AppColors.info,
              ),
            ],
          ),
          _partySection(m, s),
          _amountSection(m, p, buy),
        ],
        side: (m) => [
          _summary(s, p, buy),
          if (_last != null) _lastCard(s, m),
        ],
      ),
    );
  }
}

/// Read-only field showing a computed amount, styled like an input.
class _ResultField extends StatelessWidget {
  const _ResultField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.label, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: AppSpacing.controlHeightOf(context),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: AppRadius.input,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.calculate_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value ?? '—',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySemiBold.copyWith(
                    color: value == null ? AppColors.textMuted : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
