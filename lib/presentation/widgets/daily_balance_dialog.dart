import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/read_models.dart';
import '../../application/reconciliation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/shared/business_date.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import 'exchange_ui.dart';

/// "Add balance" (ثبت بیلانس): records the physical cash count of **one**
/// currency for **one** day. Any past day can be chosen, so a forgotten day
/// can be entered later; the expected balance is always computed from the
/// transactions of that exact day, never from today's figures.
///
/// A count never changes the ledger. Returns the saved record, or null.
class DailyBalanceDialog extends StatefulWidget {
  const DailyBalanceDialog({
    super.key,
    required this.drawerId,
    required this.date,
    this.currency,
  });

  final int drawerId;
  final BusinessDate date;
  final Currency? currency;

  static Future<ReconciliationRecord?> show(
    BuildContext context, {
    required int drawerId,
    required BusinessDate date,
    Currency? currency,
  }) {
    return showDialog<ReconciliationRecord>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: DailyBalanceDialog(drawerId: drawerId, date: date, currency: currency),
      ),
    );
  }

  @override
  State<DailyBalanceDialog> createState() => _DailyBalanceDialogState();
}

class _DailyBalanceDialogState extends State<DailyBalanceDialog> {
  final _counted = TextEditingController();
  final _notes = TextEditingController();
  late BusinessDate _date = widget.date;
  Currency? _currency;
  ReconciliationSnapshot? _snapshot;
  ReconciliationRecord? _existing;

