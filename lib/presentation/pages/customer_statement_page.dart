import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../application/ledger_queries.dart';
import '../../application/posting_service.dart';
import '../../application/read_models.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/security/permissions.dart';
import '../../domain/shared/business_date.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/transaction_detail_dialog.dart';

class CustomerStatementPage extends StatefulWidget {
  const CustomerStatementPage({super.key, required this.customerId});

  final int customerId;

  @override
  State<CustomerStatementPage> createState() => _CustomerStatementPageState();
}

class _CustomerStatementPageState extends State<CustomerStatementPage> with RevisionReload {
  CustomerRecord? _customer;
  List<CustomerBalance> _balances = const [];

  /// `null` = every currency.
  String? _currencyCode;

  /// `null` = the whole history.
  DateFilterValue? _period;

  /// The customer's transactions in the period, newest first: one row per
  /// deal, so a cash buy/sell shows up too (it never touches the account).
  List<PostedTransaction> _txs = const [];
  bool _loading = true;
  bool _notFound = false;
  final _search = TextEditingController();
  _TypeFilter _typeFilter = _TypeFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The standard view lists current deals only; earlier versions of edited
  /// deals and deleted deals are grouped under [_TypeFilter.changed].
  List<PostedTransaction> _visible(AppSession s) {
    final history = _typeFilter == _TypeFilter.changed;
    final types = _typeFilter.types;
    final query = _search.text.trim().toLowerCase();
    bool currencyMatches(String? code) => code != null && (s.currency(code)?.nameFa.contains(query) ?? false);
    return [
      for (final t in _txs)
        if (t.isActive != history &&
            (_currencyCode == null || t.sourceCurrency == _currencyCode || t.destCurrency == _currencyCode) &&
            (types == null || types.contains(t.type)) &&
            (query.isEmpty ||
                t.referenceNo.toLowerCase().contains(query) ||
                t.type.labelFa.contains(query) ||
                (t.description?.toLowerCase().contains(query) ?? false) ||
                currencyMatches(t.sourceCurrency) ||
                currencyMatches(t.destCurrency)))
          t,
    ];
  }

  /// Currencies that appear in the customer's balances or deals.
  List<String> get _currencyCodes => {
        for (final b in _balances) b.currency,
        for (final t in _txs) ...[?t.sourceCurrency, ?t.destCurrency],
      }.toList();

  @override
  Future<void> reload() async {
    final s = session.services;
    final customer = await s.customers.byId(widget.customerId);
    if (customer == null) {
      if (mounted) setState(() => _notFound = true);
      return;
    }
    final balances = await s.queries.customerBalances(customer.id);
    // Reversal documents are left out; the deal they cancelled stays, marked as reversed.
    final filter = JournalFilter(
      from: _period == null ? null : BusinessDate.fromDateTime(_period!.from),
      to: _period == null ? null : BusinessDate.fromDateTime(_period!.to),
      customerId: customer.id,
      types: {...TransactionType.values}..remove(TransactionType.reversal),
    );
    final count = await s.queries.journalCount(filter);
    final txs = count == 0 ? const <PostedTransaction>[] : await s.queries.journal(filter, limit: count);
    if (!mounted) return;
    setState(() {
      _customer = customer;
      _balances = balances;
      _txs = txs;
      _loading = false;
    });
  }

  /// What the exchange received from and paid to the customer in [t]; a
  /// buy/sell fills both sides, a receipt or payment only one.
  ({_Money? received, _Money? paid}) _sides(PostedTransaction t) {
    final source = (minor: t.sourceAmountMinor ?? 0, code: t.sourceCurrency);
    final dest = (minor: t.destAmountMinor ?? 0, code: t.destCurrency);
    final owedToCustomer = (t.signedAmountMinor ?? 0) >= 0;
    return switch (t.type) {
      TransactionType.receipt => (received: source, paid: null),
      TransactionType.payment => (received: null, paid: source),
      TransactionType.buy => (received: source, paid: dest),
      TransactionType.sell => (received: dest, paid: source),
      TransactionType.openingCustomer ||
      TransactionType.customerAdjustment =>
        owedToCustomer ? (received: source, paid: null) : (received: null, paid: source),
      _ => (received: null, paid: null),
    };
  }

