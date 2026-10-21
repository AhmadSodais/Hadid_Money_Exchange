import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/posting_service.dart';
import '../../application/read_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/shared/business_date.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/settings_kit.dart';
import '../widgets/transaction_detail_dialog.dart';
import '../widgets/workbench_kit.dart';

enum _CashKind { receipt, payment, expense }

/// رسید (cash received from a customer), برد (cash paid to a customer), and
/// operating expenses paid from a drawer.
class CashTransactionPage extends StatefulWidget {
  const CashTransactionPage({super.key});

  @override
  State<CashTransactionPage> createState() => _CashTransactionPageState();
}

class _CashTransactionPageState extends State<CashTransactionPage> with RevisionReload {
  final _amount = TextEditingController();
  final _description = TextEditingController();

  _CashKind _kind = _CashKind.receipt;
  CustomerRecord? _customer;
  int? _drawerId;
  Currency? _currency;
  BusinessDate _date = BusinessDate.today();
  bool _saving = false;
  String _key = PostingService.newIdempotencyKey();
  PostedTransaction? _last;

  List<CustomerBalance> _balances = const [];
  Map<String, int> _cash = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<AppSession>();
      final settings = context.read<AppSettingsProvider>();
      final drawers = s.activeDrawers;
      setState(() {
        _drawerId = drawers.any((d) => d.id == settings.selectedDrawerId)
            ? settings.selectedDrawerId
            : (drawers.isEmpty ? null : drawers.first.id);
        final currencies = s.activeCurrencies;
        _currency = currencies.isEmpty ? null : currencies.first;
      });
      reload();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final s = session.services;
    final customer = _customer;
    final balances =
        customer == null ? const <CustomerBalance>[] : await s.queries.customerBalances(customer.id);
    final cash = _drawerId == null
        ? const <String, int>{}
        : await s.queries.cashBalances(drawerId: _drawerId);
    if (!mounted) return;
    setState(() {
      _balances = balances;
      _cash = cash;
    });
  }

  String get _title => switch (_kind) {
        _CashKind.receipt => 'رسید',
        _CashKind.payment => 'برد',
        _CashKind.expense => 'مصرف',
      };

  bool get _needsCustomer => _kind != _CashKind.expense;

  int? get _minor {
    final c = _currency;
    if (c == null) return null;
    final minor = MoneyFormat.tryParse(_amount.text, c);
    return minor == null || minor <= 0 ? null : minor;
  }

  Future<void> _submit() async {
    final currency = _currency, drawer = _drawerId;
    if (currency == null || drawer == null) {
      GfToast.error(context, 'صندوق اصلی و ارز را انتخاب کنید.');
      return;
    }
    final minor = MoneyFormat.tryParse(_amount.text, currency);
    if (minor == null || minor <= 0) {
      GfToast.error(context,
          'مبلغ معتبر نیست (حداکثر ${currency.precision} رقم اعشار برای ${currency.nameFa}).');
      return;
    }
    final description = _description.text.trim();
    if (_needsCustomer && _customer == null) {
      GfToast.error(context, 'مشتری را انتخاب کنید.');
      return;
    }
    if (_kind == _CashKind.expense && description.isEmpty) {
      GfToast.error(context, 'شرح مصرف الزامی است.');
      return;
    }

    final what = switch (_kind) {
      _CashKind.receipt => 'دریافت ${MoneyFormat.withName(minor, currency)} نقد از ${_customer!.name}',
      _CashKind.payment => 'پرداخت ${MoneyFormat.withName(minor, currency)} نقد به ${_customer!.name}',
      _CashKind.expense => 'پرداخت مصرف ${MoneyFormat.withName(minor, currency)} — $description',
    };
    final ok = await GfConfirmDialog.show(
      context,
      title: 'تأیید $_title',
      message: '$what\nتاریخ: ${DateFormatFa.business(_date)}\n'
          'پس از ثبت، از روزنامچه قابل ویرایش یا حذف است.',
      confirmLabel: 'ثبت نهایی',
      cancelLabel: 'انصراف',
    );
    if (!ok || !mounted) return;

    final FinancialCommand cmd = switch (_kind) {
      _CashKind.receipt => ReceiptCommand(
          idempotencyKey: _key,
          effectiveDate: _date,
          description: description.isEmpty ? null : description,
          customerId: _customer!.id,
          drawerId: drawer,
          currency: currency.code,
          amountMinor: minor,
        ),
      _CashKind.payment => PaymentCommand(
          idempotencyKey: _key,
          effectiveDate: _date,
          description: description.isEmpty ? null : description,
          customerId: _customer!.id,
          drawerId: drawer,
          currency: currency.code,
          amountMinor: minor,
        ),
      _CashKind.expense => ExpenseCommand(
          idempotencyKey: _key,
          effectiveDate: _date,
          description: description,
          drawerId: drawer,
          currency: currency.code,
          amountMinor: minor,
        ),
    };

    setState(() => _saving = true);
    final s = context.read<AppSession>();
    final posted = await runAction(context, () => s.services.posting.post(cmd, s.actor));
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (posted != null) {
        _last = posted;
        _key = PostingService.newIdempotencyKey();
        _amount.clear();
        _description.clear();
      }
    });
    if (posted != null) {
      GfToast.success(context, '$_title ثبت شد — شماره سند ${posted.referenceNo}');
    }
  }

  // ------------------------------------------------------------------ form

  Widget _partySection(SettingsMetrics m, AppSession s) {
    final drawer = DrawerPicker(
      value: _drawerId,
      onChanged: (id) {
        setState(() => _drawerId = id);
        context.read<AppSettingsProvider>().setSelectedDrawerId(id);
        reload();
      },
    );
    final date = BusinessDateField(value: _date, onChanged: (d) => setState(() => _date = d));
    return WorkbenchSection(
      step: 1,
      title: _needsCustomer ? 'مشتری و صندوق اصلی' : 'صندوق اصلی و تاریخ',
      subtitle: switch (_kind) {
        _CashKind.receipt => 'نقد از کدام مشتری دریافت و به صندوق اصلی مشترک اضافه می‌شود؟',
        _CashKind.payment => 'نقد به کدام مشتری از صندوق اصلی مشترک پرداخت می‌شود؟ (حداکثر تا موجودی کل صندوق)',
        _CashKind.expense => 'مصرف از صندوق اصلی مشترک پرداخت می‌شود؟ (حداکثر تا موجودی کل صندوق)',
      },
      padding: m.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkbenchPartyFields(
            gap: m.fieldGap,
            customer: _needsCustomer
                ? CustomerPickerField(
                    selected: _customer,
                    onSelected: (c) {
                      setState(() => _customer = c);
                      reload();
                    },
                  )
                : null,
            drawer: drawer,
            date: date,
          ),
          if (_needsCustomer && _customer != null) ...[
            SizedBox(height: m.fieldGap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('مانده فعلی حساب:', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                if (_balances.isEmpty)
                  GfStatusBadge(label: 'تسویه', color: AppColors.textMuted, compact: true)
                else
                  for (final b in _balances)
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

  Widget _amountSection(SettingsMetrics m) {
    final currency = _currency;
    return WorkbenchSection(
      step: 2,
      title: 'مبلغ و شرح',
      subtitle: _kind == _CashKind.expense ? 'برای مصرف، نوشتن شرح الزامی است.' : 'شرح برای رسید و برد اختیاری است.',
      padding: m.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsFormRow(
            gap: m.fieldGap,
            left: CurrencyPicker(value: currency, onChanged: (c) => setState(() => _currency = c)),
            right: AmountField(
              controller: _amount,
              label: 'مبلغ ${currency?.nameFa ?? ''}',
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(height: m.fieldGap),
          GfTextField(
            label: _kind == _CashKind.expense ? 'شرح مصرف' : 'شرح (اختیاری)',
            hint: _kind == _CashKind.expense ? 'مثلاً کرایه دفتر، برق، معاش…' : null,
            required: _kind == _CashKind.expense,
            controller: _description,
            onChanged: (_) => setState(() {}),
            minLines: 2,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- summary

  Widget _summary(AppSession s) {
    final currency = _currency;
    final minor = _minor;
    final incoming = _kind == _CashKind.receipt;
    final ready = currency != null &&
        _drawerId != null &&
        minor != null &&
        (!_needsCustomer || _customer != null) &&
        (_kind != _CashKind.expense || _description.text.trim().isNotEmpty);

    final children = <Widget>[];
    final placeholder = currency == null || minor == null || (_needsCustomer && _customer == null);
    if (currency == null || minor == null || (_needsCustomer && _customer == null)) {
      children.add(WorkbenchHint(
        icon: Icons.receipt_long_outlined,
        text: _needsCustomer
            ? 'مشتری، ارز و مبلغ را وارد کنید تا اثر $_title بر صندوق و حساب مشتری این‌جا نمایش داده شود.'
            : 'ارز و مبلغ را وارد کنید تا اثر مصرف بر صندوق این‌جا نمایش داده شود.',
      ));
    } else {
      final cash = _cash[currency.code] ?? 0;
      final cashAfter = incoming ? cash + minor : cash - minor;
      var position = 0;
      for (final b in _balances) {
        if (b.currency == currency.code) position = b.positionMinor;
      }
      final positionAfter = switch (_kind) {
        _CashKind.receipt => position + minor,
        _CashKind.payment => position - minor,
        _CashKind.expense => position,
      };
      String? drawerName;
      for (final d in s.activeDrawers) {
        if (d.id == _drawerId) drawerName = d.nameFa;
      }

      children.addAll([
        WorkbenchFlowLine(
          incoming: incoming,
          label: switch (_kind) {
            _CashKind.receipt => 'دریافت نقد از ${_customer!.name}',
            _CashKind.payment => 'پرداخت نقد به ${_customer!.name}',
            _CashKind.expense => 'پرداخت مصرف از صندوق',
          },
          amount: MoneyFormat.withName(minor, currency),
          hint: _description.text.trim().isEmpty ? null : _description.text.trim(),
          amountColor: cashAfter < 0 ? AppColors.error : null,
        ),
        Divider(height: 1, color: AppColors.divider),
        WorkbenchValueRow(label: 'صندوق اصلی', value: drawerName ?? '—'),
        WorkbenchValueRow(label: 'تاریخ', value: DateFormatFa.business(_date)),
        WorkbenchBalanceChange(
          icon: Icons.point_of_sale_outlined,
          label: 'موجودی نقد ${currency.nameFa} در صندوق اصلی مشترک',
          before: MoneyFormat.amount(cash, currency),
          after: MoneyFormat.amount(cashAfter, currency),
          afterColor: cashAfter < 0 ? AppColors.error : (incoming ? AppColors.success : null),
        ),
        if (cashAfter < 0)
          const InfoBanner(
            'این برداشت نمی‌تواند از موجودی فعلی صندوق اصلی مشترک بیشتر باشد؛ مبلغ را تا سقف موجودی صندوق کم کنید.',
            tone: BannerTone.error,
          ),
        if (_needsCustomer)
          WorkbenchBalanceChange(
            icon: Icons.account_balance_wallet_outlined,
            label: 'حساب ${_customer!.name} — ${currency.nameFa}',
            before: MoneyFormat.position(position, currency),
            after: MoneyFormat.position(positionAfter, currency),
            afterColor: positionAfter < 0 ? AppColors.error : AppColors.success,
          ),
      ]);
    }

    return WorkbenchSummaryPanel(
      icon: switch (_kind) {
        _CashKind.receipt => Icons.south_west_rounded,
        _CashKind.payment => Icons.north_east_rounded,
        _CashKind.expense => Icons.receipt_long_outlined,
      },
      title: 'خلاصه $_title',
      subtitle: switch (_kind) {
        _CashKind.receipt => 'نقد وارد صندوق و به طلب مشتری افزوده می‌شود',
        _CashKind.payment => 'نقد از صندوق خارج و از طلب مشتری کم می‌شود',
        _CashKind.expense => 'نقد از صندوق خارج و به‌عنوان مصرف ثبت می‌شود',
      },
      accent: switch (_kind) {
        _CashKind.receipt => AppColors.success,
        _CashKind.payment => AppColors.info,
        _CashKind.expense => AppColors.warning,
      },
      height: 600,
      centerChildren: placeholder,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfPrimaryButton(
            label: 'ثبت $_title',
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
      title: 'آخرین سند ثبت‌شده',
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
        '${last.type.labelFa} ${MoneyFormat.withName(last.sourceAmountMinor ?? 0, s.currency(last.sourceCurrency))}'
        '${last.customerName == null ? '' : ' — ${last.customerName}'}',
        style: AppTypography.body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    return PageScaffold(
      title: 'رسید، برد و مصرف',
      subtitle: 'دریافت و پرداخت نقد با مشتریان و پرداخت مصارف صرافی از صندوق',
      body: WorkbenchLayout(
        main: (m) => [
          WorkbenchModeSelector<_CashKind>(
            gap: m.fieldGap,
            value: _kind,
            onChanged: (v) => setState(() => _kind = v),
            options: [
              WorkbenchModeOption(
                _CashKind.receipt,
                'رسید',
                'دریافت نقد از مشتری؛ به طلب مشتری افزوده می‌شود.',
                Icons.south_west_rounded,
                color: AppColors.success,
              ),
              WorkbenchModeOption(
                _CashKind.payment,
                'برد',
                'پرداخت نقد به مشتری؛ از طلب مشتری کم می‌شود.',
                Icons.north_east_rounded,
                color: AppColors.info,
              ),
              WorkbenchModeOption(
                _CashKind.expense,
                'مصرف',
                'پرداخت هزینه‌های صرافی (کرایه، معاش…) از صندوق.',
                Icons.receipt_long_outlined,
                color: AppColors.warning,
              ),
            ],
          ),
          _partySection(m, s),
          _amountSection(m),
        ],
        side: (m) => [
          _summary(s),
          if (_last != null) _lastCard(s, m),
        ],
      ),
    );
  }
}
