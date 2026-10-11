import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/read_models.dart';
import '../../application/reconciliation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/security/permissions.dart';
import '../../domain/shared/business_date.dart';
import '../format/money_format.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/daily_balance_dialog.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/settings_kit.dart';
import '../widgets/workbench_kit.dart';

/// اخذ بیلانس روزانه. Expected = opening + inflows − outflows (from the
/// ledger); difference = counted − expected. A count never changes the
/// ledger; a difference is corrected only by an authorized adjustment.
///
/// Balances are entered one currency at a time through [DailyBalanceDialog],
/// for any past day, so a forgotten day can be recorded later.
class ReconciliationPage extends StatefulWidget {
  const ReconciliationPage({super.key});

  @override
  State<ReconciliationPage> createState() => _ReconciliationPageState();
}

/// How far back the "days without a balance" list looks.
const int _missingLookbackDays = 30;

class _Row {
  _Row(this.currency, this.snapshot, this.record, {required this.adjustmentPosted});

  final Currency currency;
  final ReconciliationSnapshot snapshot;
  final ReconciliationRecord? record;

  /// The count has a posted cash adjustment; recount/remove needs it deleted first.
  final bool adjustmentPosted;

  bool get closed => record?.status == 'closed';

  /// Counted before more transactions were posted for the day: must be recounted.
  bool get stale {
    final rec = record;
    return rec != null && !closed && !adjustmentPosted && rec.expectedMinor != snapshot.expectedMinor;
  }

  bool get pendingDifference {
    final rec = record;
    return rec != null && !closed && rec.differenceMinor != 0 && !adjustmentPosted;
  }
}

enum _Action { count, recount, edit, remove, adjust, close, reopen }