  List<Widget> _row(PostedTransaction t, AppSession s) {
    final sides = _sides(t);
    final (String, Color)? tag = t.wasEdited
        ? ('نسخه قبل از ویرایش', AppColors.warning)
        : !t.isActive
            ? ('حذف‌شده', AppColors.error)
            : t.replacesTransactionId != null
                ? ('ویرایش‌شده', AppColors.primary)
                : null;
    final description = Text(
      (t.description?.trim().isNotEmpty ?? false) ? t.description!.trim() : '—',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body.copyWith(color: AppColors.textSecondary),
    );
    return [
      Text(DateFormatFa.business(t.effectiveDate), style: AppTypography.body),
      Text(t.referenceNo, style: AppTypography.caption, textDirection: TextDirection.ltr),
      TransactionTypeBadge(t.type),
      _MoneyCell(sides.received, session: s, color: AppColors.success, faded: !t.isActive),
      _MoneyCell(sides.paid, session: s, color: AppColors.error, faded: !t.isActive),
      Text(
        t.isExchange && t.rate != null ? MoneyFormat.rate(t.rate!) : '—',
        textDirection: TextDirection.ltr,
        style: AppTypography.body.copyWith(color: t.isExchange ? AppColors.textPrimary : AppColors.textMuted),
      ),
      const SizedBox.shrink(),
      if (tag case (final label, final color))
        Row(
          children: [
            _StatusTag(label, color),
            const SizedBox(width: 6),
            Expanded(child: description),
          ],
        )
      else
        description,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    if (_notFound) {
      return const PageScaffold(title: 'صورت‌حساب', body: Center(child: Text('مشتری پیدا نشد.')));
    }
    final customer = _customer;
    final canOpening = s.can(Permissions.openingBalancesPost);
    final txs = _visible(s);
    final changedCount = _txs.where((t) => !t.isActive).length;
    final filtered =
        _currencyCode != null || _typeFilter != _TypeFilter.all || _search.text.trim().isNotEmpty;
    return PageScaffold(
      title: customer == null ? 'صورت‌حساب مشتری' : 'صورت‌حساب ${customer.name}',
      subtitle: customer == null
          ? null
          : [customer.code, if (customer.phone != null) customer.phone!].join('  ·  '),
      leading: null,
      actions: [
        // GfFilterChip(
        //   label: 'کل دوره',
        //   icon: Icons.all_inclusive,
        //   selected: _period == null,
        //   onTap: () {
        //     setState(() => _period = null);
        //     reload();
        //   },
        // ),
        GfDateFilter(
          value: _period ?? DateFilterValue.thisMonth(),
          onChanged: (v) {
            setState(() => _period = v);
            reload();
          },
        ),
        if (customer != null && !customer.isWalkIn && canOpening)
          GfSecondaryButton(
            label: 'بیلانس افتتاحیه',
            icon: Icons.flag_outlined,
            onPressed: () => _SignedAmountDialog.show(context, customer: customer, adjustment: false),
          ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: GfSecondaryButton(
            label: 'بازگشت',
            icon: Icons.arrow_back,
            onPressed: () => context.go(AppRoutes.customers),
          ),
        ),
      ],
      body: _loading || customer == null
          ? const GfPageLoader()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final columns = w >= 1100 ? 6 : (w >= 820 ? 4 : (w >= 560 ? 3 : 2));
                  const gap = AppSpacing.sm;
                  final cardWidth = (w - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final b in _balances)
                        if (s.currency(b.currency) case final cur?)
                          SizedBox(
                            width: cardWidth,
                            child: _BalanceCard(
                              currency: cur,
                              positionMinor: b.positionMinor,
                              selected: _currencyCode == cur.code,
                              onTap: () => setState(
                                () => _currencyCode = _currencyCode == cur.code ? null : cur.code,
                              ),
                            ),
                          ),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: LedgerTable(
                    title: _typeFilter == _TypeFilter.changed ? 'معاملات ویرایش‌شده و حذف‌شده' : 'معاملات مشتری',
                    titleCount: txs.length,
                    actions: [
                      // One action keeps the table from stacking the controls under the title.
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GfMenuFilter<_TypeFilter>(
                            value: _typeFilter,
                            width: 160,
                            panelWidth: 300,
                            options: [
                              for (final f in _TypeFilter.values)
                                GfMenuFilterOption(
                                  value: f,
                                  label: f.label,
                                  icon: f.icon,
                                  subtitle: f == _TypeFilter.changed ? '$changedCount مورد — ${f.hint}' : f.hint,
                                ),
                            ],
                            onChanged: (f) => setState(() => _typeFilter = f),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          GfMenuFilter<String?>(
                            value: _currencyCode,
                            width: 150,
                            panelWidth: 240,
                            options: [
                              const GfMenuFilterOption(
                                value: null,
                                label: 'همه ارزها',
                                icon: Icons.public_rounded,
                                subtitle: 'معاملات همه ارزهای مشتری',
                              ),
                              for (final code in _currencyCodes)
                                GfMenuFilterOption(
                                  value: code,
                                  label: s.currency(code)?.nameFa ?? code,
                                  icon: Icons.payments_outlined,
                                  subtitle: code,
                                ),
                            ],
                            onChanged: (code) => setState(() => _currencyCode = code),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          GfSearchField(
                            controller: _search,
                            width: 240,
                            hintText: 'شماره سند، نوع معامله یا شرح',
                            showShortcutHint: false,
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ],
                    minWidth: 1000,
                    itemLabel: 'معامله',
                    emptyText: filtered
                        ? 'معامله‌ای با این جستجو یا فیلتر یافت نشد.'
                        : 'در این دوره معامله‌ای ثبت نشده است.',
                    emptyHint: filtered ? 'ارز، نوع معامله یا عبارت جستجو را تغییر دهید.' : null,
                    // Equal shares, so the columns spread evenly across the whole row.
                    columns: const [
                      LedgerColumn('تاریخ'),
                      LedgerColumn('شماره سند'),
                      LedgerColumn('نوع معامله'),
                      LedgerColumn('دریافت از مشتری', numeric: true),
                      LedgerColumn('پرداخت به مشتری', numeric: true),
                      LedgerColumn('نرخ', numeric: true),
                      // The rate hugs its end edge; this gap keeps it off the description.
                      LedgerColumn('', width: 24),
                      LedgerColumn('شرح'),
                    ],
                    rows: [for (final t in txs) _row(t, s)],
                    onTapRow: (i) => TransactionDetailDialog.show(context, txs[i].id),
                  ),
                ),
              ],
            ),
    );
  }

}

enum _TypeFilter {
  all('همه معاملات', 'همه انواع معامله در این ارز', Icons.list_alt_rounded, null),
  receipt('رسید', 'پول دریافت‌شده از مشتری', Icons.south_west_rounded, {TransactionType.receipt}),
  payment('برد', 'پول پرداخت‌شده به مشتری', Icons.north_east_rounded, {TransactionType.payment}),
  buy('خرید', 'خرید ارز از مشتری', Icons.shopping_cart_outlined, {TransactionType.buy}),
  sell('فروش', 'فروش ارز به مشتری', Icons.sell_outlined, {TransactionType.sell}),
  other('سایر', 'بیلانس افتتاحیه و اصلاح حساب', Icons.more_horiz_rounded, {
    TransactionType.openingCustomer,
    TransactionType.customerAdjustment,
  }),
  changed('ویرایش و حذف‌شده', 'نسخه قبلی معاملات ویرایش‌شده و معاملات حذف‌شده', Icons.history_rounded, null);

