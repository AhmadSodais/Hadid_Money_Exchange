import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/posting_service.dart';
import '../../application/read_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_loader.dart';
import '../../domain/security/permissions.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import 'exchange_ui.dart';
import 'order_detail_dialog_style.dart';
import 'order_detail_info_card.dart';

/// Full view of one posted transaction: header, every journal line, links
/// to its reversal, and the reversal action. Posted records are read-only.
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
  bool _reversing = false;
  final String _reversalKey = PostingService.newIdempotencyKey();

  @override
  void initState() {
    super.initState();
    _load(widget.transactionId);
  }

  Future<void> _load(int id) async {
    final tx = await context.read<AppSession>().services.posting.transactionById(id);
    if (mounted) setState(() => _tx = tx);
  }

  Future<void> _reverse() async {
    final tx = _tx!;
    final reason = await askReason(
      context,
      title: 'برگشت معامله ${tx.referenceNo}',
      message: 'تمام بخش‌های این معامله (همه ارزها و کمیشن) با یک سند مخالف برگشت می‌شود. '
          'سند اصلی حذف نمی‌شود و در روزنامچه با وضعیت «برگشت‌شده» باقی می‌ماند.',
      confirmLabel: 'برگشت معامله',
    );
    if (reason == null || !mounted) return;
    setState(() => _reversing = true);
    final s = context.read<AppSession>();
    final rev = await runAction(
      context,
      () => s.services.posting.reverse(
        transactionId: tx.id,
        reason: reason,
        actor: s.actor,
        idempotencyKey: _reversalKey,
      ),
      success: 'معامله برگشت شد.',
    );
    if (!mounted) return;
    setState(() => _reversing = false);
    if (rev != null) await _load(tx.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final tx = _tx;
    final canReverse = tx != null &&
        tx.status == TransactionStatus.posted &&
        tx.type != TransactionType.reversal &&
        s.can(Permissions.transactionsReverse);
    final reversed = tx?.status == TransactionStatus.reversed;

    return OrderDetailDialogFrame(
      icon: Icons.receipt_long_outlined,
      maxWidth: 640,
      title: tx == null ? 'جزئیات معامله' : '${tx.type.labelFa} — ${tx.referenceNo}',
      subtitle: tx == null ? null : DateFormatFa.dateTime(tx.createdAt),
      headerTrailing: tx == null
          ? null
          : OrderDetailStatusBadge(
              label: reversed ? 'برگشت‌شده' : 'ثبت‌شده',
              color: reversed ? AppColors.warning : OrderDetailDialogStyle.success,
              background: reversed ? AppColors.warningBg : OrderDetailDialogStyle.successBg,
            ),
      footerStart: [
        if (canReverse)
          OrderDetailFooterAction(
            label: _reversing ? 'در حال برگشت…' : 'برگشت معامله',
            icon: Icons.undo_rounded,
            danger: true,
            onPressed: _reversing ? null : _reverse,
          ),
        if (tx?.reversesTransactionId != null)
          OrderDetailFooterAction(
            label: 'نمایش معامله اصلی',
            icon: Icons.link_rounded,
            onPressed: () => _load(tx!.reversesTransactionId!),
          ),
        if (tx?.reversedByTransactionId != null)
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
            OrderDetailColumn('حساب', flex: 4),
            OrderDetailColumn('ارز', flex: 1),
            OrderDetailColumn('بدهکار', flex: 2, numeric: true),
            OrderDetailColumn('بستانکار', flex: 2, numeric: true),
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
          const InfoBanner(
            'این معامله برگشت شده و اثر مالی آن با سند برگشت خنثی شده است.',
            tone: BannerTone.warning,
          ),
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
