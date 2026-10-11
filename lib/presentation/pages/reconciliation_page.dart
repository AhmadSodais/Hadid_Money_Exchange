import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../application/read_models.dart';
import '../../application/reconciliation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/security/permissions.dart';
import '../../domain/shared/business_date.dart';
import '../format/money_format.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/settings_kit.dart';
import '../widgets/workbench_kit.dart';

/// اخذ بیلانس روزانه. Expected = opening + inflows − outflows (from the
/// ledger); difference = counted − expected. A count never changes the
/// ledger; a difference is corrected only by an authorized adjustment.
class ReconciliationPage extends StatefulWidget {
  const ReconciliationPage({super.key});

  @override
  State<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _Row {
  _Row(this.currency, this.snapshot, this.record);

  final Currency currency;
  final ReconciliationSnapshot snapshot;
  final ReconciliationRecord? record;
  final TextEditingController counted = TextEditingController();

  bool get closed => record?.status == 'closed';

  /// Counted after transactions were posted for the day: must be recounted.
  bool get stale {
    final rec = record;
    return rec != null && !closed && rec.adjustmentTransactionId == null && rec.expectedMinor != snapshot.expectedMinor;
  }

  bool get pendingDifference {
    final rec = record;
    return rec != null && !closed && rec.differenceMinor != 0 && rec.adjustmentTransactionId == null;
  }

  int? get typedMinor {
    if (counted.text.trim().isEmpty) return null;
    final minor = MoneyFormat.tryParse(counted.text, currency);
    return minor == null || minor < 0 ? null : minor;
  }

  /// The typed value is new or differs from the saved count.
  bool get unsaved {
    final typed = typedMinor;
    return typed != null && typed != record?.countedMinor;
  }
}

enum _Action { save, adjust, close, reopen }

class _ReconciliationPageState extends State<ReconciliationPage> with RevisionReload {
  int? _drawerId;
  BusinessDate _date = BusinessDate.today();
  bool _loading = true;
  List<_Row> _rows = const [];
  List<ReconciliationRecord> _history = const [];

  @override
  void dispose() {
    for (final r in _rows) {
      r.counted.dispose();
    }
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
    if (drawer == null) return;
    final svc = s.services.reconciliation;
    final rows = <_Row>[];
    for (final c in s.activeCurrencies) {
      final snap = await svc.compute(drawer, c.code, _date);
      final rec = await svc.active(drawer, c.code, _date);
      final row = _Row(c, snap, rec);
      if (rec != null) row.counted.text = MoneyFormat.editable(rec.countedMinor, c);
      rows.add(row);
    }
    final history = await svc.records(drawerId: drawer);
    if (!mounted) return;
    for (final r in _rows) {
      r.counted.dispose();
    }
    setState(() {
      _rows = rows;
      _history = history.take(60).toList();
      _loading = false;
    });
  }

  Future<void> _saveCount(_Row r) async {
    final minor = r.typedMinor;
    if (minor == null) {
      GfToast.error(context, 'مقدار شمارش‌شده معتبر نیست.');
      return;
    }
    final s = context.read<AppSession>();
    await runAction(
      context,
      () => s.services.reconciliation.saveCount(
        drawerId: _drawerId!,
        currency: r.currency.code,
        date: _date,
        countedMinor: minor,
        actor: s.actor,
      ),
      success: 'شمارش ${r.currency.nameFa} ثبت شد.',
    );
  }

  Future<void> _adjust(ReconciliationRecord rec, Currency c) async {
    final reason = await askReason(
      context,
      title: 'اصلاح اختلاف ${c.nameFa}',
      message: 'یک سند اصلاح صندوق به مبلغ ${MoneyFormat.withName(rec.differenceMinor, c)} '
          '(${rec.differenceMinor > 0 ? 'اضافه' : 'کسری'}) با تاریخ ${DateFormatFa.business(rec.businessDate)} ثبت می‌شود.',
      confirmLabel: 'ثبت اصلاح',
    );
    if (reason == null || !mounted) return;
    final s = context.read<AppSession>();
    await runAction(context, () => s.services.reconciliation.postAdjustment(rec.id, reason, s.actor),
        success: 'اصلاح صندوق ثبت شد.');
  }