  const _TypeFilter(this.label, this.hint, this.icon, this.types);

  final String label;
  final String hint;
  final IconData icon;
  final Set<TransactionType>? types;
}

typedef _Money = ({int minor, String? code});

/// Small pill marking an edited, earlier-version, or deleted deal.
class _StatusTag extends StatelessWidget {
  const _StatusTag(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Amount with its currency name in the side's colour, or a muted dash.
class _MoneyCell extends StatelessWidget {
  const _MoneyCell(this.money, {required this.session, required this.color, this.faded = false});

  final _Money? money;
  final AppSession session;
  final Color color;

  /// Deleted or edited deals stay listed but no longer count.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final m = money;
    if (m == null) return Text('—', style: AppTypography.body.copyWith(color: AppColors.textMuted));
    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: Text(
        MoneyFormat.withName(m.minor, session.currency(m.code), fallbackCode: m.code),
        textDirection: TextDirection.ltr,
        style: AppTypography.bodySemiBold.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Smaller take on the dashboard currency card: the customer's overall
/// position in one currency. Tapping it shows that currency's statement.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.currency,
    required this.positionMinor,
    required this.selected,
    required this.onTap,
  });

  final Currency currency;
  final int positionMinor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (String status, Color tone) = positionMinor > 0
        ? ('طلب مشتری', AppColors.success)
        : positionMinor < 0
            ? ('بدهی مشتری', AppColors.error)
            : ('تسویه', AppColors.textMuted);
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${currency.nameFa} (${currency.code})',
                      style: AppTypography.label.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: AppRadius.input,
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          AppAssets.currenciesFilled,
                          width: 14,
                          height: 14,
                          colorFilter: ColorFilter.mode(AppColors.primary, BlendMode.srcIn),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      MoneyFormat.amount(positionMinor.abs(), currency),
                      style: AppTypography.kpiValue.copyWith(fontSize: 15, color: tone),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.10),
                      borderRadius: AppRadius.pill,
                      border: Border.all(color: tone.withValues(alpha: 0.22)),
                    ),
                    child: Text(
                      status,
                      style: AppTypography.caption.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: tone),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Customer opening balance (posted once per currency) or an authorized
/// adjustment (reason required). Both are normal journal postings.
class _SignedAmountDialog extends StatefulWidget {
  const _SignedAmountDialog({required this.customer, required this.adjustment});

  final CustomerRecord customer;
  final bool adjustment;

