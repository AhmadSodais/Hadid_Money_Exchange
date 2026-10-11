import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../application/audit_writer.dart';
import '../../application/posting_service.dart';
import '../../application/read_models.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_font.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_calendar.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/money/currency.dart';
import '../../domain/money/decimal.dart';
import '../../domain/security/permissions.dart';
import '../../domain/shared/business_date.dart';
import '../../domain/transactions/financial_command.dart';
import '../../infrastructure/backup/backup_service.dart';
import '../format/money_format.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';
import '../widgets/app_lock_settings_card.dart';
import '../widgets/app_shell.dart';
import '../widgets/exchange_ui.dart';
import '../widgets/legacy_import_card.dart';
import '../widgets/order_detail_info_card.dart';
import '../widgets/settings_kit.dart';

part 'settings_about_section.dart';

enum _Section { policies, openingCash, currencies, appLock, backup, legacyImport, audit, appearance, about }

Future<void> _openPath(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.start('explorer', [path]);
    } else {
      await Process.start('xdg-open', [path]);
    }
  } catch (_) {}
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _nav = <SettingsNavEntry<_Section>>[
    SettingsNavEntry(_Section.policies, Icons.tune_outlined, 'سیاست‌های ثبت'),
    SettingsNavEntry(_Section.openingCash, Icons.account_balance_wallet_outlined, 'سرمایه اولیه صندوق'),
    SettingsNavEntry(_Section.currencies, Icons.currency_exchange, 'ارزها'),
    SettingsNavEntry(_Section.appLock, Icons.lock_outline, 'امنیت برنامه'),
    SettingsNavEntry(_Section.backup, Icons.folder_outlined, 'پشتیبان‌گیری و بازیابی'),
    SettingsNavEntry(_Section.legacyImport, Icons.move_down, 'انتقال از برنامه قبلی'),
    SettingsNavEntry(_Section.audit, Icons.fact_check_outlined, 'سوابق ممیزی و صحت دفاتر'),
    SettingsNavEntry(_Section.appearance, Icons.palette_outlined, 'ظاهر و تقویم'),
    SettingsNavEntry(_Section.about, Icons.info_outline, 'درباره و مجوز'),
  ];

  final _search = TextEditingController();
  _Section? _selected;
  String _query = '';
  List<SettingsNavEntry<_Section>> _items = _nav;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _visible(AppSession s, _Section section) => switch (section) {
        _Section.policies => s.can(Permissions.settingsManage),
        _Section.openingCash => s.can(Permissions.openingBalancesPost),
        _Section.legacyImport => s.can(Permissions.openingBalancesPost) && s.can(Permissions.backupRestore),
        _Section.audit => s.can(Permissions.auditView),
        _ => true,
      };

  bool _matches(SettingsNavEntry<_Section> item) =>
      _query.isEmpty || item.label.toLowerCase().contains(_query.toLowerCase());

  void _onSearch(String value) {
    setState(() => _query = value.trim());
    final current = _items.where((n) => n.section == _selected);
    if (_query.isNotEmpty && (current.isEmpty || !_matches(current.first))) {
      for (final item in _items) {
        if (_matches(item)) {
          setState(() => _selected = item.section);
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    _items = _nav.where((n) => _visible(s, n.section)).toList();
    final selected = _items.any((n) => n.section == _selected) ? _selected! : _items.first.section;

    return PageScaffold(
      title: 'تنظیمات',
      subtitle: 'سیاست‌های ثبت، ارزها، امنیت، پشتیبان‌گیری و ظاهر برنامه',
      searchController: _search,
      searchHint: 'جستجو در تنظیمات...',
      onSearch: _onSearch,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = SettingsMetrics.of(constraints.maxWidth);
          final nav = SettingsNav<_Section>(
            title: 'بخش‌های تنظیمات',
            items: _items,
            selected: selected,
            query: _query,
            onSelected: (section) => setState(() => _selected = section),
          );
          final content = _SettingsContent(selected: selected, metrics: metrics);
          if (metrics.stackNav) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 160, child: nav),
                SizedBox(height: metrics.gap),
                Expanded(child: content),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: metrics.navWidth, child: nav),
              SizedBox(width: metrics.gap),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.selected, required this.metrics});

  final _Section selected;
  final SettingsMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final sections = switch (selected) {
      _Section.policies => [_PoliciesCard(metrics: metrics)],
      _Section.openingCash => [_OpeningCashCard(metrics: metrics)],
      _Section.currencies => [const SizedBox(height: 560, child: _CurrenciesTable())],
      _Section.appLock => [AppLockSettingsCard(padding: metrics.cardPadding)],
      _Section.backup => [
          _BackupCard(metrics: metrics),
          if (s.can(Permissions.settingsManage)) _AutoBackupCard(metrics: metrics),
          const SizedBox(height: 460, child: _BackupHistoryTable()),
        ],
      _Section.legacyImport => [LegacyImportCard(metrics: metrics)],
      _Section.audit => [
          _IntegrityCard(metrics: metrics),
          const SizedBox(height: 560, child: _AuditTable()),
        ],
      _Section.appearance => [_AppearanceCard(metrics: metrics)],
      _Section.about => [_LicenseCard(metrics: metrics), _AboutCard(metrics: metrics)],
    };

    return ListView.separated(
      key: ValueKey(selected),
      itemCount: sections.length,
      separatorBuilder: (_, _) => SizedBox(height: metrics.gap),
      itemBuilder: (context, i) => sections[i],
    );
  }
}

