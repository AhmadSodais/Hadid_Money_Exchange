import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../application/audit_writer.dart';
import '../../application/catalog_service.dart';
import '../../application/ledger_queries.dart';
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
import '../widgets/transaction_actions.dart';
import '../widgets/transaction_detail_dialog.dart';

part 'settings_about_section.dart';

enum _Section {
  exchangeInfo,
  openingCash,
  currencies,
  appLock,
  backup,
  data,
  legacyImport,
  audit,
  appearance,
  about,
}

/// Kept in code but not offered in the settings navigation.
const _hiddenSections = {_Section.legacyImport, _Section.audit, _Section.backup};

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
    SettingsNavEntry(_Section.exchangeInfo, Icons.storefront_outlined, 'اطلاعات صرافی'),
    SettingsNavEntry(_Section.openingCash, Icons.account_balance_wallet_outlined, 'سرمایه اولیه '),
    SettingsNavEntry(_Section.currencies, Icons.currency_exchange, 'ارز و صندوق'),
    SettingsNavEntry(_Section.appLock, Icons.lock_outline, 'امنیت برنامه'),
    SettingsNavEntry(_Section.backup, Icons.folder_outlined, 'پشتیبان‌گیری و بازیابی'),
    SettingsNavEntry(_Section.data, Icons.table_view_outlined, 'مدیریت داده‌ها'),
    SettingsNavEntry(_Section.legacyImport, Icons.move_down, 'انتقال از برنامه قبلی'),
    SettingsNavEntry(_Section.audit, Icons.fact_check_outlined, 'سوابق ممیزی و صحت دفاتر'),
    SettingsNavEntry(_Section.appearance, Icons.palette_outlined, 'ظاهر'),
    SettingsNavEntry(_Section.about, Icons.info_outline, 'درباره برنامه'),
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
        _ when _hiddenSections.contains(section) => false,
        _Section.exchangeInfo => s.can(Permissions.settingsManage),
        _Section.data => s.can(Permissions.backupCreate) || s.can(Permissions.backupRestore),
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
      subtitle: 'اطلاعات صرافی، سرمایه، ارز و صندوق، امنیت، مدیریت داده‌ها و ظاهر برنامه',
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
      _Section.exchangeInfo => [_ExchangeInfoCard(metrics: metrics)],
      _Section.openingCash => [_CapitalSection(metrics: metrics)],
      _Section.currencies => [const _CurrenciesTable(), const _DrawersTable()],
      _Section.appLock => [AppLockSettingsCard(padding: metrics.cardPadding)],
      _Section.backup => [
          _BackupCard(metrics: metrics),
          if (s.can(Permissions.settingsManage)) _AutoBackupCard(metrics: metrics),
          const SizedBox(height: 460, child: _BackupHistoryTable()),
          const SizedBox(height: 460, child: _ExcelFileLogTable()),
        ],
      _Section.data => [
          _DataTransferCard(metrics: metrics),
          if (s.can(Permissions.settingsManage)) _AutoExcelExportCard(metrics: metrics),
          const SizedBox(height: 460, child: _AutoExcelExportHistoryTable()),
        ],
      _Section.legacyImport => [LegacyImportCard(metrics: metrics)],
      _Section.audit => [
          _IntegrityCard(metrics: metrics),
          const SizedBox(height: 560, child: _AuditTable()),
        ],
      _Section.appearance => [_AppearanceCard(metrics: metrics)],
      _Section.about => [_AboutCard(metrics: metrics)],
    };

    return ListView.separated(
      key: ValueKey(selected),
      itemCount: sections.length,
      separatorBuilder: (_, _) => SizedBox(height: metrics.gap),
      itemBuilder: (context, i) => sections[i],
    );
  }
}

// ---------------------------------------------------------- exchange info

class _ExchangeInfoCard extends StatefulWidget {
  const _ExchangeInfoCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_ExchangeInfoCard> createState() => _ExchangeInfoCardState();
}

