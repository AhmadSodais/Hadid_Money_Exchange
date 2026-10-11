import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../application/posting_service.dart';
import '../../application/read_models.dart';
import '../../core/constants/app_assets.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/security/permissions.dart';
import '../../domain/shared/business_date.dart';
import '../../domain/transactions/financial_command.dart';
import '../../infrastructure/export/excel_export.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/export_action.dart';
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
  Currency? _currency;

  /// `null` = the whole history.
  DateFilterValue? _period;
  CustomerStatement? _statement;
  bool _loading = true;
  bool _notFound = false;

  @override
  Future<void> reload() async {
    final s = session.services;
    final customer = await s.customers.byId(widget.customerId);
    if (customer == null) {
      if (mounted) setState(() => _notFound = true);
      return;
    }
    final balances = await s.queries.customerBalances(customer.id);
    var currency = _currency;
    if (currency == null) {
      final codes = balances.map((b) => b.currency).toList();
      currency = codes.isNotEmpty
          ? session.currency(codes.first)
          : (session.activeCurrencies.isEmpty ? null : session.activeCurrencies.first);
    }
    final statement = currency == null
        ? null
        : await s.queries.customerStatement(
            customer,
            currency.code,
            from: _period == null ? null : BusinessDate.fromDateTime(_period!.from),
            to: _period == null ? null : BusinessDate.fromDateTime(_period!.to),
          );
    if (!mounted) return;
    setState(() {
      _customer = customer;
      _balances = balances;
      _currency = currency;
      _statement = statement;
      _loading = false;
    });
  }

  void _export() {
    final st = _statement, c = _currency, customer = _customer;
    if (st == null || c == null || customer == null) return;
    exportSheets(context, 'statement_${customer.code}_${c.code}', [
      ExportSheet(
        name: 'صورت‌حساب',
        notes: [
          'صورت‌حساب ${customer.name} (${customer.code}) — ${c.nameFa}',
          'مثبت = طلب مشتری، منفی = بدهی مشتری',
          'مانده ابتدای دوره: ${MoneyFormat.amount(st.openingPositionMinor, c)}',
        ],
        headers: const ['تاریخ', 'شماره سند', 'نوع', 'شرح', 'بدهکار', 'بستانکار', 'مانده', 'وضعیت'],
        rows: [
          for (final l in st.lines)
            [
              DateFormatFa.business(l.effectiveDate),
              l.referenceNo,
              l.type.labelFa,
              l.description ?? '',
              MoneyFormat.amount(l.debitMinor, c),
              MoneyFormat.amount(l.creditMinor, c),
              MoneyFormat.amount(l.runningPositionMinor, c),
              l.status == TransactionStatus.reversed ? 'برگشت‌شده' : 'ثبت‌شده',
            ],
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    if (_notFound) {
      return const PageScaffold(title: 'صورت‌حساب', body: Center(child: Text('مشتری پیدا نشد.')));
    }
    final customer = _customer;
    final st = _statement;
    final c = _currency;
    final currencies = s.currencies.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return PageScaffold(
      title: customer == null ? 'صورت‌حساب مشتری' : 'صورت‌حساب ${customer.name}',
      subtitle: customer == null
          ? null
          : [customer.code, if (customer.phone != null) customer.phone!].join('  ·  '),
      leading: null,
      actions: [
        GfSecondaryButton(
          label: 'بازگشت',
          icon: Icons.arrow_forward,
          onPressed: () => context.go(AppRoutes.customers),
        ),
        if (customer != null && !customer.isWalkIn && s.can(Permissions.openingBalancesPost))
          GfSecondaryButton(
            label: 'بیلانس افتتاحیه',
            icon: Icons.flag_outlined,
            onPressed: () => _SignedAmountDialog.show(context, customer: customer, adjustment: false),
          ),
        if (customer != null && !customer.isWalkIn && s.can(Permissions.adjustmentsPost))
          GfSecondaryButton(
            label: 'اصلاح حساب',
            icon: Icons.tune,
            onPressed: () => _SignedAmountDialog.show(context, customer: customer, adjustment: true),
          ),
        GfFilterChip(
          label: 'کل دوره',
          icon: Icons.all_inclusive,
          selected: _period == null,
          onTap: () {
            setState(() => _period = null);
            reload();
          },
        ),
        GfDateFilter(
          value: _period ?? DateFilterValue.thisMonth(),
          onChanged: (v) {
            setState(() => _period = v);
            reload();
          },
        ),
        ExportButton(onPressed: st == null ? null : _export),
      ],
      body: _loading || customer == null
          ? const GfPageLoader()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GfCountBox(
                      label: 'ردیف‌های صورت‌حساب',
                      count: st?.lines.length ?? 0,
                      icon: AppAssets.invoiceFilled,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final cur in currencies) ...[
                              if (cur != currencies.first) const SizedBox(width: 8),
                              GfFilterChip(
                                label: _chipLabel(cur),
                                selected: c?.code == cur.code,
                                onTap: () {
                                  setState(() => _currency = cur);
                                  reload();
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
                    title: c == null ? 'صورت‌حساب' : 'صورت‌حساب ${c.nameFa}',
                    subtitle: st == null || c == null
                        ? null
                        : 'مانده ابتدای دوره: ${MoneyFormat.position(st.openingPositionMinor, c)}   —   '
                            'مانده پایان دوره: ${MoneyFormat.position(st.closingPositionMinor, c)}',
                    minWidth: 1000,
                    itemLabel: 'ردیف',
                    emptyText: 'در این دوره معامله‌ای ثبت نشده است.',
                    emptyHint: _balances.isEmpty ? 'حساب این مشتری در همه ارزها تسویه است.' : null,
                    columns: const [
                      LedgerColumn('تاریخ', width: 110),
                      LedgerColumn('شماره سند', width: 130),
                      LedgerColumn('نوع', flex: 2),
                      LedgerColumn('شرح', flex: 3),
                      LedgerColumn('بدهکار', flex: 2, numeric: true),
                      LedgerColumn('بستانکار', flex: 2, numeric: true),
                      LedgerColumn('مانده', flex: 2, numeric: true),
                    ],
                    rows: [
                      if (st != null && c != null)
                        for (final l in st.lines)
                          [
                            Text(DateFormatFa.business(l.effectiveDate), style: AppTypography.body),
                            Text(l.referenceNo, style: AppTypography.caption, textDirection: TextDirection.ltr),
                            Text(
                              l.type.labelFa + (l.status == TransactionStatus.reversed ? ' (برگشت‌شده)' : ''),
                              style: AppTypography.body.copyWith(
                                color: l.status == TransactionStatus.reversed ? AppColors.warning : null,
                              ),
                            ),
                            Text(l.description ?? '', style: AppTypography.body),
                            l.debitMinor == 0 ? const Text('') : AmountText(l.debitMinor, c),
                            l.creditMinor == 0 ? const Text('') : AmountText(l.creditMinor, c),
                            AmountText(l.runningPositionMinor, c, signColor: true, bold: true),
                          ],
                    ],
                    onTapRow: (i) => TransactionDetailDialog.show(context, st!.lines[i].transactionId),
                  ),
                ),
              ],
            ),
    );
  }

  String _chipLabel(Currency cur) {
    for (final b in _balances) {
      if (b.currency == cur.code) return '${cur.nameFa}: ${MoneyFormat.position(b.positionMinor, cur)}';
    }
    return cur.nameFa;
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
  bool _owedToCustomer = true;
  BusinessDate _date = BusinessDate.today();
  bool _saving = false;
  final String _key = PostingService.newIdempotencyKey();

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
      maxWidth: 460,
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
                : 'بیلانس افتتاحیه برای هر ارز فقط یک بار ثبت می‌شود (مگر پس از برگشت).',
          ),
        ],
      ),
    );
  }
}