// --------------------------------------------------------------- policies

class _PoliciesCard extends StatefulWidget {
  const _PoliciesCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_PoliciesCard> createState() => _PoliciesCardState();
}

class _PoliciesCardState extends State<_PoliciesCard> with RevisionReload {
  final _name = TextEditingController();
  final _backdate = TextEditingController();
  bool _allowNegative = false;
  bool _lockReconciled = true;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _backdate.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final c = session.services.catalog;
    final name = await c.setting('business.name');
    final back = await c.setting('posting.max_backdate_days');
    final neg = await c.setting('posting.allow_negative_cash');
    final lock = await c.setting('posting.lock_reconciled_days');
    if (!mounted) return;
    setState(() {
      _name.text = name ?? '';
      _backdate.text = back ?? '31';
      _allowNegative = neg == '1';
      _lockReconciled = lock != '0';
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final days = int.tryParse(Decimal.normalizeDigits(_backdate.text.trim()));
    if (days == null || days < 0 || days > 3650) {
      GfToast.error(context, 'تعداد روزهای مجاز ثبت گذشته باید عددی بین ۰ و ۳۶۵۰ باشد.');
      return;
    }
    final s = context.read<AppSession>();
    final c = s.services.catalog;
    setState(() => _saving = true);
    await runAction(context, () async {
      await c.putSetting('business.name', _name.text.trim(), s.actor);
      await c.putSetting('posting.max_backdate_days', '$days', s.actor);
      await c.putSetting('posting.allow_negative_cash', _allowNegative ? '1' : '0', s.actor);
      await c.putSetting('posting.lock_reconciled_days', _lockReconciled ? '1' : '0', s.actor);
    }, success: 'تنظیمات ذخیره شد.');
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    return SettingsSectionCard(
      icon: Icons.tune_outlined,
      title: 'سیاست‌های ثبت',
      padding: m.cardPadding,
      footer: Text(
        'این سیاست‌ها روی همه کاربران و همه صندوق‌ها اعمال می‌شود و هر تغییر در سوابق ممیزی ثبت می‌شود.',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        GfSecondaryButton(label: 'انصراف', icon: Icons.close, onPressed: _saving ? null : reload),
        GfPrimaryButton(
          label: 'ذخیره تغییرات',
          icon: Icons.save_outlined,
          isLoading: _saving,
          onPressed: _loaded && !_saving ? _save : null,
        ),
      ],
      child: !_loaded
          ? const SizedBox(height: 120, child: GfPageLoader())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsFormRow(
                  gap: m.fieldGap,
                  left: GfTextField(label: 'نام صرافی', prefixIcon: Icons.storefront_outlined, controller: _name),
                  right: GfTextField(
                    label: 'حداکثر روزهای ثبت با تاریخ گذشته',
                    hint: '۰ = بدون محدودیت',
                    prefixIcon: Icons.history,
                    controller: _backdate,
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(height: m.fieldGap),
                SettingsFormRow(
                  gap: m.fieldGap,
                  left: GfToggleCard(
                    label: 'اجازه منفی شدن موجودی نقد صندوق',
                    subtitle: 'پیش‌فرض خاموش: پرداخت بیش از موجودی صندوق رد می‌شود.',
                    value: _allowNegative,
                    onChanged: (v) => setState(() => _allowNegative = v),
                  ),
                  right: GfToggleCard(
                    label: 'قفل روزهای بسته‌شده',
                    subtitle: 'پس از بستن بیلانس، ثبت یا برگشت با آن تاریخ یا قبل از آن برای همان صندوق و ارز مجاز نیست.',
                    value: _lockReconciled,
                    onChanged: (v) => setState(() => _lockReconciled = v),
                  ),
                ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------ opening cash

class _OpeningCashCard extends StatefulWidget {
  const _OpeningCashCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_OpeningCashCard> createState() => _OpeningCashCardState();
}

class _OpeningCashCardState extends State<_OpeningCashCard> {
  final _amount = TextEditingController();
  int? _drawerId;
  Currency? _currency;
  BusinessDate _date = BusinessDate.today();
  String _key = PostingService.newIdempotencyKey();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final s = context.read<AppSession>();
    final drawer = _drawerId ?? (s.activeDrawers.isEmpty ? null : s.activeDrawers.first.id);
    final c = _currency;
    if (drawer == null || c == null) {
      GfToast.error(context, 'صندوق و ارز را انتخاب کنید.');
      return;
    }
    final minor = MoneyFormat.tryParse(_amount.text, c);
    if (minor == null || minor <= 0) {
      GfToast.error(context, 'مبلغ معتبر نیست.');
      return;
    }
    setState(() => _saving = true);
    final posted = await runAction(
      context,
      () => s.services.posting.post(
        OpeningCashCommand(
          idempotencyKey: _key,
          effectiveDate: _date,
          drawerId: drawer,
          currency: c.code,
          amountMinor: minor,
          description: 'سرمایه اولیه ${c.nameFa}',
        ),
        s.actor,
      ),
      success: 'سرمایه اولیه ${c.nameFa} ثبت شد.',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (posted != null) {
        _key = PostingService.newIdempotencyKey();
        _amount.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final m = widget.metrics;
    return SettingsSectionCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'سرمایه اولیه صندوق',
      padding: m.cardPadding,
      footer: const SettingsFooterNote(
        'سرمایه اولیه هر ارز برای هر صندوق فقط یک بار ثبت می‌شود و پس از آن موجودی فقط از معاملات محاسبه می‌شود. '
        'برای اصلاح، سند سرمایه اولیه را از روزنامچه برگشت کنید و دوباره ثبت کنید.',
      ),
      actions: [
        GfPrimaryButton(
          label: 'ثبت سرمایه اولیه',
          icon: Icons.account_balance_wallet_outlined,
          isLoading: _saving,
          onPressed: _saving ? null : _post,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsFormRow(
            gap: m.fieldGap,
            left: DrawerPicker(
              value: _drawerId ?? (s.activeDrawers.isEmpty ? null : s.activeDrawers.first.id),
              onChanged: (id) => setState(() => _drawerId = id),
            ),
            right: CurrencyPicker(value: _currency, onChanged: (c) => setState(() => _currency = c)),
          ),
          SizedBox(height: m.fieldGap),
          SettingsFormRow(
            gap: m.fieldGap,
            left: AmountField(controller: _amount, label: 'مبلغ ${_currency?.nameFa ?? ''}'),
            right: BusinessDateField(value: _date, onChanged: (d) => setState(() => _date = d)),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- currencies

class _CurrenciesTable extends StatelessWidget {
  const _CurrenciesTable();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canManage = s.can(Permissions.settingsManage);
    final list = s.currencies.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return LedgerTable(
      title: 'ارزها',
      subtitle: 'IRT = تومان ایران (۱ تومان = ۱۰ ریال) و با ریال (IRR) یکی نیست. '
          'تعداد اعشار ارزی که در آن سند ثبت شده قابل تغییر نیست.',
      itemLabel: 'ارز',
      actions: [
        if (canManage)
          GfPrimaryButton(label: 'ارز جدید', icon: Icons.add, onPressed: () => _CurrencyDialog.show(context)),
      ],
      columns: [
        const LedgerColumn('کد', width: 80),
        const LedgerColumn('نام', flex: 2),
        const LedgerColumn('نماد'),
        const LedgerColumn('اعشار مبلغ', numeric: true),
        const LedgerColumn('اعشار نرخ', numeric: true),
        const LedgerColumn('گرد کردن', flex: 2),
        const LedgerColumn('وضعیت'),
        if (canManage) const LedgerColumn('', width: LedgerRowMenu.width),
      ],
      rows: [
        for (final c in list)
          [
            Text(c.code, style: AppTypography.bodyMedium, textDirection: TextDirection.ltr),
            Text(c.nameFa),
            Text(c.symbol),
            Text('${c.precision}'),
            Text('${c.rateScale}'),
            Text(_roundingLabel(c.rounding)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfStatusBadge(
                label: c.isActive ? 'فعال' : 'غیرفعال',
                color: c.isActive ? AppColors.success : AppColors.textMuted,
                compact: true,
              ),
            ),
            if (canManage)
              LedgerRowMenu(
                onSelected: (_) => _CurrencyDialog.show(context, existing: c),
                items: [gfPopupMenuItem(value: 'edit', label: 'ویرایش')],
              ),
          ],
      ],
    );
  }
}

String _roundingLabel(RoundingMode m) => switch (m) {
      RoundingMode.halfUp => 'نیم به بالا',
      RoundingMode.halfEven => 'نیم به زوج (بانکی)',
      RoundingMode.down => 'به سمت صفر',
      RoundingMode.up => 'دور از صفر',
    };

class _CurrencyDialog extends StatefulWidget {
  const _CurrencyDialog({this.existing});

  final Currency? existing;

  static Future<void> show(BuildContext context, {Currency? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: _CurrencyDialog(existing: existing),
      ),
    );
  }

  @override
  State<_CurrencyDialog> createState() => _CurrencyDialogState();
}

class _CurrencyDialogState extends State<_CurrencyDialog> {
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _name = TextEditingController(text: widget.existing?.nameFa);
  late final _symbol = TextEditingController(text: widget.existing?.symbol);
  late final _precision = TextEditingController(text: '${widget.existing?.precision ?? 2}');
  late final _rateScale = TextEditingController(text: '${widget.existing?.rateScale ?? 6}');
  late final _order = TextEditingController(text: '${widget.existing?.sortOrder ?? 10}');
  late RoundingMode _rounding = widget.existing?.rounding ?? RoundingMode.halfUp;
  late bool _active = widget.existing?.isActive ?? true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_code, _name, _symbol, _precision, _rateScale, _order]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    int? n(TextEditingController c) => int.tryParse(Decimal.normalizeDigits(c.text.trim()));
    final precision = n(_precision), rateScale = n(_rateScale), order = n(_order);
    if (_name.text.trim().isEmpty ||
        precision == null ||
        precision < 0 ||
        precision > 6 ||
        rateScale == null ||
        rateScale < 0 ||
        rateScale > 12 ||
        order == null) {
      GfToast.error(context, 'نام، اعشار مبلغ (۰ تا ۶)، اعشار نرخ (۰ تا ۱۲) و ترتیب را درست وارد کنید.');
      return;
    }
    final currency = Currency(
      code: (widget.existing?.code ?? _code.text).trim().toUpperCase(),
      nameFa: _name.text.trim(),
      symbol: _symbol.text.trim(),
      precision: precision,
      rateScale: rateScale,
      rounding: _rounding,
      isActive: _active,
      sortOrder: order,
    );
    setState(() => _saving = true);
    final s = context.read<AppSession>();
    final ok = await runAction(context, () async {
      if (widget.existing == null) {
        await s.services.catalog.addCurrency(currency, s.actor);
      } else {
        await s.services.catalog.updateCurrency(currency, s.actor);
      }
      return true;
    }, success: 'ارز ذخیره شد.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return GfDialogShell(
      icon: existing == null ? Icons.add_card_outlined : Icons.edit_outlined,
      iconColor: AppColors.primary,
      title: existing == null ? 'ارز جدید' : 'ویرایش ارز',
      subtitle: existing == null ? 'برای هر ارز حساب‌های جداگانه ساخته می‌شود.' : 'کد ارز: ${existing.code}',
      cancelLabel: 'انصراف',
      onCancel: () => Navigator.of(context).pop(),
      primaryLabel: 'ذخیره',
      primaryIcon: Icons.save_outlined,
      onPrimary: _save,
      saving: _saving,
      maxWidth: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogResponsiveRow(
            children: [
              if (existing == null)
                GfTextField(label: 'کد لاتین (مثلاً GBP)', controller: _code, required: true, autofocus: true),
              GfTextField(label: 'نام فارسی', controller: _name, required: true, autofocus: existing != null),
            ],
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(label: 'نماد', controller: _symbol),
              GfTextField(label: 'ترتیب نمایش', controller: _order, keyboardType: TextInputType.number),
            ],
          ),
          const SizedBox(height: 14),
          DialogResponsiveRow(
            children: [
              GfTextField(
                label: 'اعشار مبلغ',
                controller: _precision,
                required: true,
                keyboardType: TextInputType.number,
              ),
              GfTextField(
                label: 'اعشار نرخ',
                controller: _rateScale,
                required: true,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          const SizedBox(height: 14),
          GfDropdown<RoundingMode>(
            label: 'روش گرد کردن مبلغ محاسبه‌شده',
            items: RoundingMode.values,
            value: _rounding,
            labelBuilder: _roundingLabel,
            onChanged: (m) {
              if (m != null) setState(() => _rounding = m);
            },
          ),
          if (existing != null) ...[
            const SizedBox(height: 14),
            GfToggleCard(
              label: 'فعال',
              subtitle: 'ارز غیرفعال در فرم‌های جدید نمایش داده نمی‌شود؛ سوابق آن باقی می‌ماند.',
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
          const SizedBox(height: 14),
          const DialogInfoBanner(
            message: 'تعداد اعشار ارزی که در آن سند ثبت شده قابل تغییر نیست.',
            tone: DialogBannerTone.warning,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ backup

class _BackupCard extends StatefulWidget {
  const _BackupCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<_BackupCard> with RevisionReload {
  DateTime? _lastBackup;
  bool _busy = false;

  @override
  Future<void> reload() async {
    final history = await session.services.backups.history();
    if (!mounted) return;
    setState(() {
      _lastBackup = history.isEmpty ? null : DateTime.parse(history.first['created_at'] as String);
    });
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    final s = context.read<AppSession>();
    final result = await runAction(context, () => s.services.backups.create(actor: s.actor));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) {
      GfToast.success(context, 'پشتیبان تهیه و تأیید شد: ${p.basename(result.databaseFile.path)}');
      reload();
    }
  }

  Future<String?> _pickBackup() async {
    final s = context.read<AppSession>();
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'انتخاب فایل پشتیبان',
      initialDirectory: s.services.backupDirectory,
      type: FileType.custom,
      allowedExtensions: const ['db'],
      lockParentWindow: true,
    );
    return picked?.files.single.path;
  }

  Future<void> _verify() async {
    final path = await _pickBackup();
    if (path == null || !mounted) return;
    final s = context.read<AppSession>();
    final check = await runAction(context, () => s.services.backups.verify(path));
    if (check == null || !mounted) return;
    await _showVerification(check);
  }

  Future<void> _showVerification(BackupVerification check) {
    final manifest = check.manifest;
    return showDialog<void>(
      context: context,
      builder: (ctx) => GfDialogShell(
        icon: check.isValid ? Icons.verified_outlined : Icons.gpp_bad_outlined,
        iconColor: check.isValid ? AppColors.success : AppColors.error,
        title: check.isValid ? 'پشتیبان معتبر است' : 'پشتیبان معتبر نیست',
        subtitle: p.basename(check.path),
        onCancel: () => Navigator.of(ctx).pop(),
        cancelLabel: 'بستن',
        maxWidth: 480,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (manifest != null)
              OrderDetailSummaryCard(
                rows: [
                  OrderDetailSummaryRow(label: 'زمان تهیه', value: DateFormatFa.dateTime(manifest.createdAt)),
                  OrderDetailSummaryRow(label: 'نوع', value: _kindLabel(manifest.kind)),
                  OrderDetailSummaryRow(label: 'نسخه ساختار', value: '${manifest.schemaVersion}'),
                  OrderDetailSummaryRow(
                    label: 'تعداد معاملات',
                    value: '${manifest.fingerprint['transactions']}',
                    highlight: true,
                  ),
                ],
              ),
            for (final problem in check.problems) ...[
              const SizedBox(height: 10),
              DialogInfoBanner(message: problem, tone: DialogBannerTone.error),
            ],
            if (check.isValid) ...[
              const SizedBox(height: 14),
              const DialogInfoBanner(
                message: 'کنترل صحت فایل و مشخصات آن با موفقیت انجام شد.',
                tone: DialogBannerTone.success,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _restore() async {
    final path = await _pickBackup();
    if (path == null || !mounted) return;
    final s = context.read<AppSession>();
    final check = await runAction(context, () => s.services.backups.verify(path));
    if (check == null || !mounted) return;
    if (!check.isValid) {
      await _showVerification(check);
      return;
    }
    final confirmation = await askReason(
      context,
      title: 'بازیابی پشتیبان',
      message: 'پایگاه داده فعلی با «${p.basename(path)}» '
          '(${DateFormatFa.dateTime(check.manifest!.createdAt)}) جایگزین می‌شود. '
          'پیش از آن یک پشتیبان ایمنی از وضعیت فعلی تهیه می‌شود. '
          'برای ادامه، کلمه «بازیابی» را بنویسید.',
      confirmLabel: 'بازیابی',
    );
    if (confirmation == null || !mounted) return;
    if (confirmation.trim() != 'بازیابی') {
      GfToast.warning(context, 'کلمه تأیید درست نیست؛ بازیابی انجام نشد.');
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await s.services.backups.restore(path, s.actor);
      return true;
    }, success: 'بازیابی انجام شد. پشتیبان ایمنی وضعیت قبلی نگهداری شده است.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final m = widget.metrics;
    final dir = s.services.backupDirectory;
    final last = _lastBackup;
    final fresh = last != null && DateTime.now().toUtc().difference(last.toUtc()) < const Duration(hours: 24);

    final actions = <Widget>[
      if (s.can(Permissions.backupCreate))
        SettingsTransferAction(
          icon: Icons.backup_outlined,
          title: 'تهیه پشتیبان',
          hint: 'یک نسخه سازگار از کل پایگاه داده همراه با فایل مشخصات و کنترل صحت ساخته می‌شود.',
          buttonLabel: _busy ? 'در حال انجام…' : 'تهیه پشتیبان',
          busy: _busy,
          onPressed: _busy ? null : _create,
        ),
      SettingsTransferAction(
        icon: Icons.verified_outlined,
        title: 'بررسی فایل پشتیبان',
        hint: 'صحت فایل پشتیبان و مشخصات آن بدون تغییر داده‌های فعلی بررسی می‌شود.',
        buttonLabel: 'بررسی فایل پشتیبان',
        onPressed: _busy ? null : _verify,
      ),
      if (s.can(Permissions.backupRestore))
        SettingsTransferAction(
          icon: Icons.restore,
          title: 'بازیابی از پشتیبان',
          hint: 'پایگاه داده فعلی جایگزین می‌شود؛ پیش از آن پشتیبان ایمنی گرفته می‌شود.',
          buttonLabel: 'بازیابی از پشتیبان',
          danger: true,
          onPressed: _busy ? null : _restore,
        ),
    ];

    return SettingsSectionCard(
      icon: Icons.folder_outlined,
      title: 'پشتیبان‌گیری و بازیابی',
      padding: m.cardPadding,
      footer: const SettingsFooterNote(
        'پشتیبان‌ها را مرتب روی حافظه جداگانه (فلش یا دیسک بیرونی) نیز کپی کنید. '
        'اگر کامپیوتر خراب شود، فقط نسخه بیرونی قابل استفاده است.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsFormRow(
            gap: m.fieldGap,
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('محل پشتیبان‌ها', style: AppTypography.label),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: GfTextField(
                        key: ValueKey(dir),
                        initialValue: dir,
                        readOnly: true,
                        prefixIcon: Icons.folder_open_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GfIconButton(
                      icon: Icons.open_in_new,
                      tooltip: 'باز کردن پوشه',
                      size: 48,
                      onPressed: () => _openPath(dir),
                    ),
                  ],
                ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('آخرین پشتیبان', style: AppTypography.label),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      last != null ? Icons.check_circle : Icons.schedule_outlined,
                      size: 18,
                      color: fresh ? AppColors.success : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            last == null ? 'هنوز پشتیبانی تهیه نشده است' : DateFormatFa.dateTime(last),
                            style: AppTypography.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            fresh ? 'پشتیبان به‌روز است' : 'پشتیبان جدید تهیه کنید',
                            style: AppTypography.caption.copyWith(
                              color: fresh ? AppColors.success : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: m.gap),
          SettingsTransferGroup(
            title: 'عملیات پشتیبان',
            children: [DialogResponsiveRow(gap: m.fieldGap, breakpoint: 760, children: actions)],
          ),
          SizedBox(height: m.fieldGap),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GfSecondaryButton(
              label: 'باز کردن پوشه پشتیبان‌ها',
              icon: Icons.folder_open_outlined,
              onPressed: () => _openPath(dir),
            ),
          ),
        ],
      ),
    );
  }
}

String _kindLabel(String kind) => switch (kind) {
      'manual' => 'دستی',
      'auto' => 'خودکار',
      'pre_restore' => 'ایمنی قبل از بازیابی',
      _ => kind,
    };

class _AutoBackupCard extends StatefulWidget {
  const _AutoBackupCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_AutoBackupCard> createState() => _AutoBackupCardState();
}

class _AutoBackupCardState extends State<_AutoBackupCard> with RevisionReload {
  bool _autoEnabled = true;
  final _interval = TextEditingController();
  final _retention = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _interval.dispose();
    _retention.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final c = session.services.catalog;
    final auto = await c.setting('backup.auto_enabled');
    final interval = await c.setting('backup.auto_interval_hours');
    final retention = await c.setting('backup.retention_count');
    if (!mounted) return;
    setState(() {
      _autoEnabled = auto != '0';
      _interval.text = interval ?? '24';
      _retention.text = retention ?? '30';
    });
  }

  Future<void> _save() async {
    final interval = int.tryParse(Decimal.normalizeDigits(_interval.text.trim()));
    final retention = int.tryParse(Decimal.normalizeDigits(_retention.text.trim()));
    if (interval == null || interval < 1 || retention == null || retention < 1) {
      GfToast.error(context, 'فاصله (ساعت) و تعداد نگهداری باید عدد مثبت باشد.');
      return;
    }
    final s = context.read<AppSession>();
    setState(() => _saving = true);
    await runAction(context, () async {
      await s.services.catalog.putSetting('backup.auto_enabled', _autoEnabled ? '1' : '0', s.actor);
      await s.services.catalog.putSetting('backup.auto_interval_hours', '$interval', s.actor);
      await s.services.catalog.putSetting('backup.retention_count', '$retention', s.actor);
    }, success: 'تنظیمات پشتیبان ذخیره شد.');
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    return SettingsSectionCard(
      icon: Icons.schedule_outlined,
      title: 'پشتیبان خودکار',
      padding: m.cardPadding,
      actions: [
        GfSecondaryButton(label: 'انصراف', icon: Icons.close, onPressed: _saving ? null : reload),
        GfPrimaryButton(
          label: 'ذخیره تغییرات',
          icon: Icons.save_outlined,
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfToggleCard(
            label: 'پشتیبان خودکار',
            subtitle: 'هنگام باز بودن برنامه، در فاصله تعیین‌شده پشتیبان تهیه و نسخه‌های قدیمی خودکار حذف می‌شود.',
            value: _autoEnabled,
            onChanged: (v) => setState(() => _autoEnabled = v),
          ),
          SizedBox(height: m.fieldGap),
          SettingsFormRow(
            gap: m.fieldGap,
            left: GfTextField(
              label: 'هر چند ساعت',
              prefixIcon: Icons.timer_outlined,
              controller: _interval,
              keyboardType: TextInputType.number,
            ),
            right: GfTextField(
              label: 'تعداد نگهداری',
              prefixIcon: Icons.layers_outlined,
              controller: _retention,
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupHistoryTable extends StatefulWidget {
  const _BackupHistoryTable();

  @override
  State<_BackupHistoryTable> createState() => _BackupHistoryTableState();
}

class _BackupHistoryTableState extends State<_BackupHistoryTable> with RevisionReload {
  List<Map<String, Object?>> _history = const [];
  bool _loading = true;

  @override
  Future<void> reload() async {
    final history = await session.services.backups.history();
    if (!mounted) return;
    setState(() {
      _history = history;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LedgerTable(
      title: 'سوابق پشتیبان',
      subtitle: '۱۰۰ پشتیبان آخر',
      itemLabel: 'پشتیبان',
      isLoading: _loading,
      emptyText: 'هنوز پشتیبانی تهیه نشده است.',
      columns: const [
        LedgerColumn('زمان', flex: 2),
        LedgerColumn('نوع', flex: 2),
        LedgerColumn('فایل', flex: 4),
        LedgerColumn('حجم', flex: 1, numeric: true),
      ],
      rows: [
        for (final h in _history)
          [
            Text(DateFormatFa.dateTime(DateTime.parse(h['created_at'] as String))),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfStatusBadge(
                label: _kindLabel(h['kind'] as String),
                color: switch (h['kind']) {
                  'auto' => AppColors.info,
                  'pre_restore' => AppColors.warning,
                  _ => AppColors.primary,
                },
                compact: true,
              ),
            ),
            Text(p.basename(h['file_path'] as String), style: AppTypography.caption, textDirection: TextDirection.ltr),
            Text('${((h['size_bytes'] as int) / 1024).ceil()} KB', textDirection: TextDirection.ltr),
          ],
      ],
    );
  }
}

// ------------------------------------------------------------------- audit

class _IntegrityCard extends StatefulWidget {
  const _IntegrityCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_IntegrityCard> createState() => _IntegrityCardState();
}

class _IntegrityCardState extends State<_IntegrityCard> {
  List<String>? _problems;
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final problems = await context.read<AppSession>().services.queries.integrityProblems();
    if (mounted) {
      setState(() {
        _problems = problems;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final problems = _problems;
    return SettingsSectionCard(
      icon: Icons.fact_check_outlined,
      title: 'سوابق ممیزی و صحت دفاتر',
      padding: m.cardPadding,
      trailing: problems == null
          ? null
          : GfStatusBadge(
              label: problems.isEmpty ? 'دفاتر سالم' : '${problems.length} مشکل',
              color: problems.isEmpty ? AppColors.success : AppColors.error,
            ),
      actions: [
        GfPrimaryButton(
          label: 'بررسی صحت دفاتر',
          icon: Icons.fact_check_outlined,
          isLoading: _checking,
          onPressed: _checking ? null : _check,
        ),
      ],
      footer: const SettingsFooterNote(
        'سوابق ممیزی فقط افزودنی است و قابل ویرایش یا حذف نیست.',
        warning: false,
      ),
      child: problems == null
          ? Text(
              'بررسی می‌کند که هر سند در هر ارز تراز باشد، هر معامله سند داشته باشد و ارجاعات برگشت معتبر باشند.',
              style: AppTypography.subtitle,
            )
          : problems.isEmpty
              ? const InfoBanner(
                  'همه اسناد تراز هستند، هر معامله سند دارد و ارجاعات معتبرند.',
                  tone: BannerTone.success,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < problems.length; i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      InfoBanner(problems[i], tone: BannerTone.error),
                    ],
                  ],
                ),
    );
  }
}

class _AuditTable extends StatefulWidget {
  const _AuditTable();

  @override
  State<_AuditTable> createState() => _AuditTableState();
}

class _AuditTableState extends State<_AuditTable> with RevisionReload {
  List<AuditEntry> _entries = const [];
  int _total = 0;
  int _page = 1;
  int _pageSize = 20;
  bool _loading = true;

  @override
  Future<void> reload() async {
    final db = session.services.db;
    final total = await AuditWriter.count(db);
    final entries = await AuditWriter.list(db, limit: _pageSize, offset: (_page - 1) * _pageSize);
    if (!mounted) return;
    setState(() {
      _total = total;
      _entries = entries;
      _loading = false;
    });
  }

  void _goTo(int page) {
    setState(() {
      _page = page;
      _loading = true;
    });
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return LedgerTable(
      title: 'سوابق ممیزی',
      subtitle: 'همه عملیات مهم با کاربر، زمان و نتیجه ثبت می‌شود.',
      itemLabel: 'رویداد',
      isLoading: _loading,
      minWidth: 900,
      page: _page,
      pageSize: _pageSize,
      total: _total,
      onPageChanged: _goTo,
      onPageSizeChanged: (size) {
        if (size == _pageSize) return;
        _pageSize = size;
        _goTo(1);
      },
      emptyText: 'رویدادی ثبت نشده است.',
      columns: const [
        LedgerColumn('زمان', flex: 2),
        LedgerColumn('کاربر', flex: 1),
        LedgerColumn('عملیات', flex: 2),
        LedgerColumn('موضوع', flex: 2),
        LedgerColumn('نتیجه', flex: 1),
        LedgerColumn('توضیح', flex: 3),
      ],
      rows: [
        for (final e in _entries)
          [
            Text(DateFormatFa.dateTime(e.occurredAt)),
            Text(e.actorName ?? '—'),
            Text(e.action, textDirection: TextDirection.ltr),
            Text('${e.entityType} ${e.entityId ?? ''}', textDirection: TextDirection.ltr),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfStatusBadge(
                label: e.outcome == 'success' ? 'موفق' : 'ناموفق',
                color: e.outcome == 'success' ? AppColors.success : AppColors.error,
                compact: true,
              ),
            ),
            Tooltip(
              message: e.reason ?? e.message ?? '',
              child: Text(e.reason ?? e.message ?? ''),
            ),
          ],
      ],
    );
  }
}

// -------------------------------------------------------------- appearance

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppSettingsProvider>();
    return SettingsSectionCard(
      icon: Icons.palette_outlined,
      title: 'ظاهر و تقویم',
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.appearanceSubtitle'.tr(), style: AppTypography.subtitle),
          SizedBox(height: metrics.fieldGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final options = [
                for (final variant in AppThemeVariant.values)
                  SettingsThemeOptionTile(
                    variant: variant,
                    selected: app.themeVariant == variant,
                    onSelected: () => app.setThemeVariant(variant),
                  ),
              ];
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0) SizedBox(height: metrics.fieldGap),
                      options[i],
                    ],
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0) SizedBox(width: metrics.fieldGap),
                      Expanded(child: options[i]),
                    ],
                  ],
                ),
              );
            },
          ),
          SizedBox(height: metrics.gap),
          SettingsFormRow(
            gap: metrics.fieldGap,
            left: GfDropdown<AppCalendarType>(
              label: 'تقویم نمایش',
              required: true,
              prefixIcon: Icons.calendar_month_outlined,
              items: const [AppCalendarType.solar, AppCalendarType.gregorian, AppCalendarType.lunar],
              value: app.calendarType,
              labelBuilder: (t) => switch (t) {
                AppCalendarType.solar => 'هجری شمسی',
                AppCalendarType.gregorian => 'میلادی',
                AppCalendarType.lunar => 'هجری قمری',
              },
              onChanged: (t) {
                if (t != null) app.setCalendarType(t);
              },
            ),
            right: GfToggleCard(
              label: 'کاهش انیمیشن‌ها',
              subtitle: 'انیمیشن‌های جابه‌جایی و تغییر پوسته حذف می‌شوند.',
              value: app.reducedMotion,
              onChanged: app.setReducedMotion,
            ),
          ),
          SizedBox(height: metrics.fieldGap * 0.5),
          Text(
            'تاریخ‌ها در پایگاه داده همیشه به‌صورت میلادی (ISO) ذخیره می‌شوند؛ تقویم فقط نمایش را تغییر می‌دهد.',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- about

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.metrics});

  final SettingsMetrics metrics;

  Widget _pathField(String label, String path, String openTarget) {
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
                initialValue: path,
                readOnly: true,
                prefixIcon: Icons.folder_open_outlined,
              ),
            ),
            const SizedBox(width: 8),
            GfIconButton(
              icon: Icons.open_in_new,
              tooltip: 'باز کردن پوشه',
              size: 48,
              onPressed: () => _openPath(openTarget),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final dbPath = s.services.databasePath;
    return SettingsSectionCard(
      icon: Icons.verified_user_outlined,
      title: 'درباره و مجوز',
      padding: metrics.cardPadding,
      trailing: GfStatusBadge(
        label: 'نسخه ${AppConstants.appVersion}',
        color: AppColors.primary,
        compact: true,
      ),
      footer: const SettingsFooterNote(
        'مجوز استفاده هرگز دسترسی به داده‌های مالی را مسدود نمی‌کند: '
        'مشاهده، گزارش‌گیری، پشتیبان‌گیری و خروجی همیشه در دسترس است.',
        warning: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrderDetailSummaryCard(
            rows: [
              OrderDetailSummaryRow(label: 'برنامه', value: AppConstants.appName),
              OrderDetailSummaryRow(label: 'نام لاتین', value: AppConstants.appNameLatin, ltrValue: true),
              OrderDetailSummaryRow(label: 'نسخه', value: AppConstants.appVersion, ltrValue: true),
            ],
          ),
          SizedBox(height: metrics.fieldGap),
          SettingsFormRow(
            gap: metrics.fieldGap,
            left: _pathField('پایگاه داده', dbPath, p.dirname(dbPath)),
            right: _pathField('پشتیبان‌ها', s.services.backupDirectory, s.services.backupDirectory),
          ),
        ],
      ),
    );
  }
}