class _ReconciliationPageState extends State<ReconciliationPage> with RevisionReload {
  final _scroll = ScrollController();
  int? _drawerId;
  BusinessDate _date = BusinessDate.today();
  bool _loading = true;
  List<_Row> _rows = const [];
  List<ReconciliationRecord> _history = const [];
  List<({BusinessDate date, String currency})> _missing = const [];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final s = session;
    _drawerId ??= () {
      final settings = context.read<AppSettingsProvider>();
      final drawers = s.activeDrawers;
      return drawers.any((d) => d.id == settings.selectedDrawerId)
          ? settings.selectedDrawerId
          : (drawers.isEmpty ? null : drawers.first.id);
    }();
    final drawer = _drawerId;
    if (drawer == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final svc = s.services.reconciliation;
    final rows = <_Row>[];
    for (final c in s.activeCurrencies) {
      final snap = await svc.compute(drawer, c.code, _date);
      final rec = await svc.active(drawer, c.code, _date);
      var adjustmentPosted = false;
      if (rec?.adjustmentTransactionId != null) {
        final adj = await s.services.posting.transactionById(rec!.adjustmentTransactionId!);
        adjustmentPosted = adj?.status == TransactionStatus.posted;
      }
      rows.add(_Row(c, snap, rec, adjustmentPosted: adjustmentPosted));
    }
    final history = await svc.records(drawerId: drawer);
    final today = BusinessDate.today();
    final missing = await svc.missingCounts(drawer, from: today.addDays(-_missingLookbackDays), to: today.addDays(-1));
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _history = history.take(60).toList();
      _missing = missing;
      _loading = false;
    });
  }

  void _goToDate(BusinessDate date) {
    _date = date;
    reload();
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _addBalance({Currency? currency, BusinessDate? date}) async {
    final drawer = _drawerId;
    if (drawer == null) {
      GfToast.error(context, 'صندوق فعالی وجود ندارد.');
      return;
    }
    final rec = await DailyBalanceDialog.show(context, drawerId: drawer, date: date ?? _date, currency: currency);
    if (rec != null && mounted && rec.businessDate != _date) _goToDate(rec.businessDate);
  }

  Future<void> _remove(ReconciliationRecord rec, Currency c) async {
    final reason = await askReason(
      context,
      title: 'حذف شمارش ${c.nameFa}',
      message:
          'شمارش ${MoneyFormat.withName(rec.countedMinor, c)} برای ${DateFormatFa.business(rec.businessDate)} '
          'حذف می‌شود و می‌توانید دوباره ثبت کنید. موجودی دفتر تغییر نمی‌کند.',
      confirmLabel: 'حذف شمارش',
    );
    if (reason == null || !mounted) return;
    final s = context.read<AppSession>();
    await runAction(
      context,
      () => s.services.reconciliation.voidCount(rec.id, reason, s.actor),
      success: 'شمارش ${c.nameFa} حذف شد.',
    );
  }

  Future<void> _adjust(ReconciliationRecord rec, Currency c) async {
    final reason = await askReason(
      context,
      title: 'اصلاح اختلاف ${c.nameFa}',
      message:
          'یک سند اصلاح صندوق به مبلغ ${MoneyFormat.withName(rec.differenceMinor, c)} '
          '(${rec.differenceMinor > 0 ? 'اضافه' : 'کسری'}) با تاریخ ${DateFormatFa.business(rec.businessDate)} ثبت می‌شود.',
      confirmLabel: 'ثبت اصلاح',
    );
    if (reason == null || !mounted) return;
    final s = context.read<AppSession>();
    await runAction(
      context,
      () => s.services.reconciliation.postAdjustment(rec.id, reason, s.actor),
      success: 'اصلاح صندوق ثبت شد.',
    );
  }

  Future<void> _close(ReconciliationRecord rec) async {
    final s = context.read<AppSession>();
    await runAction(
      context,
      () => s.services.reconciliation.close(rec.id, s.actor),
      success: 'بیلانس روز بسته شد؛ ثبت، ویرایش یا حذف معامله با این تاریخ برای این ارز قفل است.',
    );
  }

  Future<void> _reopen(ReconciliationRecord rec) async {
    final reason = await askReason(
      context,
      title: 'بازگشایی روز بسته‌شده',
      message: 'با بازگشایی، ثبت، ویرایش و حذف معاملات این تاریخ دوباره ممکن می‌شود. دلیل در سوابق ممیزی ثبت می‌شود.',
      confirmLabel: 'بازگشایی',
    );
    if (reason == null || !mounted) return;
    final s = context.read<AppSession>();
    await runAction(
      context,
      () => s.services.reconciliation.reopen(rec.id, reason, s.actor),
      success: 'روز بازگشایی شد.',
    );
  }

  void _run(_Action action, _Row r) {
    switch (action) {
      case _Action.count || _Action.recount || _Action.edit:
        _addBalance(currency: r.currency);
      case _Action.remove:
        _remove(r.record!, r.currency);
      case _Action.adjust:
        _adjust(r.record!, r.currency);
      case _Action.close:
        _close(r.record!);
      case _Action.reopen:
        _reopen(r.record!);
    }
  }

  String _statusLabel(ReconciliationRecord? rec) {
    if (rec == null) return 'ثبت نشده';
    if (rec.status == 'closed') return 'بسته';
    if (rec.adjustmentTransactionId != null) return 'باز — اصلاح‌شده';
    return rec.differenceMinor == 0 ? 'باز — بدون اختلاف' : 'باز — دارای اختلاف';
  }

  Color _statusColor(ReconciliationRecord? rec) {
    if (rec == null) return AppColors.textMuted;
    if (rec.status == 'closed') return AppColors.success;
    if (rec.adjustmentTransactionId != null || rec.differenceMinor == 0) return AppColors.info;
    return AppColors.warning;
  }

  // ------------------------------------------------------------ header card

  Widget _header(SettingsMetrics m) {
    final total = _rows.length;
    final counted = _rows.where((r) => r.record != null && !r.stale).length;
    final stale = _rows.where((r) => r.stale).length;
    final pending = _rows.where((r) => r.pendingDifference).length;
    final closed = _rows.where((r) => r.closed).length;
    final allClosed = total > 0 && closed == total;

    final steps = [
      _StepItem(
        step: 1,
        title: 'ثبت بیلانس هر ارز',
        detail: stale > 0 ? '$counted از $total ارز — $stale ارز نیاز به شمارش مجدد' : '$counted از $total ارز ثبت شده',
        done: total > 0 && counted == total,
      ),
      _StepItem(
        step: 2,
        title: 'اصلاح اختلاف‌ها (در صورت نیاز)',
        detail: pending == 0 ? 'اختلاف اصلاح‌نشده‌ای نیست' : '$pending ارز دارای اختلاف اصلاح‌نشده',
        done: total > 0 && counted == total && pending == 0,
        warning: pending > 0,
      ),
      _StepItem(step: 3, title: 'بستن روز', detail: '$closed از $total ارز بسته شده', done: allClosed),
    ];

    return SettingsSectionCard(
      icon: Icons.point_of_sale_outlined,
      title: 'صندوق و تاریخ بیلانس',
      padding: m.cardPadding,
      trailing: GfStatusBadge(
        label: allClosed ? 'بیلانس روز بسته شد' : (closed > 0 ? 'بسته‌شدن ناقص' : 'روز باز'),
        color: allClosed ? AppColors.success : (closed > 0 ? AppColors.warning : AppColors.info),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pickers = SettingsFormRow(
            gap: m.fieldGap,
            breakpoint: 420,
            left: DrawerPicker(
              value: _drawerId,
              onChanged: (id) {
                _drawerId = id;
                context.read<AppSettingsProvider>().setSelectedDrawerId(id);
                reload();
              },
            ),
            right: BusinessDateField(
              label: 'تاریخ بیلانس',
              value: _date,
              onChanged: (d) {
                _date = d;
                reload();
              },
            ),
          );
          final stepper = constraints.maxWidth < 760
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[if (i > 0) SizedBox(height: m.fieldGap), steps[i]],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 13),
                          child: SizedBox(width: 28, child: Divider(height: 1, color: AppColors.border)),
                        ),
                      Expanded(child: steps[i]),
                    ],
                  ],
                );
          if (constraints.maxWidth < 1100) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                pickers,
                SizedBox(height: m.gap),
                stepper,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 460, child: pickers),
              SizedBox(width: m.gap),
              Container(width: 1, height: 56, color: AppColors.divider),
              SizedBox(width: m.gap),
              Expanded(child: stepper),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- count sheet

  Widget _countSheet(bool canAdjust, bool canReopen) {
    return LedgerTable(
      shrinkWrap: true,
      showRowNumbers: false,
      minWidth: 1050,
      title: 'بیلانس ارزها — ${DateFormatFa.business(_date)}',
      subtitle:
          'هر ارز جداگانه ثبت می‌شود: روی «ثبت بیلانس» همان ارز بزنید و مبلغ شمارش‌شده را وارد کنید. '
          'مورد انتظار = مانده اول روز + ورودی − خروجی؛ اختلاف = شمارش − مورد انتظار.',
      emptyText: 'ارز فعالی برای این صندوق وجود ندارد.',
      columns: const [
        LedgerColumn('ارز', width: 100),
        LedgerColumn('مانده اول روز', flex: 2, numeric: true),
        LedgerColumn('گردش روز', flex: 2, numeric: true),
        LedgerColumn('مورد انتظار', flex: 2, numeric: true),
        LedgerColumn('شمارش‌شده', flex: 2, numeric: true),
        LedgerColumn('اختلاف', flex: 2, numeric: true),
        LedgerColumn('وضعیت', width: 132),
        LedgerColumn('', width: 270),
      ],
      rows: [for (final r in _rows) _sheetRow(r, canAdjust, canReopen)],
    );
  }

  Widget _movementLine(String sign, int minor, Currency c, Color color) {
    return Text(
      '$sign ${MoneyFormat.amount(minor, c)}',
      textDirection: TextDirection.ltr,
      style: AppTypography.caption.copyWith(
        color: minor == 0 ? AppColors.textMuted : color,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  List<_Action> _actionsFor(_Row r, bool canAdjust, bool canReopen) {
    final rec = r.record;
    if (rec == null) return const [_Action.count];
    if (r.closed) return [if (canReopen) _Action.reopen];
    final editable = !r.adjustmentPosted;
    if (r.stale) return [_Action.recount, if (editable) _Action.remove];
    return [
      if (r.pendingDifference && canAdjust) _Action.adjust,
      _Action.close,
      if (editable) _Action.edit,
      if (editable) _Action.remove,
    ];
  }

  List<Widget> _sheetRow(_Row r, bool canAdjust, bool canReopen) {
    final c = r.currency;
    final snap = r.snapshot;
    final rec = r.record;
    final actions = _actionsFor(r, canAdjust, canReopen);
    final primary = actions.isEmpty ? null : actions.first;
    String label(_Action a) => switch (a) {
      _Action.count => 'ثبت بیلانس',
      _Action.recount => 'شمارش مجدد',
      _Action.edit => 'ویرایش شمارش',
      _Action.remove => 'حذف شمارش',
      _Action.adjust => 'اصلاح اختلاف',
      _Action.close => 'بستن روز',
      _Action.reopen => 'بازگشایی',
    };
    IconData icon(_Action a) => switch (a) {
      _Action.count => Icons.add_rounded,
      _Action.recount || _Action.edit => Icons.edit_outlined,
      _Action.remove => Icons.delete_outline_rounded,
      _Action.adjust => Icons.tune,
      _Action.close => Icons.lock_outline,
      _Action.reopen => Icons.lock_open,
    };

    return [
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.nameFa, style: AppTypography.bodySemiBold),
          Text(c.code, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        ],
      ),
      AmountText(snap.openingMinor, c),
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _movementLine('+', snap.inflowMinor, c, AppColors.success),
          _movementLine('-', snap.outflowMinor, c, AppColors.error),
        ],
      ),
      AmountText(snap.expectedMinor, c, bold: true),
      rec == null
          ? Text('—', style: AppTypography.body.copyWith(color: AppColors.textMuted))
          : AmountText(rec.countedMinor, c, bold: true),
      rec == null
          ? Text('—', style: AppTypography.body.copyWith(color: AppColors.textMuted))
          : AmountText(rec.differenceMinor, c, signColor: true, bold: true),
      r.stale
          ? Tooltip(
              message: 'پس از ثبت بیلانس، معاملات این روز تغییر کرده است؛ دوباره شمارش کنید.',
              child: GfStatusBadge(label: 'شمارش مجدد', color: AppColors.warning, compact: true),
            )
          : GfStatusBadge(label: _statusLabel(rec), color: _statusColor(rec), compact: true),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (primary == null)
              Text('—', style: AppTypography.body.copyWith(color: AppColors.textMuted))
            else if (primary == _Action.reopen)
              GfDangerButton(
                label: label(primary),
                icon: icon(primary),
                compact: true,
                onPressed: () => _run(primary, r),
              )
            else if (primary == _Action.count || primary == _Action.recount)
              GfPrimaryButton(
                label: label(primary),
                icon: icon(primary),
                compact: true,
                onPressed: () => _run(primary, r),
              )
            else
              GfSecondaryButton(
                label: label(primary),
                icon: icon(primary),
                compact: true,
                onPressed: () => _run(primary, r),
              ),
            if (actions.length > 1)
              LedgerRowMenu(
                onSelected: (v) => _run(_Action.values.byName(v), r),
                items: [
                  for (final a in actions.skip(1))
                    gfPopupMenuItem(value: a.name, label: label(a), danger: a == _Action.remove || a == _Action.reopen),
                ],
              ),
          ],
        ),
      ),
    ];
  }

  // ---------------------------------------------------------- missing days

  Widget _missingDays(AppSession s) {
    return LedgerTable(
      shrinkWrap: true,
      fixedRows: 5,
      showRowNumbers: false,
      title: 'روزهای بدون بیلانس ($_missingLookbackDays روز اخیر)',
      subtitle:
          'در این روزها معامله نقدی ثبت شده اما بیلانس آن ارز ثبت نشده است. '
          'بیلانس روز گذشته را هر وقت خواستید از همین‌جا ثبت کنید؛ روی ردیف بزنید تا آن روز باز شود.',
      itemLabel: 'روز',
      onTapRow: (i) => _goToDate(_missing[i].date),
      columns: const [LedgerColumn('تاریخ', flex: 2), LedgerColumn('ارز', flex: 2), LedgerColumn('', width: 150)],
      rows: [
        for (final m in _missing)
          [
            Text(DateFormatFa.business(m.date), style: AppTypography.body),
            Text(s.currency(m.currency)?.nameFa ?? m.currency, style: AppTypography.bodyMedium),
            GfSecondaryButton(
              label: 'ثبت بیلانس',
              icon: Icons.add_rounded,
              compact: true,
              onPressed: () => _addBalance(currency: s.currency(m.currency), date: m.date),
            ),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canReopen = s.can(Permissions.reconciliationReopen);
    final canAdjust = s.can(Permissions.adjustmentsPost);
    final canCount = s.can(Permissions.reconciliationPerform);
    return PageScaffold(
      title: 'بیلانس روزانه صندوق',
      subtitle: 'ثبت شمارش نقد هر ارز، مقایسه با دفتر و بستن روز',
      actions: [
        if (canCount)
          GfPrimaryButton(
            label: 'افزودن بیلانس',
            icon: Icons.add_rounded,
            onPressed: _loading ? null : () => _addBalance(),
          ),
      ],
      body: _loading
          ? const GfPageLoader()
          : LayoutBuilder(
              builder: (context, constraints) {
                final m = SettingsMetrics.of(constraints.maxWidth);
                return ListView(
                  controller: _scroll,
                  children: [
                    _header(m),
                    SizedBox(height: m.gap),
                    _countSheet(canAdjust, canReopen),
                    if (_missing.isNotEmpty) ...[SizedBox(height: m.gap), _missingDays(s)],
                    SizedBox(height: m.gap),
                    SizedBox(
                      height: 460,
                      child: LedgerTable(
                        title: 'سابقه بیلانس‌ها',
                        subtitle: 'آخرین ۶۰ بیلانس این صندوق؛ برای باز کردن آن روز روی ردیف بزنید.',
                        minWidth: 860,
                        itemLabel: 'بیلانس',
                        emptyText: 'هنوز بیلانسی ثبت نشده است.',
                        onTapRow: (i) => _goToDate(_history[i].businessDate),
                        columns: const [
                          LedgerColumn('تاریخ', width: 110),
                          LedgerColumn('ارز', width: 90),
                          LedgerColumn('مورد انتظار', flex: 2, numeric: true),
                          LedgerColumn('شمارش', flex: 2, numeric: true),
                          LedgerColumn('اختلاف', flex: 2, numeric: true),
                          LedgerColumn('وضعیت', flex: 2),
                        ],
                        rows: [
                          for (final h in _history)
                            [
                              Text(DateFormatFa.business(h.businessDate), style: AppTypography.body),
                              Text(s.currency(h.currency)?.nameFa ?? h.currency, style: AppTypography.bodyMedium),
                              AmountText(h.expectedMinor, s.currency(h.currency)),
                              AmountText(h.countedMinor, s.currency(h.currency)),
                              AmountText(h.differenceMinor, s.currency(h.currency), signColor: true),
                              GfStatusBadge(label: _statusLabel(h), color: _statusColor(h), compact: true),
                            ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.step,
    required this.title,
    required this.detail,
    required this.done,
    this.warning = false,
  });

  final int step;
  final String title;
  final String detail;
  final bool done;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkbenchStepBadge(step: step, done: done),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodySemiBold, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                detail,
                style: AppTypography.caption.copyWith(
                  color: done ? AppColors.success : (warning ? AppColors.warning : AppColors.textSecondary),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
