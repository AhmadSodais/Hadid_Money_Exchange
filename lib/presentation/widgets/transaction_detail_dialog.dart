import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/read_models.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_loader.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import 'exchange_ui.dart';
import 'order_detail_dialog_style.dart';
import 'order_detail_info_card.dart';
import 'transaction_actions.dart';

/// Full view of one posted transaction: header, every journal line, links
/// between edited/replacement/reversal versions, and edit/delete actions.
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(widget.transactionId);
  }

  Future<void> _load(int id) async {
    final tx = await context.read<AppSession>().services.posting.transactionById(id);
    if (mounted) setState(() => _tx = tx);
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
      summary: tx == null ? null : _summary(tx, s),
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
        if (tx.description != null || tx.reason != null) ...[
          OrderDetailDialogStyle.sectionSpace,
          OrderDetailSummaryCard(
            rows: [
              if (tx.description != null) OrderDetailSummaryRow(label: 'شرح', value: tx.description!, dense: true),
              if (tx.reason != null) OrderDetailSummaryRow(label: 'دلیل', value: tx.reason!, dense: true),
            ],
          ),
        ],
        OrderDetailDialogStyle.sectionSpace,
        Text(
          'سند حسابداری (هر ارز جداگانه تراز است)',
          style: AppTypography.caption.copyWith(
            color: OrderDetailDialogStyle.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        OrderDetailDialogStyle.smallSpace,
        OrderDetailLinesTable(
          columns: const [
            LedgerColumn.primary('حساب'),
            LedgerColumn.text('ارز'),
            LedgerColumn.amount('بدهکار'),
            LedgerColumn.amount('بستانکار'),
          ],
          rows: [
            for (final l in tx.lines)
              [
                Text('${l.accountCode}  ${l.accountName}', maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(s.currency(l.currency)?.nameFa ?? l.currency),
                l.debitMinor == 0 ? const Text('') : AmountText(l.debitMinor, s.currency(l.currency)),
                l.creditMinor == 0 ? const Text('') : AmountText(l.creditMinor, s.currency(l.currency)),
              ],
          ],
        ),
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
