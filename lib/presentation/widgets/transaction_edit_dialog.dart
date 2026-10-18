import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/posting_service.dart';
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
import 'exchange_ui.dart';

enum _Family { cash, exchange, openingCash, openingCustomer }

/// Edits a posted transaction. Saving calls [PostingService.correct]: the
/// original is reversed on its own date and the corrected version posted in
/// one database transaction, so balances are never left half-changed.
/// Returns the corrected transaction, or null when cancelled.
class TransactionEditDialog extends StatefulWidget {
  const TransactionEditDialog({super.key, required this.original});

  final PostedTransaction original;

  static Future<PostedTransaction?> show(BuildContext context, PostedTransaction original) {
    return showDialog<PostedTransaction>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: TransactionEditDialog(original: original),
      ),
    );
  }

  @override
  State<TransactionEditDialog> createState() => _TransactionEditDialogState();
}

class _TransactionEditDialogState extends State<TransactionEditDialog> {
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _fee = TextEditingController();
  final _description = TextEditingController();
  final _reason = TextEditingController();
  final String _key = PostingService.newIdempotencyKey();

  late final _Family _family;
  late TransactionType _type;
  late BusinessDate _date;
  int? _customerId;
  CustomerRecord? _customer;
  Currency? _currency;
  Currency? _quote;

  /// Opening customer balance: true = the exchange owes the customer (طلب).
  bool _owesCustomer = true;
  int? _drawerId;
  late final String _initial;
  bool _saving = false;