class _ExchangeInfoCardState extends State<_ExchangeInfoCard> with RevisionReload {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _userName = TextEditingController();
  final _phone = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _userName.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final services = session.services;
    final c = services.catalog;
    final name = await c.setting('business.name');
    final city = await c.setting('business.city');
    final address = await c.setting('business.address');
    final profile = await services.security.profile(session.actor.userId);
    if (!mounted) return;
    setState(() {
      _name.text = name ?? '';
      _city.text = city ?? '';
      _address.text = address ?? '';
      _userName.text = profile.displayName;
      _phone.text = profile.phone ?? '';
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      GfToast.error(context, 'نام صرافی را وارد کنید.');
      return;
    }
    if (_userName.text.trim().isEmpty) {
      GfToast.error(context, 'نام کاربری را وارد کنید.');
      return;
    }
    final s = context.read<AppSession>();
    final c = s.services.catalog;
    setState(() => _saving = true);
    await runAction(context, () async {
      await s.services.security.updateProfile(
        s.actor.userId,
        displayName: _userName.text,
        phone: _phone.text,
        actor: s.actor,
      );
      await c.putSetting('business.name', _name.text.trim(), s.actor);
      await c.putSetting('business.city', _city.text.trim(), s.actor);
      await c.putSetting('business.address', _address.text.trim(), s.actor);
    }, success: 'اطلاعات صرافی ذخیره شد.');
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    return SettingsSectionCard(
      icon: Icons.storefront_outlined,
      title: 'اطلاعات صرافی',
      padding: m.cardPadding,
      footer: Text(
        'نام صرافی و نشانی در گزارش‌ها و رسیدها استفاده می‌شود. نام کاربری در منوی کناری نمایش داده می‌شود.',
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
                SettingsTransferGroup(
                  title: 'مشخصات صرافی',
                  children: [
                    SettingsFormRow(
                      gap: m.fieldGap,
                      left: GfTextField(
                        label: 'نام صرافی',
                        prefixIcon: Icons.storefront_outlined,
                        controller: _name,
                        required: true,
                      ),
                      right: GfTextField(
                        label: 'ولایت / شهر',
                        hint: 'مثلاً کابل',
                        prefixIcon: Icons.location_city_outlined,
                        controller: _city,
                      ),
                    ),
                    SizedBox(height: m.fieldGap),
                    GfTextField(
                      label: 'آدرس صرافی',
                      hint: 'ناحیه، سرک، مارکیت، منزل و شماره دکان',
                      prefixIcon: Icons.place_outlined,
                      controller: _address,
                      minLines: 2,
                      maxLines: 3,
                    ),
                  ],
                ),
                SizedBox(height: m.fieldGap * 1.5),
                SettingsTransferGroup(
                  title: 'مشخصات کاربر',
                  children: [
                    SettingsFormRow(
                      gap: m.fieldGap,
                      left: GfTextField(
                        label: 'نام کاربری',
                        prefixIcon: Icons.person_outline,
                        controller: _userName,
                        required: true,
                      ),
                      right: GfTextField(
                        label: 'شماره تماس',
                        hint: 'مثلاً 0700123456',
                        prefixIcon: Icons.phone_outlined,
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ----------------------------------------------------------------- capital

/// One active capital posting. The earliest per drawer and currency is the
/// initial capital; every later one is a capital injection.
class _CapitalEntry {
  const _CapitalEntry(this.tx, {required this.initial});

  final PostedTransaction tx;
  final bool initial;

  int get drawerId => tx.drawerId ?? 0;
  String get currency => tx.sourceCurrency ?? '';
  int get amountMinor => tx.sourceAmountMinor ?? 0;
}

class _CapitalTotal {
  int initialMinor = 0;
  int injectedMinor = 0;
  int injections = 0;

  int get totalMinor => initialMinor + injectedMinor;
}

enum _CapitalAction { details, edit, delete }

/// Initial capital and later capital injections of every drawer: a form to
/// add capital, the current capital per drawer and currency, and the list of
/// capital documents with view, edit and delete.
class _CapitalSection extends StatefulWidget {
  const _CapitalSection({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_CapitalSection> createState() => _CapitalSectionState();
}

class _CapitalSectionState extends State<_CapitalSection> with RevisionReload {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  int? _drawerId;
  Currency? _currency;
  BusinessDate _date = BusinessDate.today();
  String _key = PostingService.newIdempotencyKey();
  bool _saving = false;
  bool _loading = true;

  /// Newest first.
  List<_CapitalEntry> _entries = const [];

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final rows = await session.services.queries.journal(
      const JournalFilter(types: {TransactionType.openingCash}, activeOnly: true),
      limit: 100000,
      newestFirst: false,
    );
    final seen = <(int?, String?)>{};
    final entries = [
      for (final t in rows) _CapitalEntry(t, initial: seen.add((t.drawerId, t.sourceCurrency))),
    ];
    if (!mounted) return;
    setState(() {
      _entries = entries.reversed.toList();
      _loading = false;
    });
  }

  Map<(int, String), _CapitalTotal> get _totals {
    final totals = <(int, String), _CapitalTotal>{};
    for (final e in _entries) {
      final t = totals.putIfAbsent((e.drawerId, e.currency), _CapitalTotal.new);
      if (e.initial) {
        t.initialMinor += e.amountMinor;
      } else {
        t.injectedMinor += e.amountMinor;
        t.injections++;
      }
    }
    return totals;
  }

  int? _selectedDrawer(AppSession s) => _drawerId ?? (s.activeDrawers.isEmpty ? null : s.activeDrawers.first.id);

  Future<void> _post() async {
    final s = context.read<AppSession>();
    final drawer = _selectedDrawer(s);
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
    final kind = _totals.containsKey((drawer, c.code)) ? 'افزایش سرمایه' : 'سرمایه اولیه';
    final note = _description.text.trim();
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
          description: note.isEmpty ? '$kind ${c.nameFa}' : note,
        ),
        s.actor,
      ),
      success: '$kind ${MoneyFormat.withName(minor, c)} ثبت شد.',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (posted != null) {
        _key = PostingService.newIdempotencyKey();
        _amount.clear();
        _description.clear();
      }
    });
  }

  Future<void> _run(_CapitalAction action, PostedTransaction t) async {
    switch (action) {
      case _CapitalAction.details:
        await TransactionDetailDialog.show(context, t.id);
      case _CapitalAction.edit:
        await TransactionActions.edit(context, t);
      case _CapitalAction.delete:
        await TransactionActions.delete(context, t);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final m = widget.metrics;
    final totals = _totals;
    final drawerNames = {for (final d in s.drawers) d.id: d.nameFa};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _form(s, m, totals, drawerNames),
        SizedBox(height: m.gap),
        _summaryTable(s, totals, drawerNames),
        SizedBox(height: m.gap),
        _historyTable(s),
      ],
    );
  }

  Widget _form(
    AppSession s,
    SettingsMetrics m,
    Map<(int, String), _CapitalTotal> totals,
    Map<int, String> drawerNames,
  ) {
    final drawer = _selectedDrawer(s);
    final c = _currency;
    final current = drawer == null || c == null ? null : totals[(drawer, c.code)];
    final injecting = current != null;
    return SettingsSectionCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'ثبت سرمایه صندوق',
      padding: m.cardPadding,
      footer: const SettingsFooterNote(
        'اولین سرمایه هر ارز در هر صندوق «سرمایه اولیه» و هر مبلغ بعدی «افزایش سرمایه» است و به موجودی صندوق اضافه می‌شود. '
        'برای مشاهده، ویرایش یا حذف، از منوی ⋮ هر ردیف در «سوابق سرمایه» استفاده کنید؛ سابقه برای ممیزی حفظ می‌شود.',
        warning: false,
      ),
      actions: [
        GfPrimaryButton(
          label: injecting ? 'افزودن سرمایه' : 'ثبت سرمایه اولیه',
          icon: injecting ? Icons.add_card_outlined : Icons.account_balance_wallet_outlined,
          isLoading: _saving,
          onPressed: _saving ? null : _post,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsFormRow(
            gap: m.fieldGap,
            left: DrawerPicker(value: drawer, onChanged: (id) => setState(() => _drawerId = id)),
            right: CurrencyPicker(value: _currency, onChanged: (c) => setState(() => _currency = c)),
          ),
          SizedBox(height: m.fieldGap),
          SettingsFormRow(
            gap: m.fieldGap,
            left: AmountField(controller: _amount, label: 'مبلغ ${_currency?.nameFa ?? ''}'),
            right: BusinessDateField(value: _date, onChanged: (d) => setState(() => _date = d)),
          ),
          SizedBox(height: m.fieldGap),
          GfTextField(
            label: 'شرح (اختیاری)',
            hint: injecting ? 'مثلاً افزایش سرمایه توسط شریک' : 'مثلاً سرمایه شروع کار صرافی',
            prefixIcon: Icons.notes_outlined,
            controller: _description,
          ),
          if (drawer != null && c != null) ...[
            SizedBox(height: m.fieldGap),
            InfoBanner(
              injecting
                  ? 'سرمایه فعلی «${drawerNames[drawer] ?? ''}» در ${c.nameFa}: '
                      '${MoneyFormat.withName(current.totalMinor, c)} '
                      '(سرمایه اولیه ${MoneyFormat.withName(current.initialMinor, c)}'
                      '${current.injections > 0 ? '، ${current.injections} بار افزایش' : ''}). '
                      'مبلغ جدید به‌عنوان افزایش سرمایه به آن اضافه می‌شود.'
                  : 'برای «${drawerNames[drawer] ?? ''}» در ${c.nameFa} هنوز سرمایه‌ای ثبت نشده؛ '
                      'این مبلغ به‌عنوان سرمایه اولیه ثبت می‌شود.',
              tone: injecting ? BannerTone.success : BannerTone.info,
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryTable(AppSession s, Map<(int, String), _CapitalTotal> totals, Map<int, String> drawerNames) {
    final keys = totals.keys.toList()
      ..sort((a, b) {
        final byDrawer = a.$1.compareTo(b.$1);
        if (byDrawer != 0) return byDrawer;
        return (s.currency(a.$2)?.sortOrder ?? 99).compareTo(s.currency(b.$2)?.sortOrder ?? 99);
      });
    return LedgerTable(
      shrinkWrap: true,
      title: 'سرمایه فعلی',
      subtitle: 'مجموع سرمایه اولیه و افزایش‌های سرمایه هر صندوق به تفکیک ارز.',
      itemLabel: 'ردیف',
      minWidth: 760,
      showRowNumbers: false,
      isLoading: _loading,
      emptyText: 'هنوز سرمایه‌ای ثبت نشده است.',
      columns: const [
        LedgerColumn.primary('صندوق'),
        LedgerColumn.text('ارز'),
        LedgerColumn.amount('سرمایه اولیه'),
        LedgerColumn.amount('افزایش سرمایه'),
        LedgerColumn.amount('مجموع سرمایه'),
      ],
      rows: [
        for (final k in keys)
          () {
            final t = totals[k]!;
            final c = s.currency(k.$2);
            return [
              Text(drawerNames[k.$1] ?? '—', style: AppTypography.bodyMedium),
              Text(c?.nameFa ?? k.$2, style: AppTypography.body),
              AmountText(t.initialMinor, c),
              AmountText(t.injectedMinor, c),
              AmountText(t.totalMinor, c, bold: true),
            ];
          }(),
      ],
    );
  }

  Widget _historyTable(AppSession s) {
    return LedgerTable(
      shrinkWrap: true,
      fixedRows: 10,
      title: 'سوابق سرمایه',
      titleCount: _entries.length,
      subtitle: 'برای جزئیات روی ردیف کلیک کنید؛ ویرایش و حذف از منوی ⋮ انتهای ردیف.',
      itemLabel: 'سند',
      minWidth: 720,
      isLoading: _loading,
      emptyText: 'هنوز سرمایه‌ای ثبت نشده است.',
      columns: const [
        LedgerColumn('تاریخ'),
        LedgerColumn('نوع'),
        LedgerColumn('شرح'),
        LedgerColumn('مبلغ', numeric: true),
        LedgerColumn.actions(),
      ],
      rows: [
        for (final e in _entries)
          [
            Text(DateFormatFa.business(e.tx.effectiveDate), style: AppTypography.body),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfStatusBadge(
                label: e.initial ? 'سرمایه اولیه' : 'افزایش سرمایه',
                color: e.initial ? AppColors.primary : AppColors.success,
                compact: true,
              ),
            ),
            Tooltip(
              message: e.tx.description ?? '',
              child: Text(e.tx.description ?? '—', style: AppTypography.body),
            ),
            AmountText(e.amountMinor, s.currency(e.currency), showName: true),
            LedgerRowMenu(
              onSelected: (v) => _run(_CapitalAction.values.byName(v), e.tx),
              items: [
                gfPopupMenuItem(value: _CapitalAction.details.name, label: 'مشاهده جزئیات'),
                if (TransactionActions.canEdit(e.tx, s))
                  gfPopupMenuItem(value: _CapitalAction.edit.name, label: 'ویرایش'),
                if (TransactionActions.canDelete(e.tx, s))
                  gfPopupMenuItem(value: _CapitalAction.delete.name, label: 'حذف', danger: true),
              ],
            ),
          ],
      ],
      onTapRow: (i) => TransactionDetailDialog.show(context, _entries[i].tx.id),
    );
  }
}

// -------------------------------------------------------------- currencies

/// Single-digit settings and a one-word badge; the default flex/status widths
/// leave the headers truncated or the badge floating in empty space.
const double _currencyDigitsWidth = 96;
const double _currencyStatusWidth = 96;

class _CurrenciesTable extends StatelessWidget {
  const _CurrenciesTable();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canManage = s.can(Permissions.settingsManage);
    final list = s.currencies.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return LedgerTable(
      shrinkWrap: true,
      title: 'ارزها',
      subtitle: 'IRT = تومان ایران (۱ تومان = ۱۰ ریال) و با ریال (IRR) یکی نیست. '
          'تعداد اعشار ارزی که در آن سند ثبت شده قابل تغییر نیست.',
      itemLabel: 'ارز',
      minWidth: 680,
      showRowNumbers: false,
      emptyText: 'ارزی تعریف نشده است.',
      actions: [
        if (canManage)
          GfPrimaryButton(label: 'ارز جدید', icon: Icons.add, onPressed: () => _CurrencyDialog.show(context)),
      ],
      columns: [
        const LedgerColumn.code(),
        const LedgerColumn.primary('ارز'),
        const LedgerColumn.text('روش گرد کردن'),
        const LedgerColumn('اعشار مبلغ', numeric: true, width: _currencyDigitsWidth),
        const LedgerColumn('اعشار نرخ', numeric: true, width: _currencyDigitsWidth),
        const LedgerColumn('وضعیت', width: _currencyStatusWidth),
        if (canManage) const LedgerColumn.actions(),
      ],
      rows: [
        for (final c in list)
          () {
            final muted = c.isActive ? null : AppColors.textMuted;
            return [
              Text(
                c.code,
                style: AppTypography.bodySemiBold.copyWith(color: muted),
                textDirection: TextDirection.ltr,
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: c.nameFa, style: AppTypography.bodyMedium.copyWith(color: muted)),
                    if (c.symbol.trim().isNotEmpty)
                      TextSpan(
                        text: '  ${c.symbol.trim()}',
                        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
              Text(_roundingLabel(c.rounding), style: AppTypography.body.copyWith(color: muted ?? AppColors.textSecondary)),
              Text('${c.precision}', style: AppTypography.bodyMedium.copyWith(color: muted)),
              Text('${c.rateScale}', style: AppTypography.bodyMedium.copyWith(color: muted)),
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
            ];
          }(),
      ],
      onTapRow: canManage ? (i) => _CurrencyDialog.show(context, existing: list[i]) : null,
    );
  }
}

// ----------------------------------------------------------------- drawers

class _DrawersTable extends StatefulWidget {
  const _DrawersTable();

  @override
  State<_DrawersTable> createState() => _DrawersTableState();
}

class _DrawersTableState extends State<_DrawersTable> with RevisionReload {
  Map<int, Map<String, int>> _balances = const {};

  @override
  Future<void> reload() async {
    final queries = session.services.queries;
    final balances = <int, Map<String, int>>{
      for (final d in session.drawers) d.id: await queries.cashBalances(drawerId: d.id),
    };
    if (!mounted) return;
    setState(() => _balances = balances);
  }

  Future<void> _toggle(CashDrawer d) async {
    final s = context.read<AppSession>();
    await runAction(
      context,
      () => s.services.catalog.updateDrawer(d.id, name: d.nameFa, isActive: !d.isActive, actor: s.actor),
      success: d.isActive ? 'صندوق «${d.nameFa}» غیرفعال شد.' : 'صندوق «${d.nameFa}» فعال شد.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final canManage = s.can(Permissions.settingsManage);
    final list = s.drawers;
    return LedgerTable(
      shrinkWrap: true,
      title: 'صندوق‌ها',
      subtitle: 'هر صندوق موجودی، سرمایه اولیه و بیلانس روزانه جداگانه دارد. '
          'صندوق با موجودی غیرصفر قابل غیرفعال کردن نیست.',
      itemLabel: 'صندوق',
      minWidth: 680,
      showRowNumbers: false,
      emptyText: 'صندوقی تعریف نشده است.',
      actions: [
        if (canManage)
          GfPrimaryButton(label: 'صندوق جدید', icon: Icons.add, onPressed: () => _DrawerDialog.show(context)),
      ],
      columns: [
        const LedgerColumn.code(),
        const LedgerColumn.primary('صندوق'),
        const LedgerColumn.description('موجودی'),
        const LedgerColumn('وضعیت', width: _currencyStatusWidth),
        if (canManage) const LedgerColumn.actions(),
      ],
      rows: [
        for (final d in list)
          () {
            final muted = d.isActive ? null : AppColors.textMuted;
            final balances = (_balances[d.id] ?? const {}).entries.where((e) => e.value != 0).toList()
              ..sort((a, b) => (s.currency(a.key)?.sortOrder ?? 99).compareTo(s.currency(b.key)?.sortOrder ?? 99));
            final summary = balances.isEmpty
                ? 'بدون موجودی'
                : balances
                    .map((e) => '${MoneyFormat.amount(e.value, s.currency(e.key))} ${s.currency(e.key)?.nameFa ?? e.key}')
                    .join('  ·  ');
            return [
              Text(d.code, style: AppTypography.caption.copyWith(color: muted), textDirection: TextDirection.ltr),
              Text(d.nameFa, style: AppTypography.bodyMedium.copyWith(color: muted)),
              Tooltip(
                message: summary,
                child: Text(
                  summary,
                  style: AppTypography.body.copyWith(color: balances.isEmpty ? AppColors.textMuted : muted),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: GfStatusBadge(
                  label: d.isActive ? 'فعال' : 'غیرفعال',
                  color: d.isActive ? AppColors.success : AppColors.textMuted,
                  compact: true,
                ),
              ),
              if (canManage)
                LedgerRowMenu(
                  onSelected: (action) {
                    if (action == 'edit') _DrawerDialog.show(context, existing: d);
                    if (action == 'toggle') _toggle(d);
                  },
                  items: [
                    gfPopupMenuItem(value: 'edit', label: 'ویرایش نام'),
                    gfPopupMenuItem(
                      value: 'toggle',
                      label: d.isActive ? 'غیرفعال کردن' : 'فعال کردن',
                      danger: d.isActive,
                    ),
                  ],
                ),
            ];
          }(),
      ],
      onTapRow: canManage ? (i) => _DrawerDialog.show(context, existing: list[i]) : null,
    );
  }
}

class _DrawerDialog extends StatefulWidget {
  const _DrawerDialog({this.existing});

  final CashDrawer? existing;

  static Future<void> show(BuildContext context, {CashDrawer? existing}) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AppSession>(),
        child: _DrawerDialog(existing: existing),
      ),
    );
  }

  @override
  State<_DrawerDialog> createState() => _DrawerDialogState();
}

class _DrawerDialogState extends State<_DrawerDialog> {
  late final _name = TextEditingController(text: widget.existing?.nameFa);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      GfToast.error(context, 'نام صندوق را وارد کنید.');
      return;
    }
    final s = context.read<AppSession>();
    final existing = widget.existing;
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      if (existing == null) {
        await s.services.catalog.addDrawer(_name.text, s.actor);
      } else {
        await s.services.catalog.updateDrawer(existing.id, name: _name.text, isActive: existing.isActive, actor: s.actor);
      }
      return true;
    }, success: existing == null ? 'صندوق جدید اضافه شد.' : 'نام صندوق ذخیره شد.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return GfDialogShell(
      icon: existing == null ? Icons.add_business_outlined : Icons.edit_outlined,
      iconColor: AppColors.primary,
      title: existing == null ? 'صندوق جدید' : 'ویرایش صندوق',
      subtitle: existing == null ? 'برای صندوق جدید حساب نقد جداگانه ساخته می‌شود.' : 'کد صندوق: ${existing.code}',
      cancelLabel: 'انصراف',
      onCancel: () => Navigator.of(context).pop(),
      primaryLabel: 'ذخیره',
      primaryIcon: Icons.save_outlined,
      onPrimary: _save,
      saving: _saving,
      maxWidth: 440,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfTextField(label: 'نام صندوق', controller: _name, required: true, autofocus: true),
          if (existing == null) ...[
            const SizedBox(height: 14),
            const DialogInfoBanner(
              message: 'پس از ساخت، سرمایه اولیه هر ارز این صندوق را از بخش «سرمایه اولیه و افزایش سرمایه» ثبت کنید.',
              tone: DialogBannerTone.info,
            ),
          ],
        ],
      ),
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
      'pre_restore' => 'ایمنی (قبل از جایگزینی داده‌ها)',
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
        LedgerColumn.dateTime(),
        LedgerColumn.text('نوع'),
        LedgerColumn.description('فایل'),
        LedgerColumn.number('حجم'),
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

String _excelActionLabel(String action) => switch (action) {
      'data.export' => 'خروجی اکسل',
      'data.import' => 'ورودی اکسل',
      'data.clear' => 'پاک کردن داده‌ها',
      _ => action,
    };

class _ExcelFileLogTable extends StatefulWidget {
  const _ExcelFileLogTable();

  @override
  State<_ExcelFileLogTable> createState() => _ExcelFileLogTableState();
}

class _ExcelFileLogTableState extends State<_ExcelFileLogTable> with RevisionReload {
  List<AuditEntry> _entries = const [];
  bool _loading = true;

  @override
  Future<void> reload() async {
    final entries = await session.services.transfer.fileLog();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LedgerTable(
      title: 'سوابق فایل‌های اکسل',
      subtitle: 'خروجی، ورودی و پاک کردن داده‌ها',
      itemLabel: 'عملیات',
      isLoading: _loading,
      emptyText: 'هنوز فایل اکسلی ثبت نشده است.',
      columns: const [
        LedgerColumn('زمان', flex: 2),
        LedgerColumn('عملیات', flex: 2),
        LedgerColumn('فایل', flex: 4),
        LedgerColumn('نتیجه', flex: 1),
      ],
      rows: [
        for (final e in _entries)
          [
            Text(DateFormatFa.dateTime(e.occurredAt)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfStatusBadge(
                label: _excelActionLabel(e.action),
                color: switch (e.action) {
                  'data.import' => AppColors.warning,
                  'data.clear' => AppColors.error,
                  _ => AppColors.primary,
                },
                compact: true,
              ),
            ),
            Text(
              e.action == 'data.clear' ? '—' : (e.entityId ?? '—'),
              style: AppTypography.caption,
              textDirection: e.action == 'data.clear' ? null : TextDirection.ltr,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfStatusBadge(
                label: e.outcome == 'success' ? 'موفق' : 'ناموفق',
                color: e.outcome == 'success' ? AppColors.success : AppColors.error,
                compact: true,
              ),
            ),
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
      minWidth: 1100,
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
        LedgerColumn.dateTime(),
        LedgerColumn.text('عملیات'),
        LedgerColumn.text('کاربر'),
        LedgerColumn.text('موضوع'),
        LedgerColumn.description('توضیح'),
        LedgerColumn.status('نتیجه'),
      ],
      rows: [
        for (final e in _entries)
          [
            Text(DateFormatFa.dateTime(e.occurredAt)),
            Text(e.action, textDirection: TextDirection.ltr),
            Text(e.actorName ?? '—'),
            Text('${e.entityType} ${e.entityId ?? ''}', textDirection: TextDirection.ltr),
            Tooltip(
              message: e.reason ?? e.message ?? '',
              child: Text(e.reason ?? e.message ?? ''),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfStatusBadge(
                label: e.outcome == 'success' ? 'موفق' : 'ناموفق',
                color: e.outcome == 'success' ? AppColors.success : AppColors.error,
                compact: true,
              ),
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
      title: 'ظاهر',
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
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- excel data

class _DataTransferCard extends StatefulWidget {
  const _DataTransferCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_DataTransferCard> createState() => _DataTransferCardState();
}

class _DataTransferCardState extends State<_DataTransferCard> {
  bool _busy = false;

  Future<T?> _run<T>(Future<T> Function() action, {String? success}) async {
    setState(() => _busy = true);
    final result = await runAction(context, action, success: success);
    if (mounted) setState(() => _busy = false);
    return result;
  }

  Future<bool> _confirmWord(String title, String message, String word, String confirmLabel) async {
    final typed = await askReason(
      context,
      title: title,
      message: '$message برای ادامه، کلمه «$word» را بنویسید.',
      confirmLabel: confirmLabel,
    );
    if (typed == null || !mounted) return false;
    if (typed.trim() != word) {
      GfToast.warning(context, 'کلمه تأیید درست نیست؛ عملیات انجام نشد.');
      return false;
    }
    return true;
  }

  Future<void> _export() async {
    final s = context.read<AppSession>();
    final stamp = AppCalendar.formatDate(DateTime.now()).replaceAll('/', '-');
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: 'خروجی اکسل همه داده‌ها',
      fileName: 'hadid_data_$stamp.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      lockParentWindow: true,
    );
    if (picked == null || !mounted) return;
    final path = picked.toLowerCase().endsWith('.xlsx') ? picked : '$picked.xlsx';
    final summary = await _run(() => s.services.transfer.exportTo(path, s.actor));
    if (summary == null || !mounted) return;
    GfToast.success(
      context,
      'خروجی اکسل ذخیره شد (${summary['transactions'] ?? 0} معامله، '
      '${summary['customers'] ?? 0} مشتری): ${p.basename(path)}',
    );
  }

  Future<void> _import() async {
    final s = context.read<AppSession>();
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'انتخاب فایل اکسل برای ورود داده‌ها',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      lockParentWindow: true,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final ok = await _confirmWord(
      'ورودی اکسل',
      'همه داده‌های فعلی برنامه با محتوای «${p.basename(path)}» جایگزین می‌شود. '
          'فایل پیش از جایگزینی کامل بررسی می‌شود و یک پشتیبان ایمنی از وضعیت فعلی گرفته می‌شود.',
      'جایگزینی',
      'ورود داده‌ها',
    );
    if (!ok) return;
    await _run(
      () => s.services.transfer.importFrom(path, s.actor),
      success: 'داده‌ها از فایل اکسل وارد شد. پشتیبان ایمنی وضعیت قبلی نگهداری شده است.',
    );
  }

  Future<void> _clear() async {
    final s = context.read<AppSession>();
    final ok = await _confirmWord(
      'پاک کردن همه داده‌ها',
      'همه مشتریان، معاملات، نرخ‌ها، بیلانس‌های روزانه و سوابق حذف می‌شوند. '
          'اطلاعات صرافی، سیاست‌ها و تعریف ارزها باقی می‌ماند. '
          'پیش از پاک کردن یک پشتیبان ایمنی گرفته می‌شود که از بخش پشتیبان‌گیری قابل بازیابی است.',
      'پاک کردن',
      'پاک کردن همه داده‌ها',
    );
    if (!ok) return;
    await _run(
      () => s.services.transfer.clearAll(s.actor),
      success: 'همه داده‌ها پاک شد. پشتیبان ایمنی داده‌های قبلی نگهداری شده است.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final m = widget.metrics;
    final canRestore = s.can(Permissions.backupRestore);
    return SettingsSectionCard(
      icon: Icons.table_view_outlined,
      title: 'ورودی و خروجی اکسل',
      padding: m.cardPadding,
      footer: const SettingsFooterNote(
        'فایل اکسل شامل همه داده‌های برنامه است و تاریخ‌ها در آن هجری شمسی ثبت می‌شوند. '
        'برای ورود، فقط فایلی را انتخاب کنید که از «خروجی اکسل» همین برنامه گرفته شده است.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsTransferGroup(
            title: 'اکسل',
            children: [
              DialogResponsiveRow(
                gap: m.fieldGap,
                breakpoint: 760,
                children: [
                  if (s.can(Permissions.backupCreate))
                    SettingsTransferAction(
                      icon: Icons.file_download_outlined,
                      title: 'خروجی اکسل',
                      hint: 'همه داده‌ها (مشتریان، معاملات، نرخ‌ها، بیلانس‌ها و تنظیمات) در یک فایل اکسل ذخیره می‌شود.',
                      buttonLabel: _busy ? 'در حال انجام…' : 'خروجی اکسل',
                      busy: _busy,
                      onPressed: _busy ? null : _export,
                    ),
                  if (canRestore)
                    SettingsTransferAction(
                      icon: Icons.file_upload_outlined,
                      title: 'ورودی اکسل',
                      hint: 'داده‌های فعلی با فایل اکسل جایگزین می‌شود؛ فایل نادرست یا ناقص پذیرفته نمی‌شود.',
                      buttonLabel: 'ورودی اکسل',
                      danger: true,
                      onPressed: _busy ? null : _import,
                    ),
                ],
              ),
            ],
          ),
          if (canRestore) ...[
            SizedBox(height: m.gap),
            SettingsTransferGroup(
              title: 'پاک کردن داده‌ها',
              children: [
                SettingsTransferAction(
                  icon: Icons.delete_forever_outlined,
                  title: 'پاک کردن همه داده‌ها',
                  hint: 'برنامه به حالت شروع برمی‌گردد؛ اطلاعات صرافی و ارزها باقی می‌ماند و پشتیبان ایمنی گرفته می‌شود.',
                  buttonLabel: 'پاک کردن همه داده‌ها',
                  danger: true,
                  onPressed: _busy ? null : _clear,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AutoExcelExportCard extends StatefulWidget {
  const _AutoExcelExportCard({required this.metrics});

  final SettingsMetrics metrics;

  @override
  State<_AutoExcelExportCard> createState() => _AutoExcelExportCardState();
}

class _AutoExcelExportCardState extends State<_AutoExcelExportCard> with RevisionReload {
  bool _enabled = false;
  final _interval = TextEditingController();
  final _retention = TextEditingController();

  /// Empty means the default folder.
  String _folder = '';
  bool _saving = false;
  bool _running = false;

  @override
  void dispose() {
    _interval.dispose();
    _retention.dispose();
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final c = session.services.catalog;
    final enabled = await c.setting('excel.auto_enabled');
    final interval = await c.setting('excel.auto_interval_hours');
    final retention = await c.setting('excel.auto_retention_count');
    final folder = await c.setting('excel.auto_directory');
    if (!mounted) return;
    setState(() {
      _enabled = enabled == '1';
      _interval.text = interval ?? '24';
      _retention.text = retention ?? '30';
      _folder = folder?.trim() ?? '';
    });
  }

  String get _effectiveFolder => _folder.isEmpty ? session.services.excelExportDirectory : _folder;

  Future<void> _pickFolder() async {
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'انتخاب پوشه خروجی خودکار اکسل',
      initialDirectory: _effectiveFolder,
      lockParentWindow: true,
    );
    if (picked != null && mounted) setState(() => _folder = picked);
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
      await s.services.catalog.putSetting('excel.auto_enabled', _enabled ? '1' : '0', s.actor);
      await s.services.catalog.putSetting('excel.auto_interval_hours', '$interval', s.actor);
      await s.services.catalog.putSetting('excel.auto_retention_count', '$retention', s.actor);
      await s.services.catalog.putSetting('excel.auto_directory', _folder, s.actor);
    }, success: 'تنظیمات خروجی خودکار اکسل ذخیره شد.');
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _runNow() async {
    final s = context.read<AppSession>();
    setState(() => _running = true);
    final row = await runAction(context, () => s.services.transfer.runAutoExport(actor: s.actor));
    if (!mounted) return;
    setState(() => _running = false);
    if (row == null) return;
    if (row['outcome'] == 'success') {
      GfToast.success(context, 'خروجی اکسل ذخیره شد: ${row['file_path']}');
    } else {
      GfToast.error(context, 'خروجی خودکار اکسل ناکام شد: ${row['message']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSession>();
    final m = widget.metrics;
    final folder = _effectiveFolder;
    return SettingsSectionCard(
      icon: Icons.schedule_outlined,
      title: 'خروجی خودکار اکسل',
      padding: m.cardPadding,
      footer: const SettingsFooterNote(
        'هنگام باز بودن برنامه، هر ۱۵ دقیقه بررسی می‌شود و در صورت رسیدن زمان، یک فایل اکسل کامل در پوشه انتخاب‌شده ذخیره می‌شود. '
        'فقط فایل‌هایی که خود برنامه ساخته است با رسیدن به حد نگهداری حذف می‌شوند.',
        warning: false,
      ),
      actions: [
        GfSecondaryButton(label: 'انصراف', icon: Icons.close, onPressed: _saving ? null : reload),
        if (s.can(Permissions.backupCreate))
          GfSecondaryButton(
            label: 'اجرای خروجی اکنون',
            icon: Icons.play_arrow_outlined,
            isLoading: _running,
            onPressed: _running ? null : _runNow,
          ),
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
            label: 'خروجی خودکار اکسل',
            subtitle: 'همه داده‌ها در فاصله تعیین‌شده به‌صورت خودکار در یک فایل اکسل ذخیره می‌شود.',
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
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
              label: 'تعداد فایل‌های نگهداری',
              prefixIcon: Icons.layers_outlined,
              controller: _retention,
              keyboardType: TextInputType.number,
            ),
          ),
          SizedBox(height: m.fieldGap),
          Text('پوشه ذخیره فایل‌ها', style: AppTypography.label),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: GfTextField(
                  key: ValueKey(folder),
                  initialValue: folder,
                  readOnly: true,
                  prefixIcon: Icons.folder_open_outlined,
                  hint: _folder.isEmpty ? 'پوشه پیش‌فرض' : null,
                ),
              ),
              const SizedBox(width: 8),
              GfIconButton(icon: Icons.drive_folder_upload_outlined, tooltip: 'تغییر پوشه', size: 48, onPressed: _pickFolder),
              const SizedBox(width: 8),
              GfIconButton(
                icon: Icons.restart_alt,
                tooltip: 'بازگشت به پوشه پیش‌فرض',
                size: 48,
                onPressed: _folder.isEmpty ? null : () => setState(() => _folder = ''),
              ),
              const SizedBox(width: 8),
              GfIconButton(
                icon: Icons.open_in_new,
                tooltip: 'باز کردن پوشه',
                size: 48,
                onPressed: () => _openPath(folder),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AutoExcelExportHistoryTable extends StatefulWidget {
  const _AutoExcelExportHistoryTable();

  @override
  State<_AutoExcelExportHistoryTable> createState() => _AutoExcelExportHistoryTableState();
}

class _AutoExcelExportHistoryTableState extends State<_AutoExcelExportHistoryTable> with RevisionReload {
  List<Map<String, Object?>> _history = const [];
  Set<String> _missing = const {};
  bool _loading = true;

  @override
  Future<void> reload() async {
    final history = await session.services.transfer.autoExportHistory();
    final missing = <String>{
      for (final h in history)
        if (h['outcome'] == 'success' && !await File(h['file_path'] as String).exists()) h['file_path'] as String,
    };
    if (!mounted) return;
    setState(() {
      _history = history;
      _missing = missing;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LedgerTable(
      title: 'سوابق خروجی خودکار اکسل',
      subtitle: '۱۰۰ خروجی آخر همراه با مسیر کامل فایل',
      itemLabel: 'خروجی',
      isLoading: _loading,
      minWidth: 900,
      emptyText: 'هنوز خروجی خودکاری انجام نشده است.',
      columns: const [
        LedgerColumn('زمان', flex: 2),
        LedgerColumn('وضعیت', flex: 2),
        LedgerColumn('مسیر فایل', flex: 6),
        LedgerColumn('معاملات', flex: 1, numeric: true),
        LedgerColumn('حجم', flex: 1, numeric: true),
        LedgerColumn('', width: LedgerRowMenu.width),
      ],
      rows: [
        for (final h in _history)
          () {
            final path = h['file_path'] as String;
            final ok = h['outcome'] == 'success';
            final missing = _missing.contains(path);
            final size = h['size_bytes'] as int?;
            return [
              Text(DateFormatFa.dateTime(DateTime.parse(h['created_at'] as String))),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Tooltip(
                  message: (h['message'] as String?) ?? '',
                  child: GfStatusBadge(
                    label: !ok ? 'ناموفق' : (missing ? 'حذف شده' : 'موفق'),
                    color: !ok ? AppColors.error : (missing ? AppColors.textMuted : AppColors.success),
                    compact: true,
                  ),
                ),
              ),
              Tooltip(
                message: path,
                child: SelectableText(
                  path,
                  style: AppTypography.caption,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                ),
              ),
              Text(ok ? '${h['transactions'] ?? 0}' : '—'),
              Text(size == null ? '—' : '${(size / 1024).ceil()} KB', textDirection: TextDirection.ltr),
              LedgerRowMenu(
                onSelected: (value) {
                  if (value == 'folder') _openPath(p.dirname(path));
                  if (value == 'copy') {
                    Clipboard.setData(ClipboardData(text: path));
                    GfToast.success(context, 'مسیر فایل کپی شد.');
                  }
                },
                items: [
                  gfPopupMenuItem(value: 'folder', label: 'باز کردن پوشه'),
                  gfPopupMenuItem(value: 'copy', label: 'کپی مسیر فایل'),
                ],
              ),
            ];
          }(),
      ],
    );
  }
}
