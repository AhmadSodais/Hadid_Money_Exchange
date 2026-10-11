import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../application/legacy_migration_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../format/money_format.dart';
import '../session/app_session.dart';
import 'exchange_ui.dart';
import 'order_detail_info_card.dart';
import 'settings_kit.dart';

/// Settings card that analyzes and imports the legacy three-database data.
class LegacyImportCard extends StatefulWidget {
  const LegacyImportCard({super.key, this.metrics = SettingsMetrics.standard});

  final SettingsMetrics metrics;

  @override
  State<LegacyImportCard> createState() => _LegacyImportCardState();
}

class _LegacyImportCardState extends State<LegacyImportCard> with RevisionReload {
  String? _customersDb;
  String? _balanceDb;
  String? _removedDb;
  LegacyAnalysis? _analysis;
  bool _includeCash = true;
  bool _busy = false;
  List<Map<String, Object?>> _runs = const [];

  @override
  Future<void> reload() async {
    final runs = await session.services.legacy.runs();
    if (mounted) setState(() => _runs = runs);
  }

  Future<void> _pick(void Function(String) assign, String title) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: const ['db'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() {
      assign(path);
      _analysis = null;
    });
  }

  Future<void> _analyze() async {
    final customers = _customersDb;
    if (customers == null) {
      GfToast.error(context, 'فایل customers.db را انتخاب کنید.');
      return;
    }
    setState(() => _busy = true);
    final analysis = await runAction(
      context,
      () => session.services.legacy
          .analyzeFiles(customersDb: customers, balanceDb: _balanceDb, removedDb: _removedDb),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _analysis = analysis;
    });
  }

  Future<void> _import() async {
    final a = _analysis;
    if (a == null) return;
    final ok = await askReason(
      context,
      title: 'انتقال اطلاعات برنامه قبلی',
      message: 'برای ${a.customers.where((c) => !c.isWalkIn).length} مشتری حساب و بیلانس افتتاحیه ساخته می‌شود'
          '${_includeCash ? ' و موجودی نقد آخرین بیلانس روزانه ثبت می‌شود' : ''}. '
          'پیش از شروع، پشتیبان کامل گرفته می‌شود و در صورت هر خطا دفتر به همان وضعیت برمی‌گردد. '
          'برای ادامه، کلمه «انتقال» را بنویسید.',
      confirmLabel: 'انتقال',
    );
    if (ok == null || !mounted) return;
    if (ok.trim() != 'انتقال') {
      GfToast.warning(context, 'کلمه تأیید درست نیست؛ انتقال انجام نشد.');
      return;
    }
    setState(() => _busy = true);
    final s = context.read<AppSession>();
    final result = await runAction(context, () => s.services.legacy.import(a, s.actor, includeCash: _includeCash));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) _analysis = null;
    });
    if (result != null) {
      GfToast.success(context,
          'انتقال تأیید شد: ${result.customersCreated} مشتری، ${result.balancesPosted} مانده، ${result.cashPosted} موجودی نقد.');
    }
    reload();
  }

  Widget _fileField(String label, String? path, VoidCallback onPick, {VoidCallback? onClear, bool required = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: GfTextField(
                key: ValueKey(path),
                initialValue: path ?? '',
                hint: required ? 'انتخاب نشده (الزامی)' : 'انتخاب نشده (اختیاری)',
                readOnly: true,
                prefixIcon: Icons.storage_outlined,
                onTap: _busy ? null : onPick,
              ),
            ),
            if (path != null && onClear != null) ...[
              const SizedBox(width: 8),
              GfIconButton(icon: Icons.close, tooltip: 'حذف', size: 48, onPressed: _busy ? null : onClear),
            ],
            const SizedBox(width: 8),
            GfIconButton(icon: Icons.folder_open_outlined, tooltip: 'انتخاب فایل', size: 48, onPressed: _busy ? null : onPick),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final m = widget.metrics;
    final a = _analysis;
    final blocking = a?.blockingIssues(includeCash: _includeCash) ?? const [];
    return SettingsSectionCard(
      icon: Icons.move_down,
      title: 'انتقال از برنامه قبلی',
      padding: m.cardPadding,
      actions: [
        GfSecondaryButton(
          label: 'بررسی اطلاعات',
          icon: Icons.manage_search,
          isLoading: _busy && a == null,
          onPressed: _busy || _customersDb == null ? null : _analyze,
        ),
        if (a != null)
          GfPrimaryButton(
            label: 'انتقال به دفتر',
            icon: Icons.move_down,
            isLoading: _busy,
            onPressed: _busy || blocking.isNotEmpty ? null : _import,
          ),
      ],
      footer: const SettingsFooterNote(
        'فایل‌های برنامه قبلی فقط خوانده می‌شوند و هرگز تغییر نمی‌کنند. این فایل‌ها معمولاً در پوشه '
        '«.dart_tool\\sqflite_common_ffi\\databases» کنار برنامه قبلی قرار دارند. '
        'انتقال فقط روی دفتر خالی انجام می‌شود.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fileField(
            'مشتریان (customers.db)',
            _customersDb,
            () => _pick((v) => _customersDb = v, 'انتخاب customers.db'),
            required: true,
          ),
          SizedBox(height: m.fieldGap),
          SettingsFormRow(
            gap: m.fieldGap,
            left: _fileField(
              'بیلانس روزانه (balance.db)',
              _balanceDb,
              () => _pick((v) => _balanceDb = v, 'انتخاب balance.db'),
              onClear: () => setState(() {
                _balanceDb = null;
                _analysis = null;
              }),
            ),
            right: _fileField(
              'حذف‌شده‌ها (removed_data.db)',
              _removedDb,
              () => _pick((v) => _removedDb = v, 'انتخاب removed_data.db'),
              onClear: () => setState(() {
                _removedDb = null;
                _analysis = null;
              }),
            ),
          ),
          if (a != null) ...[
            SizedBox(height: m.gap),
            _AnalysisSummary(analysis: a, session: s, gap: m.fieldGap),
            SizedBox(height: m.fieldGap),
            GfToggleCard(
              label: 'ثبت موجودی نقد از آخرین بیلانس روزانه',
              subtitle: 'اگر خاموش باشد، سرمایه اولیه صندوق را بعداً دستی ثبت کنید.',
              value: _includeCash,
              onChanged: (v) {
                if (!_busy) setState(() => _includeCash = v);
              },
            ),
            if (blocking.isNotEmpty) ...[
              SizedBox(height: m.fieldGap),
              InfoBanner(
                '${blocking.length} مشکل مانع انتقال است؛ آن‌ها را در برنامه قبلی اصلاح و دوباره بررسی کنید.',
                tone: BannerTone.error,
              ),
            ],
          ],
          if (_runs.isNotEmpty) ...[
            SizedBox(height: m.gap),
            LedgerTable(
              shrinkWrap: true,
              title: 'سوابق انتقال',
              itemLabel: 'انتقال',
              columns: const [
                LedgerColumn.dateTime('زمان شروع'),
                LedgerColumn.status(),
              ],
              rows: [
                for (final r in _runs)
                  [
                    Text(DateFormatFa.dateTime(DateTime.parse(r['started_at'] as String))),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: switch (r['status']) {
                        'verified' => GfStatusBadge(label: 'تأییدشده', color: AppColors.success, compact: true),
                        'rolled_back' =>
                          GfStatusBadge(label: 'ناموفق، بازگردانده شد', color: AppColors.warning, compact: true),
                        'failed' => GfStatusBadge(label: 'ناموفق', color: AppColors.error, compact: true),
                        _ => GfStatusBadge(label: 'در حال اجرا', color: AppColors.info, compact: true),
                      },
                    ),
                  ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AnalysisSummary extends StatelessWidget {
  const _AnalysisSummary({required this.analysis, required this.session, required this.gap});

  final LegacyAnalysis analysis;
  final AppSession session;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final visible = [for (final i in a.issues) if (!i.code.startsWith('legacy.')) i]
      ..sort((x, y) => y.severity.index.compareTo(x.severity.index));
    final totals = a.customerTotals;
    String amount(String cur, int minor) {
      final c = session.currency(cur);
      return c == null ? '$minor $cur' : MoneyFormat.withName(minor, c);
    }

    int count(IssueSeverity s) => visible.where((i) => i.severity == s).length;
    final errors = count(IssueSeverity.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('منبع: ${a.sources.map(p.basename).join('، ')}', style: AppTypography.caption),
        SizedBox(height: gap),
        DialogResponsiveRow(
          gap: gap,
          breakpoint: 560,
          children: [
            DialogMetricBox(
              icon: Icons.people_outline,
              title: 'مشتریان',
              value: '${a.customers.where((c) => !c.isWalkIn).length}',
            ),
            DialogMetricBox(
              icon: Icons.inventory_2_outlined,
              title: 'ردیف‌های حذف‌شده (فقط بایگانی)',
              value: '${a.removedCount}',
            ),
            DialogMetricBox(
              icon: errors > 0 ? Icons.error_outline : Icons.check_circle_outline,
              title: 'مشکلات',
              value: '$errors خطا',
              valueColor: errors > 0 ? AppColors.error : AppColors.success,
              hint: '${count(IssueSeverity.warning)} هشدار، ${count(IssueSeverity.info)} اطلاع',
            ),
          ],
        ),
        if (totals.values.any((v) => v != 0) || a.cash.isNotEmpty) ...[
          SizedBox(height: gap),
          OrderDetailSummaryCard(
            rows: [
              for (final e in totals.entries)
                if (e.value != 0)
                  OrderDetailSummaryRow(
                    label: 'جمع مانده مشتریان ${e.key}',
                    value: MoneyFormat.position(e.value, session.currency(e.key)!),
                    dense: true,
                    ltrValue: true,
                  ),
              for (final c in a.cash.values)
                OrderDetailSummaryRow(
                  label: 'موجودی نقد ${c.currency} (${c.legacyDate})',
                  value: amount(c.currency, c.amountMinor),
                  dense: true,
                  ltrValue: true,
                ),
            ],
          ),
        ],
        if (visible.isNotEmpty) ...[
          SizedBox(height: gap),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final i = visible[index];
                return InfoBanner(
                  i.message,
                  tone: switch (i.severity) {
                    IssueSeverity.error => BannerTone.error,
                    IssueSeverity.warning => BannerTone.warning,
                    IssueSeverity.info => BannerTone.info,
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