  static Future<void> show(BuildContext context, {required CustomerRecord customer, required bool adjustment}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: _SignedAmountDialog(customer: customer, adjustment: adjustment),
      ),
    );
  }

  @override
  State<_SignedAmountDialog> createState() => _SignedAmountDialogState();
}

class _SignedAmountDialogState extends State<_SignedAmountDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  Currency? _currency;
  int? _drawerId;
  bool _owedToCustomer = true;
  BusinessDate _date = BusinessDate.today();
  bool _saving = false;
  final String _key = PostingService.newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    final drawers = context.read<AppSession>().activeDrawers;
    final selected = context.read<AppSettingsProvider>().selectedDrawerId;
    _drawerId = drawers.any((d) => d.id == selected) ? selected : drawers.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final currency = _currency;
    if (currency == null) {
      GfToast.error(context, 'ارز را انتخاب کنید.');
      return;
    }
    final minor = MoneyFormat.tryParse(_amount.text, currency);
    if (minor == null || minor <= 0) {
      GfToast.error(context, 'مبلغ معتبر نیست.');
      return;
    }
    if (!widget.adjustment && _owedToCustomer && _drawerId == null) {
      GfToast.error(context, 'صندوق را انتخاب کنید.');
      return;
    }
    final signed = _owedToCustomer ? minor : -minor;
    final FinancialCommand cmd = widget.adjustment
        ? CustomerAdjustmentCommand(
            idempotencyKey: _key,
            effectiveDate: _date,
            customerId: widget.customer.id,
            currency: currency.code,
            signedMinor: signed,
            reason: _reason.text.trim(),
          )
        : OpeningCustomerCommand(
            idempotencyKey: _key,
            effectiveDate: _date,
            description: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
            customerId: widget.customer.id,
            currency: currency.code,
            signedMinor: signed,
            drawerId: _owedToCustomer ? _drawerId : null,
          );
    setState(() => _saving = true);
    final s = context.read<AppSession>();
    final posted = await runAction(
      context,
      () => s.services.posting.post(cmd, s.actor),
      success: widget.adjustment ? 'اصلاح حساب ثبت شد.' : 'بیلانس افتتاحیه ثبت شد.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (posted != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final needsDrawer = !widget.adjustment && _owedToCustomer;
    return GfDialogShell(
      icon: widget.adjustment ? Icons.tune : Icons.flag_outlined,
      iconColor: AppColors.primary,
      title: widget.adjustment ? 'اصلاح حساب مشتری' : 'بیلانس افتتاحیه مشتری',
      subtitle: '${widget.customer.name}  ·  ${widget.customer.code}',
      cancelLabel: 'انصراف',
      onCancel: () => Navigator.of(context).pop(),
      primaryLabel: 'ثبت',
      primaryIcon: Icons.save_outlined,
      onPrimary: _save,
      saving: _saving,
      maxWidth: 580,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogResponsiveRow(
            children: [
              CurrencyPicker(value: _currency, onChanged: (c) => setState(() => _currency = c)),
              BusinessDateField(value: _date, onChanged: (d) => setState(() => _date = d)),
            ],
          ),
          if (needsDrawer) ...[
            const SizedBox(height: 14),
            DrawerPicker(
              value: _drawerId,
              onChanged: (id) {
                setState(() => _drawerId = id);
                context.read<AppSettingsProvider>().setSelectedDrawerId(id);
              },
            ),
          ],
          const SizedBox(height: 14),
          Text('جهت مانده', style: AppTypography.label),
          const SizedBox(height: 6),
          GfChoiceChips<bool>(
            expand: true,
            value: _owedToCustomer,
            onChanged: (v) => setState(() => _owedToCustomer = v),
            options: const [
              GfChoiceOption(true, 'طلب مشتری (صرافی بدهکار)', icon: Icons.south_west),
              GfChoiceOption(false, 'بدهی مشتری', icon: Icons.north_east),
            ],
          ),
          const SizedBox(height: 14),
          AmountField(controller: _amount, label: 'مبلغ'),
          const SizedBox(height: 14),
          GfTextField(
            label: widget.adjustment ? 'دلیل اصلاح' : 'شرح (اختیاری)',
            required: widget.adjustment,
            controller: _reason,
            minLines: 2,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          DialogInfoBanner(
            message: widget.adjustment
                ? 'اصلاح با سند حسابداری مجزا و دلیل ثبت می‌شود و در سوابق ممیزی باقی می‌ماند.'
                : needsDrawer
                    ? 'طلب مشتری به معنی وجه موجود نزد صرافی است؛ مبلغ همزمان به حساب مشتری و موجودی صندوق اضافه می‌شود. برای هر ارز فقط یک بار ثبت می‌شود (مگر پس از برگشت).'
                    : 'بیلانس افتتاحیه برای هر ارز فقط یک بار ثبت می‌شود (مگر پس از برگشت).',
          ),
        ],
      ),
    );
  }
}
