// ignore_for_file: unused_local_variable

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/read_models.dart';
import '../../application/reconciliation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_calendar.dart';
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

/// How far back the "missed days" panel looks.
const int _missingLookbackDays = 30;

/// Missed days shown before the rest are summarized.
const int _missingShown = 8;

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

  /// Has cash, movement or a count on this day; other currencies are counted
  /// through «افزودن بیلانس».
  bool get relevant =>
      record != null || snapshot.openingMinor != 0 || snapshot.inflowMinor != 0 || snapshot.outflowMinor != 0;
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
    final today = BusinessDate.today();
    _date = date.isAfter(today) ? today : date;
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
          'یک سند اصلاح صندوق به مبلغ ${MoneyFormat.withName(rec.differenceMinor.abs(), c)} '
          '(${rec.differenceMinor > 0 ? 'اضافه' : 'کسری'}) با تاریخ ${DateFormatFa.business(rec.businessDate)} ثبت می‌شود '
          'تا موجودی دفتر با پول شمارش‌شده برابر شود.',
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
      message: 'با بازگشایی، ثبت، ویرایش و حذف معاملات این تاریخ دوباره ممکن می‌شود.',
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

  static String _actionLabel(_Action a) => switch (a) {
    _Action.count => 'ثبت بیلانس',
    _Action.recount => 'شمارش مجدد',
    _Action.edit => 'ویرایش',
    _Action.remove => 'حذف شمارش',
    _Action.adjust => 'اصلاح اختلاف',
    _Action.close => 'بستن روز',
    _Action.reopen => 'بازگشایی روز',
  };

  static IconData _actionIcon(_Action a) => switch (a) {
    _Action.count => Icons.add_rounded,
    _Action.recount || _Action.edit => Icons.edit_outlined,
    _Action.remove => Icons.delete_outline_rounded,
    _Action.adjust => Icons.tune,
    _Action.close => Icons.lock_outline,
    _Action.reopen => Icons.lock_open,
  };

  static String _statusLabel(ReconciliationRecord? rec) {
    if (rec == null) return 'ثبت نشده';
    if (rec.status == 'closed') return 'بسته شد';
    if (rec.adjustmentTransactionId != null) return 'اختلاف اصلاح شد';
    return rec.differenceMinor == 0 ? 'برابر — آماده بستن' : 'دارای اختلاف';
  }

  static Color _statusColor(ReconciliationRecord? rec) {
    if (rec == null) return AppColors.textMuted;
    if (rec.status == 'closed') return AppColors.success;
    if (rec.adjustmentTransactionId != null || rec.differenceMinor == 0) return AppColors.info;
    return AppColors.warning;
  }

  String _longDate(BusinessDate d) => '${AppCalendar.weekdayName(d.toDateTime())} ${DateFormatFa.business(d)}';

  // ------------------------------------------------------------ header card

  Widget _header(SettingsMetrics m, List<_Row> relevant) {
    final today = BusinessDate.today();
    final total = relevant.length;
    final counted = relevant.where((r) => r.record != null && !r.stale).length;
    final pending = relevant.where((r) => r.pendingDifference || r.stale).length;
    final closed = relevant.where((r) => r.closed).length;
    final allClosed = total > 0 && closed == total;

    final (statusText, statusColor) = total == 0
        ? ('بدون موجودی', AppColors.textMuted)
        : allClosed
        ? ('روز بسته شد', AppColors.success)
        : counted == 0
        ? ('شمارش نشده', AppColors.warning)
        : ('در حال انجام', AppColors.info);

    final dateNav = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GfIconButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'روز قبل',
          onPressed: () => _goToDate(_date.addDays(-1)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: BusinessDateField(label: 'تاریخ بیلانس', value: _date, onChanged: _goToDate),
        ),
        const SizedBox(width: 8),
        GfIconButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'روز بعد',
          onPressed: _date.isBefore(today) ? () => _goToDate(_date.addDays(1)) : null,
        ),
        if (_date != today) ...[
          const SizedBox(width: 8),
          GfSecondaryButton(label: 'امروز', icon: Icons.today_outlined, onPressed: () => _goToDate(today)),
        ],
      ],
    );

    final drawer = DrawerPicker(
      value: _drawerId,
      onChanged: (id) {
        _drawerId = id;
        context.read<AppSettingsProvider>().setSelectedDrawerId(id);
        reload();
      },
    );

    final progress = total == 0
        ? null
        : 'شمارش: $counted از $total  ·  بسته: $closed از $total${pending > 0 ? '  ·  نیاز به رسیدگی: $pending' : ''}';

    return GfCard(
      padding: EdgeInsets.all(m.cardPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pickers = constraints.maxWidth >= 680
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(width: 220, child: drawer),
                    SizedBox(width: m.fieldGap),
                    SizedBox(width: 420, child: dateNav),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    drawer,
                    SizedBox(height: m.fieldGap),
                    dateNav,
                  ],
                );
          final status = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // GfStatusBadge(label: statusText, color: statusColor),
              // if (progress != null) ...[
              //   const SizedBox(width: 10),
              //   Flexible(
              //     child: Text(
              //       progress,
              //       maxLines: 1,
              //       overflow: TextOverflow.ellipsis,
              //       style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              //     ),
              //   ),
              // ],
            ],
          );
          if (constraints.maxWidth < 1000) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pickers,
                SizedBox(height: m.fieldGap),
                status,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              pickers,
              SizedBox(width: m.gap),
              Expanded(child: Align(alignment: AlignmentDirectional.centerEnd, child: status)),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------- balance table

  Widget _balanceTable(List<_Row> relevant, bool canAdjust, bool canReopen, bool canCount) {
    Widget plain(int minor, Currency c, {String sign = '', Color? color}) => Text(
      minor == 0 ? '—' : '$sign${MoneyFormat.amount(minor, c)}',
      textDirection: TextDirection.ltr,
      style: AppTypography.body.copyWith(
        color: minor == 0 ? AppColors.textMuted : (color ?? AppColors.textPrimary),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final dash = Text('—', style: AppTypography.body.copyWith(color: AppColors.textMuted));

    // Narrow windows drop the day's movement so the actions stay on screen.
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth >= 1100;
        return LedgerTable(
          shrinkWrap: true,
          showRowNumbers: false,
          title: 'موجودی صندوق به تفکیک ارز',
          minWidth: full ? 1100 : 760,
          emptyText: 'در این روز هیچ ارزی موجودی یا معامله ندارد.',
          emptyHint: 'برای ثبت شمارش، «افزودن بیلانس» را بزنید.',
          columns: [
            const LedgerColumn.primary('ارز'),
            if (full) ...const [
              LedgerColumn.amount('اول روز'),
              LedgerColumn.amount('دریافت'),
              LedgerColumn.amount('پرداخت'),
            ],
            const LedgerColumn.amount('باید باشد'),
            const LedgerColumn.amount('شمارش‌شده'),
            const LedgerColumn.amount('اختلاف'),
            const LedgerColumn.status(),
            const LedgerColumn.actions(width: 170),
          ],
          rows: [
            for (final r in relevant)
              () {
                final c = r.currency;
                final rec = r.record;
                return <Widget>[
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: c.nameFa, style: AppTypography.bodySemiBold),
                        TextSpan(
                          text: '  ${c.code}',
                          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (full) ...[
                    AmountText(r.snapshot.openingMinor, c),
                    plain(r.snapshot.inflowMinor, c, sign: '+', color: AppColors.success),
                    plain(r.snapshot.outflowMinor, c, sign: '-', color: AppColors.error),
                  ],
                  AmountText(r.snapshot.expectedMinor, c, bold: true),
                  rec == null ? dash : AmountText(rec.countedMinor, c, bold: true),
                  rec == null || r.stale ? dash : _DifferenceText(rec.differenceMinor, c),
                  GfStatusBadge(
                    label: r.stale ? 'شمارش مجدد لازم است' : _statusLabel(rec),
                    color: r.stale ? AppColors.warning : _statusColor(rec),
                    compact: true,
                  ),
                  _RowActions(
                    actions: _actionsFor(r, canAdjust, canReopen),
                    canCount: canCount,
                    onAction: (a) => _run(a, r),
                  ),
                ];
              }(),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------ missed days

  Widget _missedDays(AppSession s) {
    final byDate = <BusinessDate, List<String>>{};
    for (final x in _missing) {
      (byDate[x.date] ??= []).add(x.currency);
    }
    final dates = byDate.keys.toList();
    final shown = dates.take(_missingShown).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy_outlined, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text('بیلانس ${dates.length} روز ثبت نشده:', style: AppTypography.bodySemiBold),
            ],
          ),
          for (final d in shown)
            ActionChip(
              label: Text(DateFormatFa.business(d), style: AppTypography.caption),
              tooltip:
                  '${_longDate(d)} — ${[for (final code in byDate[d]!) s.currency(code)?.nameFa ?? code].join('، ')}',
              onPressed: () => _goToDate(d),
              backgroundColor: AppColors.card,
              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.4)),
              visualDensity: VisualDensity.compact,
            ),
          if (dates.length > shown.length)
            Text(
              'و ${dates.length - shown.length} روز دیگر',
              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- history

  Widget _historyTable(AppSession s) {
    return SizedBox(
      height: 520,
      child: LedgerTable(
        title: 'سابقه بیلانس‌ها',
        subtitle: 'روی هر ردیف بزنید تا همان روز باز شود.',
        minWidth: 900,
        itemLabel: 'بیلانس',
        emptyText: 'هنوز بیلانسی ثبت نشده است.',
        onTapRow: (i) => _goToDate(_history[i].businessDate),
        columns: const [
          LedgerColumn.date(),
          LedgerColumn.text('ارز'),
          LedgerColumn.amount('باید باشد'),
          LedgerColumn.amount('شمارش‌شده'),
          LedgerColumn.amount('اختلاف'),
          LedgerColumn.status(),
        ],
        rows: [
          for (final h in _history)
            [
              Tooltip(
                message: _longDate(h.businessDate),
                child: Text(DateFormatFa.business(h.businessDate), style: AppTypography.body),
              ),
              Text(s.currency(h.currency)?.nameFa ?? h.currency, style: AppTypography.bodyMedium),
              AmountText(h.expectedMinor, s.currency(h.currency)),
              AmountText(h.countedMinor, s.currency(h.currency), bold: true),
              _DifferenceText(h.differenceMinor, s.currency(h.currency)),
              GfStatusBadge(label: _statusLabel(h), color: _statusColor(h), compact: true),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canReopen = s.can(Permissions.reconciliationReopen);
    final canAdjust = s.can(Permissions.adjustmentsPost);
    final canCount = s.can(Permissions.reconciliationPerform);
    final relevant = _rows.where((r) => r.relevant).toList();
    return PageScaffold(
      title: 'بیلانس روزانه صندوق',
      subtitle: 'شمارش پول نقد هر ارز در پایان روز، مقایسه با دفتر و بستن روز',
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
                    _header(m, relevant),
                    if (_missing.isNotEmpty) ...[SizedBox(height: m.fieldGap), _missedDays(s)],
                    SizedBox(height: m.gap),
                    _balanceTable(relevant, canAdjust, canReopen, canCount),
                    SizedBox(height: m.gap),
                    _historyTable(s),
                  ],
                );
              },
            ),
    );
  }
}

// ----------------------------------------------------------------- widgets

/// The next step as one compact button; the remaining actions in a menu.
class _RowActions extends StatelessWidget {
  const _RowActions({required this.actions, required this.canCount, required this.onAction});

  final List<_Action> actions;
  final bool canCount;
  final ValueChanged<_Action> onAction;

  bool _allowed(_Action a) => canCount || a == _Action.reopen || a == _Action.adjust;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final main = actions.first;
    final label = _ReconciliationPageState._actionLabel(main);
    final icon = _ReconciliationPageState._actionIcon(main);
    final onPressed = _allowed(main) ? () => onAction(main) : null;
    final rest = actions.skip(1).where(_allowed).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: main == _Action.reopen
              ? GfSecondaryButton(label: label, icon: icon, compact: true, onPressed: onPressed)
              : GfPrimaryButton(label: label, icon: icon, compact: true, onPressed: onPressed),
        ),
        if (rest.isNotEmpty)
          LedgerRowMenu(
            items: [
              for (final a in rest)
                PopupMenuItem(
                  value: a.name,
                  child: Row(
                    children: [
                      Icon(
                        _ReconciliationPageState._actionIcon(a),
                        size: 18,
                        color: a == _Action.remove ? AppColors.error : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _ReconciliationPageState._actionLabel(a),
                        style: AppTypography.body.copyWith(color: a == _Action.remove ? AppColors.error : null),
                      ),
                    ],
                  ),
                ),
            ],
            onSelected: (name) => onAction(_Action.values.byName(name)),
          ),
      ],
    );
  }
}

class _DifferenceText extends StatelessWidget {
  const _DifferenceText(this.minor, this.currency);

  final int minor;
  final Currency? currency;

  @override
  Widget build(BuildContext context) {
    if (minor == 0) {
      return Text('برابر', style: AppTypography.body.copyWith(color: AppColors.success));
    }
    final color = minor > 0 ? AppColors.warning : AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(minor > 0 ? 'اضافه' : 'کسری', style: AppTypography.caption.copyWith(color: color)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            MoneyFormat.amount(minor.abs(), currency),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySemiBold.copyWith(
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
