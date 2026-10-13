import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/read_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_loader.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import 'exchange_ui.dart';
import 'order_detail_dialog_style.dart';
import 'order_detail_info_card.dart';
import 'transaction_actions.dart';

/// Full view of one posted transaction: header, its items as the customer
/// sees them (what was received and paid, in which currency), links between
/// edited/replacement/reversal versions, and edit/delete actions.
class TransactionDetailDialog extends StatefulWidget {
  const TransactionDetailDialog({super.key, required this.transactionId});

  final int transactionId;

  static Future<void> show(BuildContext context, int transactionId) {
    return OrderDetailDialogFrame.show<void>(
      context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: TransactionDetailDialog(transactionId: transactionId),
      ),
    );
  }

  @override
  State<TransactionDetailDialog> createState() => _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<TransactionDetailDialog> {
  PostedTransaction? _tx;

  /// For a reversal document: the transaction it cancelled.
  PostedTransaction? _reversed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(widget.transactionId);
  }

  Future<void> _load(int id) async {
    final posting = context.read<AppSession>().services.posting;
    final tx = await posting.transactionById(id);
    final reversedId = tx?.reversesTransactionId;
    final reversed = reversedId == null ? null : await posting.transactionById(reversedId);
    if (mounted) {
      setState(() {
        _tx = tx;
        _reversed = reversed;
      });
    }
  }

  Future<void> _edit() async {
    final fixed = await TransactionActions.edit(context, _tx!);
    if (fixed != null && mounted) await _load(fixed.id);
  }

  Future<void> _delete() async {
    final tx = _tx!;
    setState(() => _busy = true);
    final deleted = await TransactionActions.delete(context, tx);
    if (!mounted) return;
    setState(() => _busy = false);
    if (deleted) await _load(tx.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final tx = _tx;
    final statusColor = tx == null ? OrderDetailDialogStyle.success : TransactionActions.statusColor(tx);

    return OrderDetailDialogFrame(
      icon: Icons.receipt_long_outlined,
      maxWidth: 640,
      title: tx == null ? 'جزئیات معامله' : '${tx.type.labelFa} — ${tx.referenceNo}',
      subtitle: tx == null ? null : DateFormatFa.dateTime(tx.createdAt),
      headerTrailing: tx == null
          ? null
          : OrderDetailStatusBadge(
              label: TransactionActions.statusLabel(tx),
              color: statusColor,
              background: statusColor.withValues(alpha: 0.12),
            ),
      footerStart: [
        if (tx != null && TransactionActions.canEdit(tx, s))
          OrderDetailFooterAction(
            label: 'ویرایش',
            icon: Icons.edit_outlined,
            onPressed: _busy ? null : _edit,
          ),
        if (tx != null && TransactionActions.canDelete(tx, s))
          OrderDetailFooterAction(
            label: _busy ? 'در حال حذف…' : 'حذف',
            icon: Icons.delete_outline_rounded,
            danger: true,
            onPressed: _busy ? null : _delete,
          ),
        if (tx?.replacedByTransactionId != null)
          OrderDetailFooterAction(
            label: 'نمایش نسخه اصلاحی',
            icon: Icons.link_rounded,
            onPressed: () => _load(tx!.replacedByTransactionId!),
          ),
        if (tx?.replacesTransactionId != null)
          OrderDetailFooterAction(
            label: 'نمایش نسخه قبلی',
            icon: Icons.history_rounded,
            onPressed: () => _load(tx!.replacesTransactionId!),
          ),
        if (tx?.reversesTransactionId != null)
          OrderDetailFooterAction(
            label: 'نمایش معامله اصلی',
            icon: Icons.link_rounded,
            onPressed: () => _load(tx!.reversesTransactionId!),
          ),
        if (tx?.reversedByTransactionId != null && tx?.replacedByTransactionId == null)
          OrderDetailFooterAction(
            label: 'نمایش سند برگشت',
            icon: Icons.link_rounded,
            onPressed: () => _load(tx!.reversedByTransactionId!),
          ),
      ],
      summary: tx == null ? null : _footer(tx, s),
      body: tx == null ? const SizedBox(height: 240, child: GfPageLoader()) : _body(tx, s),
    );
  }

  Widget _body(PostedTransaction tx, AppSession s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OrderDetailInfoCard(
                title: 'مشتری',
                child: OrderDetailInfoValue(
                  icon: Icons.person_outline_rounded,
                  value: tx.customerName ?? '—',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OrderDetailInfoCard(
                title: 'تاریخ مؤثر',
                child: OrderDetailInfoValue(
                  icon: Icons.event_outlined,
                  value: DateFormatFa.business(tx.effectiveDate),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OrderDetailInfoCard(
                title: 'ثبت‌کننده',
                child: OrderDetailInfoValue(
                  icon: Icons.badge_outlined,
                  value: tx.createdByName ?? '${tx.createdBy}',
                ),
              ),
            ),
          ],
        ),
        OrderDetailDialogStyle.sectionSpace,
        Text(
          'اقلام معامله',
          style: AppTypography.caption.copyWith(
            color: OrderDetailDialogStyle.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        OrderDetailDialogStyle.smallSpace,
        _itemsTable(tx, s),
        if (tx.status == TransactionStatus.reversed) ...[
          OrderDetailDialogStyle.sectionSpace,
          InfoBanner(
            tx.wasEdited
                ? 'این معامله ویرایش شده است؛ اثر مالی آن خنثی و «نسخه اصلاحی» جایگزین آن شده است.'
                : 'این معامله حذف شده و اثر مالی آن با سند برگشت خنثی شده است؛ فقط برای سابقه نمایش داده می‌شود.',
            tone: BannerTone.warning,
          ),
        ],
        if (tx.replacesTransactionId != null) ...[
          OrderDetailDialogStyle.sectionSpace,
          const InfoBanner('این نسخه اصلاح‌شده یک معامله ویرایش‌شده است.', tone: BannerTone.info),
        ],
      ],
    );
  }

  static String? _text(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// The items of [tx] from the exchange's side: `incoming` is money or
  /// currency the exchange received, otherwise it paid it out.
  List<_Item> _items(PostedTransaction tx) {
    _Item source(String label, {required bool incoming}) =>
        _Item(label, tx.sourceCurrency, tx.sourceAmountMinor ?? (tx.signedAmountMinor ?? 0).abs(), incoming);
    String via(String? settlement, {required bool incoming}) =>
        settlement == Settlement.customer.name ? (incoming ? ' (از حساب مشتری)' : ' (به حساب مشتری)') : '';
    final up = (tx.signedAmountMinor ?? 0) >= 0;

    switch (tx.type) {
      case TransactionType.receipt:
        return [source('دریافت پول از مشتری', incoming: true)];
      case TransactionType.payment:
        return [source('پرداخت پول به مشتری', incoming: false)];
      case TransactionType.buy:
      case TransactionType.sell:
        final buy = tx.type == TransactionType.buy;
        final fee = tx.feeAmountMinor;
        return [
          _Item(
            (buy ? 'ارز خریداری‌شده' : 'ارز فروخته‌شده') + via(tx.sourceSettlement, incoming: buy),
            tx.sourceCurrency,
            tx.sourceAmountMinor ?? 0,
            buy,
          ),
          _Item(
            (buy ? 'مبلغ پرداخت‌شده در برابر آن' : 'مبلغ دریافت‌شده در برابر آن') +
                via(tx.destSettlement, incoming: !buy),
            tx.destCurrency,
            tx.destAmountMinor ?? 0,
            !buy,
          ),
          if (fee != null && fee > 0)
            _Item('کمیشن' + via(tx.feeSettlement, incoming: true), tx.feeCurrency, fee, true),
        ];
      case TransactionType.openingCustomer:
        return [source(up ? 'بیلانس افتتاحیه (طلب مشتری)' : 'بیلانس افتتاحیه (بدهی مشتری)', incoming: up)];
      case TransactionType.customerAdjustment:
        return [source(up ? 'اصلاح حساب — افزایش طلب مشتری' : 'اصلاح حساب — افزایش بدهی مشتری', incoming: up)];
      case TransactionType.openingCash:
        return [source('سرمایه واریزشده به صندوق', incoming: true)];
      case TransactionType.cashAdjustment:
        return [source(up ? 'اصلاح صندوق — افزایش موجودی' : 'اصلاح صندوق — کاهش موجودی', incoming: up)];
      case TransactionType.expense:
        return [source('مصرف از صندوق', incoming: false)];
      case TransactionType.reversal:
        final original = _reversed;
        if (original == null) return [source('مبلغ برگشت‌شده', incoming: false)];
        return [
          for (final i in _items(original)) _Item('برگشت: ${i.label}', i.currency, i.minor, !i.incoming),
        ];
    }
  }

  Widget _itemsTable(PostedTransaction tx, AppSession s) {
    final withCustomer = tx.customerId != null;
    Widget amount(_Item i, bool incomingColumn) {
      if (i.incoming != incomingColumn) {
        return Text('—', style: AppTypography.body.copyWith(color: OrderDetailDialogStyle.muted));
      }
      return Text(
        MoneyFormat.amount(i.minor, s.currency(i.currency)),
        textDirection: TextDirection.ltr,
        style: AppTypography.bodySemiBold.copyWith(
          color: incomingColumn ? AppColors.success : AppColors.error,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return OrderDetailLinesTable(
      columns: [
        const LedgerColumn('شرح', flex: 4),
        const LedgerColumn('ارز', flex: 2),
        LedgerColumn(withCustomer ? 'دریافت از مشتری' : 'ورود به صندوق', numeric: true, flex: 3),
        LedgerColumn(withCustomer ? 'پرداخت به مشتری' : 'خروج از صندوق', numeric: true, flex: 3),
      ],
      rows: [
        for (final i in _items(tx))
          [
            Text(i.label, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(s.currency(i.currency)?.nameFa ?? i.currency ?? '—'),
            amount(i, true),
            amount(i, false),
          ],
      ],
    );
  }

  /// Amounts panel followed by the description and reason, pinned at the
  /// bottom of the dialog above the buttons.
  Widget? _footer(PostedTransaction tx, AppSession s) {
    final summary = _summary(tx, s);
    final description = _text(tx.description);
    final reason = _text(tx.reason);
    if (summary == null && description == null && reason == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?summary,
        if (description != null) ...[
          if (summary != null) OrderDetailDialogStyle.sectionSpace,
          _NoteCard(icon: Icons.notes_rounded, title: 'شرح', text: description),
        ],
        if (reason != null) ...[
          if (summary != null || description != null) OrderDetailDialogStyle.sectionSpace,
          _NoteCard(icon: Icons.help_outline_rounded, title: 'دلیل', text: reason),
        ],
      ],
    );
  }

  Widget? _summary(PostedTransaction tx, AppSession s) {
    final src = s.currency(tx.sourceCurrency);
    final fee = tx.feeAmountMinor == null
        ? null
        : OrderDetailStat('کمیشن', MoneyFormat.withName(tx.feeAmountMinor!, s.currency(tx.feeCurrency)));
    if (tx.isExchange) {
      return OrderDetailStatPanel(
        stats: [
          OrderDetailStat(
            'نرخ',
            '1 ${src?.nameFa ?? tx.sourceCurrency} = '
                '${MoneyFormat.rate(tx.rate ?? '')} ${s.currency(tx.destCurrency)?.nameFa ?? tx.destCurrency}',
          ),
          ?fee,
        ],
        highlights: [
          OrderDetailStat(
            tx.type == TransactionType.buy ? 'ارز خریداری‌شده' : 'ارز فروخته‌شده',
            MoneyFormat.withName(tx.sourceAmountMinor ?? 0, src),
          ),
          OrderDetailStat('مبلغ مقابل', MoneyFormat.withName(tx.destAmountMinor ?? 0, s.currency(tx.destCurrency))),
        ],
      );
    }
    final amount = tx.signedAmountMinor ?? tx.sourceAmountMinor;
    if (amount == null && fee == null) return null;
    return OrderDetailStatPanel(
      stats: [?fee],
      highlights: [
        if (amount != null) OrderDetailStat('مبلغ', MoneyFormat.withName(amount, src)),
      ],
    );
  }
}

class _Item {
  const _Item(this.label, this.currency, this.minor, this.incoming);

  final String label;
  final String? currency;
  final int minor;

  /// Received by the exchange; otherwise paid out by it.
  final bool incoming;
}

/// Titled card for free text (description, reason) that wraps instead of
/// being squeezed into a label/value row.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: OrderDetailDialogStyle.cardPadding,
      decoration: OrderDetailDialogStyle.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: OrderDetailDialogStyle.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.caption.copyWith(color: OrderDetailDialogStyle.muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  text,
                  style: AppTypography.body.copyWith(
                    color: OrderDetailDialogStyle.navy,
                    fontSize: 13.5,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
