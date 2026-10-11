import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/posting_service.dart';
import '../../application/read_models.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/security/permissions.dart';
import '../../domain/transactions/financial_command.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import 'exchange_ui.dart';
import 'transaction_edit_dialog.dart';

/// Edit and delete entry points shared by the journal and the detail dialog.
abstract final class TransactionActions {
  static String _postPermission(TransactionType type) => switch (type) {
        TransactionType.openingCash || TransactionType.openingCustomer => Permissions.openingBalancesPost,
        _ => Permissions.transactionsPost,
      };

  static bool canEdit(PostedTransaction t, AppSession s) =>
      t.isActive &&
      PostingService.correctableInto(t.type).isNotEmpty &&
      s.can(Permissions.transactionsReverse) &&
      s.can(_postPermission(t.type));

  static bool canDelete(PostedTransaction t, AppSession s) =>
      t.isActive && s.can(Permissions.transactionsReverse);

  /// Opens the edit form. Returns the corrected transaction once saved.
  static Future<PostedTransaction?> edit(BuildContext context, PostedTransaction t) =>
      TransactionEditDialog.show(context, t);

  /// Asks for a reason, then deletes (reverses on the original date).
  static Future<bool> delete(BuildContext context, PostedTransaction t) async {
    final s = context.read<AppSession>();
    final reason = await askReason(
      context,
      title: 'حذف ${t.type.labelFa} ${t.referenceNo}',
      message: 'این معامله با همه بخش‌هایش (همه ارزها و کمیشن) از موجودی صندوق، حساب مشتری و '
          'بیلانس روز ${DateFormatFa.business(t.effectiveDate)} حذف می‌شود. '
          'برای حفظ سابقه، سند اصلی با وضعیت «حذف‌شده» در روزنامچه باقی می‌ماند.',
      confirmLabel: 'حذف معامله',
    );
    if (reason == null || !context.mounted) return false;
    final result = await runAction(
      context,
      () => s.services.posting.delete(
        transactionId: t.id,
        reason: reason,
        actor: s.actor,
        idempotencyKey: PostingService.newIdempotencyKey(),
      ),
      success: '${t.type.labelFa} ${t.referenceNo} حذف شد.',
    );
    return result != null;
  }

  static String statusLabel(PostedTransaction t) {
    if (t.status == TransactionStatus.reversed) return t.wasEdited ? 'ویرایش‌شده' : 'حذف‌شده';
    if (t.type == TransactionType.reversal) return 'سند برگشت';
    if (t.replacesTransactionId != null) return 'نسخه اصلاحی';
    return 'ثبت‌شده';
  }

  static Color statusColor(PostedTransaction t) {
    if (t.status == TransactionStatus.reversed) return t.wasEdited ? AppColors.info : AppColors.error;
    if (t.type == TransactionType.reversal) return AppColors.textMuted;
    return AppColors.success;
  }
}