  PostedTransaction get _o => widget.original;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppSession>();
    _family = switch (_o.type) {
      TransactionType.buy || TransactionType.sell => _Family.exchange,
      TransactionType.openingCash => _Family.openingCash,
      TransactionType.openingCustomer => _Family.openingCustomer,
      _ => _Family.cash,
    };
    _type = _o.type;
    _date = _o.effectiveDate;
    _customerId = _o.customerId;
    _currency = s.currency(_o.sourceCurrency);
    _quote = s.currency(_o.destCurrency);
    final amount = (_o.signedAmountMinor ?? _o.sourceAmountMinor ?? 0).abs();
    if (_currency != null) _amount.text = MoneyFormat.editable(amount, _currency!);
    _owesCustomer = (_o.signedAmountMinor ?? 1) > 0;
    final drawers = s.activeDrawers;
    final pref = context.read<AppSettingsProvider>().selectedDrawerId;
    _drawerId = _o.drawerId ??
        (drawers.any((d) => d.id == pref) ? pref : drawers.firstOrNull?.id);
    _rate.text = _o.rate == null ? '' : MoneyFormat.rate(_o.rate!).replaceAll(',', '');
    final feeCur = s.currency(_o.feeCurrency);
    if (_o.feeAmountMinor != null && feeCur != null) {
      _fee.text = MoneyFormat.editable(_o.feeAmountMinor!, feeCur);
    }
    _description.text = _o.description ?? '';
    _initial = _signature();
    _loadCustomer();
  }

  Future<void> _loadCustomer() async {
    final id = _customerId;
    if (id == null) return;
    final c = await context.read<AppSession>().services.customers.byId(id);
    if (mounted) setState(() => _customer = c);
  }

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _fee.dispose();
    _description.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _needsCustomer =>
      _family == _Family.exchange || (_family == _Family.cash && _type != TransactionType.expense);

  String _signature() => [
        _type.name,
        _date.iso,
        _customerId,
        _drawerId,
        _currency?.code,
        _quote?.code,
        _currency == null ? _amount.text : MoneyFormat.tryParse(_amount.text, _currency!),
        Decimal.tryParse(_rate.text.replaceAll(',', ''))?.toCanonical() ?? _rate.text,
        _fee.text.replaceAll(',', '').trim(),
        _description.text.trim(),
        _owesCustomer,
      ].join('|');

  ({int? quoteMinor, String? error}) _exchangePreview() {
    final base = _currency, quote = _quote;
    if (base == null || quote == null) return (quoteMinor: null, error: null);
    if (base == quote) return (quoteMinor: null, error: 'ارز مبدأ و مقابل نباید یکی باشند.');
    if (_amount.text.trim().isEmpty || _rate.text.trim().isEmpty) return (quoteMinor: null, error: null);
    try {
      final baseMinor = MoneyFormat.parse(_amount.text, base);
      final rate = Decimal.parse(_rate.text.replaceAll(',', ''));
      return (quoteMinor: ExchangeRate.of(base, quote, rate).convert(baseMinor), error: null);
    } on DomainError catch (e) {
      return (quoteMinor: null, error: e.message);
    }
  }

  /// Builds the corrected command, or reports what is missing and returns null.
  FinancialCommand? _command() {
    final c = _currency;
    void fail(String message) => GfToast.error(context, message);
    if (c == null) {
      fail('ارز را انتخاب کنید.');
      return null;
    }
    final minor = MoneyFormat.tryParse(_amount.text, c);
    if (minor == null || minor <= 0) {
      fail('مبلغ معتبر نیست (حداکثر ${c.precision} رقم اعشار برای ${c.nameFa}).');
      return null;
    }
    if (_needsCustomer && _customerId == null) {
      fail('مشتری را انتخاب کنید.');
      return null;
    }
    final drawerId = _drawerId ?? _o.drawerId ?? 1;
    final description = _description.text.trim().isEmpty ? null : _description.text.trim();
    switch (_family) {
      case _Family.cash:
        if (_type == TransactionType.expense && description == null) {
          fail('شرح مصرف الزامی است.');
          return null;
        }
        return switch (_type) {
          TransactionType.receipt => ReceiptCommand(
              idempotencyKey: _key,
              effectiveDate: _date,
              description: description,
              customerId: _customerId!,
              drawerId: drawerId,
              currency: c.code,
              amountMinor: minor),
          TransactionType.payment => PaymentCommand(
              idempotencyKey: _key,
              effectiveDate: _date,
              description: description,
              customerId: _customerId!,
              drawerId: drawerId,
              currency: c.code,
              amountMinor: minor),
          _ => ExpenseCommand(
              idempotencyKey: _key,
              effectiveDate: _date,
              description: description!,
              drawerId: drawerId,
              currency: c.code,
              amountMinor: minor),
        };
      case _Family.exchange:
        final quote = _quote;
        final preview = _exchangePreview();
        final rate = Decimal.tryParse(_rate.text.replaceAll(',', ''));
        if (quote == null || rate == null || preview.error != null || preview.quoteMinor == null) {
          fail(preview.error ?? 'ارز مقابل و نرخ را درست وارد کنید.');
          return null;
        }
        ExchangeFee? fee;
        final feeCur = context.read<AppSession>().currency(_o.feeCurrency);
        if (feeCur != null && _fee.text.trim().isNotEmpty) {
          final feeMinor = MoneyFormat.tryParse(_fee.text, feeCur);
          if (feeMinor == null || feeMinor < 0) {
            fail('مبلغ کمیشن معتبر نیست.');
            return null;
          }
          if (feeMinor > 0) {
            fee = ExchangeFee(
              currency: feeCur.code,
              amountMinor: feeMinor,
              settlement: Settlement.parse(_o.feeSettlement ?? 'cash'),
            );
          }
        }
        return ExchangeCommand(
          idempotencyKey: _key,
          effectiveDate: _date,
          description: description,
          direction: _type == TransactionType.buy ? ExchangeDirection.buy : ExchangeDirection.sell,
          customerId: _customerId!,
          drawerId: drawerId,
          baseCurrency: c.code,
          quoteCurrency: quote.code,
          baseAmountMinor: minor,
          rate: rate,
          baseSettlement: Settlement.parse(_o.sourceSettlement ?? 'cash'),
          quoteSettlement: Settlement.parse(_o.destSettlement ?? 'cash'),
          fee: fee,
        );
      case _Family.openingCash:
        return OpeningCashCommand(
            idempotencyKey: _key,
            effectiveDate: _date,
            description: description,
            drawerId: drawerId,
            currency: c.code,
            amountMinor: minor);
      case _Family.openingCustomer:
        return OpeningCustomerCommand(
            idempotencyKey: _key,
            effectiveDate: _date,
            description: description,
            customerId: _customerId!,
            currency: c.code,
            signedMinor: _owesCustomer ? minor : -minor,
            drawerId: _owesCustomer ? drawerId : null);
    }
  }

  Future<void> _save() async {
    if (_signature() == _initial) {
      GfToast.info(context, 'تغییری ایجاد نشده است.');
      return;
    }
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      GfToast.error(context, 'دلیل ویرایش را بنویسید (برای سوابق ممیزی الزامی است).');
      return;
    }
    final cmd = _command();
    if (cmd == null) return;
    setState(() => _saving = true);
    final s = context.read<AppSession>();
    final result = await runAction(
      context,
      () => s.services.posting.correct(
        transactionId: _o.id,
        replacement: cmd,
        reason: reason,
        actor: s.actor,
      ),
      success: 'معامله ${_o.referenceNo} ویرایش شد.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) Navigator.of(context).pop(result);
  }

  // ------------------------------------------------------------------ view

  Widget _kindChips() {
    final options = switch (_family) {
      _Family.cash when _type != TransactionType.expense => const [
          GfChoiceOption(TransactionType.receipt, 'رسید (دریافت نقد)', icon: Icons.south_west_rounded),
          GfChoiceOption(TransactionType.payment, 'برد (پرداخت نقد)', icon: Icons.north_east_rounded),
        ],
      _Family.exchange => const [
          GfChoiceOption(TransactionType.buy, 'خرید ارز', icon: Icons.south_west_rounded),
          GfChoiceOption(TransactionType.sell, 'فروش ارز', icon: Icons.north_east_rounded),
        ],
      _ => const <GfChoiceOption<TransactionType>>[],
    };
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GfChoiceChips<TransactionType>(
        options: options,
        value: _type,
        expand: true,
        onChanged: (t) => setState(() => _type = t),
      ),
    );
  }

  Widget _customerField() {
    if (_family == _Family.openingCustomer) {
      return _ReadOnlyField(label: 'مشتری', value: _customer?.name ?? _o.customerName ?? '—');
    }
    return CustomerPickerField(
      selected: _customer,
      allowWalkIn: _family == _Family.exchange,
      onSelected: (c) => setState(() {
        _customer = c;
        _customerId = c.id;
      }),
    );
  }

  Widget _exchangeFields(AppSession s) {
    final preview = _exchangePreview();
    final feeCur = s.currency(_o.feeCurrency);
    final buy = _type == TransactionType.buy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DialogResponsiveRow(children: [
          CurrencyPicker(
            label: buy ? 'ارزی که خریده شد' : 'ارزی که فروخته شد',
            value: _currency,
            onChanged: (c) => setState(() => _currency = c),
          ),
          CurrencyPicker(label: 'ارز مقابل', value: _quote, onChanged: (c) => setState(() => _quote = c)),
        ]),
        const SizedBox(height: 12),
        DialogResponsiveRow(children: [
          AmountField(
            controller: _amount,
            label: 'مبلغ ${_currency?.nameFa ?? ''}',
            onChanged: (_) => setState(() {}),
          ),
          GfTextField(
            label: 'نرخ',
            hint: '۱ ${_currency?.nameFa ?? ''} = ? ${_quote?.nameFa ?? ''}',
            controller: _rate,
            required: true,
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [ThousandsSeparatorInputFormatter()],
            onChanged: (_) => setState(() {}),
          ),
        ]),
        const SizedBox(height: 12),
        if (preview.error != null)
          InfoBanner(preview.error!, tone: BannerTone.error)
        else
          _ReadOnlyField(
            label: 'مبلغ ${_quote?.nameFa ?? 'مقابل'} (محاسبه خودکار)',
            value: preview.quoteMinor == null ? '—' : MoneyFormat.withName(preview.quoteMinor!, _quote),
          ),
        if (feeCur != null) ...[
          const SizedBox(height: 12),
          AmountField(
            controller: _fee,
            label: 'کمیشن ${feeCur.nameFa} (خالی = بدون کمیشن)',
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (_o.sourceSettlement == 'customer' || _o.destSettlement == 'customer') ...[
          const SizedBox(height: 12),
          const InfoBanner('این معامله (بخشی) از طریق حساب مشتری تسویه شده است؛ همان روش تسویه حفظ می‌شود.'),
        ],
      ],
    );
  }

  Widget _singleCurrencyFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DialogResponsiveRow(children: [
          CurrencyPicker(value: _currency, onChanged: (c) => setState(() => _currency = c)),
          AmountField(
            controller: _amount,
            label: 'مبلغ ${_currency?.nameFa ?? ''}',
            onChanged: (_) => setState(() {}),
          ),
        ]),
        if (_family == _Family.openingCustomer) ...[
          const SizedBox(height: 12),
          GfChoiceChips<bool>(
            options: const [
              GfChoiceOption(true, 'طلب مشتری (صرافی بدهکار است)'),
              GfChoiceOption(false, 'بدهی مشتری (مشتری بدهکار است)'),
            ],
            value: _owesCustomer,
            expand: true,
            onChanged: (v) => setState(() => _owesCustomer = v),
          ),
          if (_owesCustomer) ...[
            const SizedBox(height: 12),
            DrawerPicker(
              value: _drawerId,
              onChanged: (id) => setState(() => _drawerId = id),
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final changed = _signature() != _initial;
    return GfDialogShell(
      icon: Icons.edit_note_outlined,
      iconColor: AppColors.primary,
      title: 'ویرایش ${_o.type.labelFa} — ${_o.referenceNo}',
      subtitle: 'ثبت اصلی: ${DateFormatFa.business(_o.effectiveDate)}',
      cancelLabel: 'انصراف',
      onCancel: () => Navigator.of(context).pop(),
      primaryLabel: 'ذخیره ویرایش',
      primaryIcon: Icons.save_outlined,
      onPrimary: _save,
      saving: _saving,
      maxWidth: 600,
      maxHeight: 820,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const InfoBanner(
            'با ذخیره، اثر سند قبلی در همان تاریخ خنثی و نسخه اصلاح‌شده ثبت می‌شود (هر دو با هم یا هیچ‌کدام). '
            'موجودی صندوق، حساب مشتری و بیلانس روزها خودکار دوباره محاسبه می‌شوند و سابقه برای ممیزی حفظ می‌شود.',
          ),
          const SizedBox(height: 14),
          _kindChips(),
          if (_needsCustomer || _family == _Family.openingCustomer)
            DialogResponsiveRow(children: [
              _customerField(),
              BusinessDateField(value: _date, onChanged: (d) => setState(() => _date = d)),
            ])
          else
            BusinessDateField(value: _date, onChanged: (d) => setState(() => _date = d)),
          const SizedBox(height: 12),
          if (_family == _Family.exchange) _exchangeFields(s) else _singleCurrencyFields(),
          const SizedBox(height: 12),
          GfTextField(
            label: _type == TransactionType.expense ? 'شرح مصرف' : 'شرح (اختیاری)',
            required: _type == TransactionType.expense,
            controller: _description,
            onChanged: (_) => setState(() {}),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          GfTextField(
            label: 'دلیل ویرایش',
            hint: 'مثلاً مبلغ اشتباه وارد شده بود',
            required: true,
            controller: _reason,
            minLines: 1,
            maxLines: 2,
          ),
          if (!changed) ...[
            const SizedBox(height: 10),
            Text(
              'هنوز تغییری ایجاد نشده است.',
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Non-editable value styled like a field.
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

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
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: AppRadius.input,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySemiBold.copyWith(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}