  /// The existing count has a posted adjustment, so it cannot be replaced.
  bool _adjusted = false;
  bool _loading = false;
  bool _saving = false;
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    final currencies = context.read<AppSession>().activeCurrencies;
    _currency = widget.currency ?? (currencies.isEmpty ? null : currencies.first);
    _load();
  }

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _future => _date.isAfter(BusinessDate.today());

  Future<void> _load() async {
    final c = _currency;
    if (c == null || _future) {
      setState(() {
        _snapshot = null;
        _existing = null;
      });
      return;
    }
    final seq = ++_loadSeq;
    setState(() => _loading = true);
    final services = context.read<AppSession>().services;
    final snap = await services.reconciliation.compute(widget.drawerId, c.code, _date);
    final rec = await services.reconciliation.active(widget.drawerId, c.code, _date);
    var adjusted = false;
    if (rec?.adjustmentTransactionId != null) {
      final adj = await services.posting.transactionById(rec!.adjustmentTransactionId!);
      adjusted = adj?.status == TransactionStatus.posted;
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _snapshot = snap;
      _existing = rec;
      _adjusted = adjusted;
      _loading = false;
      _counted.text = rec == null ? '' : MoneyFormat.editable(rec.countedMinor, c);
      _notes.text = rec?.notes ?? '';
    });
  }

  int? get _typedMinor {
    final c = _currency;
    if (c == null) return null;
    final minor = MoneyFormat.tryParse(_counted.text, c);
    return minor == null || minor < 0 ? null : minor;
  }

  /// Why saving is impossible right now, or null.
  String? get _blocker {
    if (_currency == null) return 'ارز را انتخاب کنید.';
    if (_future) return 'بیلانس روز آینده قابل ثبت نیست.';
    final rec = _existing;
    if (rec?.status == 'closed') {
      return 'بیلانس ${_currency!.nameFa} در این روز بسته شده است؛ برای تغییر، ابتدا روز را از جدول بازگشایی کنید.';
    }
    if (_adjusted) {
      return 'برای این شمارش اصلاح صندوق ثبت شده است؛ برای شمارش مجدد ابتدا سند اصلاح را از روزنامچه حذف کنید.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_blocker != null) {
      GfToast.error(context, _blocker!);
      return;
    }
    final minor = _typedMinor;
    if (minor == null) {
      GfToast.error(context, 'مبلغ شمارش‌شده ${_currency!.nameFa} معتبر نیست.');
      return;
    }
    setState(() => _saving = true);
    final s = context.read<AppSession>();
    final rec = await runAction(
      context,
      () => s.services.reconciliation.saveCount(
        drawerId: widget.drawerId,
        currency: _currency!.code,
        date: _date,
        countedMinor: minor,
        notes: _notes.text,
        actor: s.actor,
      ),
      success: 'بیلانس ${_currency!.nameFa} برای ${DateFormatFa.business(_date)} ثبت شد.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (rec != null) Navigator.of(context).pop(rec);
  }

  Widget _preview(Currency c) {
    final snap = _snapshot;
    if (snap == null) return const SizedBox.shrink();
    final typed = _typedMinor;
    final diff = typed == null ? null : typed - snap.expectedMinor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DialogResponsiveRow(children: [
          DialogMetricBox(
            icon: Icons.menu_book_outlined,
            title: 'مانده مورد انتظار (از معاملات)',
            value: MoneyFormat.withName(snap.expectedMinor, c),
            hint: 'اول روز ${MoneyFormat.amount(snap.openingMinor, c)}  ·  '
                '+${MoneyFormat.amount(snap.inflowMinor, c)}  ·  -${MoneyFormat.amount(snap.outflowMinor, c)}',
          ),
          DialogMetricBox(
            icon: Icons.difference_outlined,
            title: 'اختلاف (شمارش - مورد انتظار)',
            value: diff == null ? '—' : MoneyFormat.withName(diff, c),
            valueColor: diff == null || diff == 0 ? null : (diff > 0 ? AppColors.success : AppColors.error),
            hint: diff == null
                ? 'پس از وارد کردن مبلغ محاسبه می‌شود'
                : (diff == 0 ? 'بدون اختلاف' : (diff > 0 ? 'اضافه صندوق' : 'کسری صندوق')),
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _currency;
    final blocker = _blocker;
    final rec = _existing;
    final pastDay = _date.isBefore(BusinessDate.today());
    return GfDialogShell(
      icon: Icons.account_balance_wallet_outlined,
      iconColor: AppColors.primary,
      title: c == null ? 'ثبت بیلانس' : 'ثبت بیلانس ${c.nameFa} (${c.code})',
      subtitle: 'شمارش فزیکی نقد یک ارز برای یک روز',
      cancelLabel: 'انصراف',
      onCancel: () => Navigator.of(context).pop(),
      primaryLabel: rec == null ? 'ثبت بیلانس' : 'ذخیره شمارش جدید',
      primaryIcon: Icons.save_outlined,
      onPrimary: blocker == null && !_loading ? _save : null,
      saving: _saving,
      maxWidth: 560,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogResponsiveRow(children: [
            BusinessDateField(
              label: 'تاریخ بیلانس',
              value: _date,
              onChanged: (d) {
                _date = d;
                _load();
              },
            ),
            CurrencyPicker(
              value: c,
              onChanged: (v) {
                _currency = v;
                _load();
              },
            ),
          ]),
          const SizedBox(height: 14),
          AmountField(
            controller: _counted,
            label: c == null ? 'مبلغ شمارش‌شده' : 'مبلغ شمارش‌شده ${c.nameFa} در صندوق',
            enabled: blocker == null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          if (c != null && !_future) _preview(c),
          const SizedBox(height: 14),
          GfTextField(
            label: 'یادداشت (اختیاری)',
            controller: _notes,
            enabled: blocker == null,
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          if (blocker != null)
            InfoBanner(blocker, tone: BannerTone.error)
          else if (rec != null)
            InfoBanner(
              'برای این روز قبلاً ${MoneyFormat.withName(rec.countedMinor, c)} ثبت شده است؛ '
              'با ذخیره، شمارش جدید جایگزین آن می‌شود.',
              tone: BannerTone.warning,
            )
          else if (pastDay)
            const InfoBanner(
              'ثبت بیلانس برای روز گذشته: مانده مورد انتظار فقط از معاملات تا پایان همان روز محاسبه می‌شود.',
            ),
          const SizedBox(height: 6),
          Text(
            'ثبت بیلانس موجودی دفتر را تغییر نمی‌دهد؛ اختلاف فقط با «اصلاح اختلاف» در جدول بیلانس اصلاح می‌شود.',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