  Future<void> _close(ReconciliationRecord rec) async {
    final s = context.read<AppSession>();
    await runAction(context, () => s.services.reconciliation.close(rec.id, s.actor),
        success: 'بیلانس روز بسته شد؛ ثبت معامله با این تاریخ برای این ارز قفل است.');
  }

  Future<void> _reopen(ReconciliationRecord rec) async {
    final reason = await askReason(
      context,
      title: 'بازگشایی روز بسته‌شده',
      message: 'با بازگشایی، ثبت و برگشت معاملات این تاریخ دوباره ممکن می‌شود. دلیل در سوابق ممیزی ثبت می‌شود.',
      confirmLabel: 'بازگشایی',
    );
    if (reason == null || !mounted) return;
    final s = context.read<AppSession>();
    await runAction(context, () => s.services.reconciliation.reopen(rec.id, reason, s.actor),
        success: 'روز بازگشایی شد.');
  }

  void _run(_Action action, _Row r) {
    switch (action) {
      case _Action.save:
        _saveCount(r);
      case _Action.adjust:
        _adjust(r.record!, r.currency);
      case _Action.close:
        _close(r.record!);
      case _Action.reopen:
        _reopen(r.record!);
    }
  }

  String _statusLabel(ReconciliationRecord? rec) {
    if (rec == null) return 'شمارش نشده';
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
        title: 'شمارش نقد هر ارز',
        detail: stale > 0 ? '$counted از $total ارز — $stale ارز نیاز به شمارش مجدد' : '$counted از $total ارز شمارش شده',
        done: total > 0 && counted == total,
      ),
      _StepItem(
        step: 2,
        title: 'اصلاح اختلاف‌ها (در صورت نیاز)',
        detail: pending == 0 ? 'اختلاف اصلاح‌نشده‌ای نیست' : '$pending ارز دارای اختلاف اصلاح‌نشده',
        done: total > 0 && counted == total && pending == 0,
        warning: pending > 0,
      ),
      _StepItem(
        step: 3,
        title: 'بستن روز',
        detail: '$closed از $total ارز بسته شده',
        done: allClosed,
      ),
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
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) SizedBox(height: m.fieldGap),
                      steps[i],
                    ],
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
              children: [pickers, SizedBox(height: m.gap), stepper],
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
      minWidth: 1080,
      title: 'برگه شمارش صندوق — ${DateFormatFa.business(_date)}',
      subtitle: 'مورد انتظار = مانده اول روز + ورودی − خروجی · اختلاف = شمارش − مورد انتظار. '
          'مبلغ شمارش‌شده را وارد کنید؛ اختلاف همان لحظه محاسبه می‌شود.',
      emptyText: 'ارز فعالی برای این صندوق وجود ندارد.',
      columns: const [
        LedgerColumn('ارز', flex: 2),
        LedgerColumn('مانده اول روز', flex: 2, numeric: true),
        LedgerColumn('ورودی', flex: 2, numeric: true),
        LedgerColumn('خروجی', flex: 2, numeric: true),
        LedgerColumn('مورد انتظار', flex: 2, numeric: true),
        LedgerColumn('شمارش فزیکی', width: 176),
        LedgerColumn('اختلاف', flex: 2, numeric: true),
        LedgerColumn('وضعیت', width: 150),
        LedgerColumn('', width: 196),
      ],
      rows: [for (final r in _rows) _sheetRow(r, canAdjust, canReopen)],
    );
  }

  List<Widget> _sheetRow(_Row r, bool canAdjust, bool canReopen) {
    final c = r.currency;
    final snap = r.snapshot;
    final rec = r.record;
    final typed = r.typedMinor;
    final diff = typed == null ? null : typed - snap.expectedMinor;

    final actions = <_Action>[
      if (!r.closed && (r.unsaved || r.stale || rec == null)) _Action.save,
      if (r.pendingDifference && canAdjust && !r.unsaved) _Action.adjust,
      if (rec != null && !r.closed && !r.stale && !r.unsaved) _Action.close,
      if (r.closed && canReopen) _Action.reopen,
    ];
    final primary = actions.isEmpty ? null : actions.first;
    String label(_Action a) => switch (a) {
          _Action.save => 'ثبت شمارش',
          _Action.adjust => 'اصلاح اختلاف',
          _Action.close => 'بستن روز',
          _Action.reopen => 'بازگشایی',
        };
    IconData icon(_Action a) => switch (a) {
          _Action.save => Icons.save_outlined,
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
      AmountText(snap.inflowMinor, c),
      AmountText(snap.outflowMinor, c),
      AmountText(snap.expectedMinor, c, bold: true),
      r.closed
          ? AmountText(rec!.countedMinor, c, bold: true)
          : SizedBox(
              width: 160,
              child: GfTextField(
                controller: r.counted,
                hint: '0',
                textAlign: TextAlign.end,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp('-')),
                  const ThousandsSeparatorInputFormatter(),
                ],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _saveCount(r),
              ),
            ),
      diff == null
          ? Text('—', style: AppTypography.body.copyWith(color: AppColors.textMuted))
          : AmountText(diff, c, signColor: true, bold: true),
      r.stale
          ? Tooltip(
              message: 'پس از شمارش، معاملات جدید ثبت شده است؛ دوباره شمارش کنید.',
              child: GfStatusBadge(label: 'شمارش مجدد', color: AppColors.warning, compact: true),
            )
          : GfStatusBadge(label: _statusLabel(rec), color: _statusColor(rec), compact: true),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (primary == null)
            Text('—', style: AppTypography.body.copyWith(color: AppColors.textMuted))
          else if (primary == _Action.reopen)
            GfDangerButton(label: label(primary), icon: icon(primary), compact: true, onPressed: () => _run(primary, r))
          else if (primary == _Action.save)
            GfPrimaryButton(
              label: label(primary),
              icon: icon(primary),
              compact: true,
              onPressed: typed == null ? null : () => _run(primary, r),
            )
          else
            GfSecondaryButton(label: label(primary), icon: icon(primary), compact: true, onPressed: () => _run(primary, r)),
          if (actions.length > 1)
            LedgerRowMenu(
              onSelected: (v) => _run(_Action.values.byName(v), r),
              items: [
                for (final a in actions.skip(1))
                  gfPopupMenuItem(value: a.name, label: label(a), danger: a == _Action.reopen),
              ],
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canReopen = s.can(Permissions.reconciliationReopen);
    final canAdjust = s.can(Permissions.adjustmentsPost);
    return PageScaffold(
      title: 'بیلانس روزانه صندوق',
      subtitle: 'شمارش نقد پایان روز، مقایسه با دفتر و بستن روز',
      body: _loading
          ? const GfPageLoader()
          : LayoutBuilder(
              builder: (context, constraints) {
                final m = SettingsMetrics.of(constraints.maxWidth);
                return ListView(
                  children: [
                    _header(m),
                    SizedBox(height: m.gap),
                    _countSheet(canAdjust, canReopen),
                    SizedBox(height: m.gap),
                    SizedBox(
                      height: 460,
                      child: LedgerTable(
                        title: 'سابقه بیلانس‌ها',
                        subtitle: 'آخرین ۶۰ شمارش این صندوق',
                        minWidth: 860,
                        itemLabel: 'بیلانس',
                        emptyText: 'هنوز بیلانسی ثبت نشده است.',
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
