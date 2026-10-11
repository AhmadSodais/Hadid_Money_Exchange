import 'dart:io';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/app_font.dart';
import '../../core/database/app_database.dart';
import '../../core/sync/firebase_auth_session.dart';
import '../../core/sync/firebase_config.dart';
import '../../core/sync/sync_error_messages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/day_night_transition.dart';
import '../../core/utils/app_calendar.dart';
import '../../core/utils/file_helpers.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../providers/app_settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/trial_license_provider.dart';
import '../viewmodels/module_viewmodels.dart';
import '../viewmodels/sync_viewmodel.dart';
import '../widgets/app_shell.dart';
import '../widgets/sync_center_panel.dart';
import '../widgets/app_lock_settings_card.dart';
import '../widgets/users_roles_access_card.dart';
import '../../core/security/app_permissions.dart';

/// Sync/server error codes become a readable message; other text is shown
/// as is.
String _serverErrorText(String err) =>
    SyncErrorMessages.codeFor(err) == 'generic'
    ? err
    : SyncErrorMessages.display(err);

enum _SettingsSection {
  storeProfile,
  general,
  appLock,
  currencies,
  usersRoles,
  invoice,
  notifications,
  backup,
  firebase,
  trialLicense,
  systemTools,
  excelTransfer,
  syncCenter,
  appearance,
  about,
}

class _NavItem {
  const _NavItem(this.section, this.icon, this.labelKey);

  final _SettingsSection section;
  final IconData icon;
  final String labelKey;
}

class _DesktopMetrics {
  const _DesktopMetrics({
    required this.navWidth,
    required this.gap,
    required this.fieldGap,
    required this.logoSize,
    required this.cardPadding,
    required this.stackNav,
  });

  final double navWidth;
  final double gap;
  final double fieldGap;
  final double logoSize;
  final double cardPadding;
  final bool stackNav;

  factory _DesktopMetrics.of(double width) {
    if (width >= 1400) {
      return const _DesktopMetrics(
        navWidth: 300,
        gap: 24,
        fieldGap: 20,
        logoSize: 176,
        cardPadding: 24,
        stackNav: false,
      );
    }
    if (width >= 1100) {
      return const _DesktopMetrics(
        navWidth: 260,
        gap: 20,
        fieldGap: 16,
        logoSize: 148,
        cardPadding: 20,
        stackNav: false,
      );
    }
    if (width >= 720) {
      return const _DesktopMetrics(
        navWidth: 220,
        gap: 16,
        fieldGap: 12,
        logoSize: 120,
        cardPadding: 16,
        stackNav: false,
      );
    }
    return const _DesktopMetrics(
      navWidth: double.infinity,
      gap: 12,
      fieldGap: 12,
      logoSize: 100,
      cardPadding: 14,
      stackNav: true,
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsViewModel()..load(),
      child: const _SettingsView(),
    );
  }
}

class _SettingsView extends StatefulWidget {
  const _SettingsView();

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  /// Nav items shown in the sidebar. Hidden sections stay in the enum / switch
  /// so their widgets remain available without being displayed.
  static const _nav = <_NavItem>[
    _NavItem(
      _SettingsSection.storeProfile,
      Icons.storefront_outlined,
      'settings.storeProfile',
    ),
    _NavItem(_SettingsSection.general, Icons.tune_outlined, 'settings.general'),
    _NavItem(
      _SettingsSection.appLock,
      Icons.lock_outline,
      'settings.appLockTitle',
    ),
    _NavItem(
      _SettingsSection.usersRoles,
      Icons.manage_accounts_outlined,
      'settings.usersRoles',
    ),
    _NavItem(
      _SettingsSection.excelTransfer,
      Icons.table_chart_outlined,
      'settings.excelTransfer',
    ),
    _NavItem(
      _SettingsSection.syncCenter,
      Icons.cloud_sync_outlined,
      'settings.syncCenter',
    ),
    _NavItem(
      _SettingsSection.systemTools,
      Icons.admin_panel_settings_outlined,
      'settings.systemTools',
    ),
    _NavItem(
      _SettingsSection.appearance,
      Icons.palette_outlined,
      'settings.appearance',
    ),
    _NavItem(_SettingsSection.about, Icons.info_outline, 'settings.about'),
  ];

  final _search = TextEditingController();

  _SettingsSection _selected = _SettingsSection.storeProfile;
  String _query = '';
  bool _systemSectionUnlocked = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _select(_SettingsSection section) async {
    if (section == _SettingsSection.systemTools && !_systemSectionUnlocked) {
      final ok = await _unlockSystemSection(context);
      if (!ok || !mounted) return;
      _systemSectionUnlocked = true;
    }
    setState(() => _selected = section);
  }

  Future<bool> _unlockSystemSection(BuildContext context) async {
    final password = await _promptPasswordDialog(
      context,
      title: 'settings.firebaseUnlockTitle'.tr(),
      subtitle: 'settings.firebaseUnlockSubtitle'.tr(),
      fieldLabel: 'settings.firebasePassword'.tr(),
    );
    if (password == null) return false;
    final ok = FirebaseConfig.verifySectionPassword(password);
    if (!ok && context.mounted) {
      GfToast.error(context, 'settings.firebaseWrongPassword'.tr());
    }
    return ok;
  }

  bool _matches(_SettingsSection section) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final item = _nav.firstWhere((n) => n.section == section);
    return item.labelKey.tr().toLowerCase().contains(q);
  }

  void _onSearch(String value) {
    setState(() {
      _query = value.trim();
    });
    if (_query.isNotEmpty && !_matches(_selected)) {
      for (final item in _nav) {
        if (_matches(item.section)) {
          _select(item.section);
          break;
        }
      }
    }
  }

  Future<void> _openPath(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer', [path]);
      } else {
        await Process.start('xdg-open', [path]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();

    return PageScaffold(
      title: 'settings.title'.tr(),
      subtitle: 'settings.subtitle'.tr(),
      searchController: _search,
      searchHint: 'settings.searchHint'.tr(),
      onSearch: _onSearch,
      actions: _selected == _SettingsSection.syncCenter
          ? const [SyncNowButton()]
          : const [],
      floatingOverlay: vm.busy
          ? GfLoadingOverlay(message: 'settings.workingDb'.tr())
          : null,
      body: vm.loading
          ? const GfPageLoader()
          : LayoutBuilder(
              builder: (context, constraints) {
                final metrics = _DesktopMetrics.of(constraints.maxWidth);
                final auth = context.watch<AuthProvider>();
                final onlineEnabled = context
                    .watch<AppSettingsProvider>()
                    .onlineEnabled;
                bool isVisible(_SettingsSection section) => switch (section) {
                  _SettingsSection.usersRoles => auth.hasPermission(
                    AppPermissions.rolesManage,
                  ),
                  _SettingsSection.syncCenter =>
                    onlineEnabled &&
                        auth.hasPermission(AppPermissions.syncCenter),
                  _ => true,
                };
                final navItems = _nav
                    .where((item) => isVisible(item.section))
                    .toList();
                if (!isVisible(_selected)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _selected = _SettingsSection.storeProfile);
                    }
                  });
                }
                final nav = _SettingsNav(
                  items: navItems,
                  selected: _selected,
                  query: _query,
                  onSelected: _select,
                );
                final content = _SettingsContent(
                  selected: _selected,
                  metrics: metrics,
                  onOpenPath: _openPath,
                );
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

class _SettingsNav extends StatelessWidget {
  const _SettingsNav({
    required this.items,
    required this.selected,
    required this.query,
    required this.onSelected,
  });

  final List<_NavItem> items;
  final _SettingsSection selected;
  final String query;
  final ValueChanged<_SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Text(
              'settings.navTitle'.tr(),
              style: AppTypography.sectionTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: GfNoScrollbarGutter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                children: [
                  for (final item in items)
                    _NavTile(
                      icon: item.icon,
                      label: item.labelKey.tr(),
                      selected: selected == item.section,
                      dimmed:
                          query.isNotEmpty &&
                          !item.labelKey.tr().toLowerCase().contains(
                            query.toLowerCase(),
                          ),
                      onTap: () => onSelected(item.section),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dimmed = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.primarySoft : Colors.transparent,
        borderRadius: AppRadius.navItem,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.navItem,
          hoverColor: AppColors.hover,
          child: Opacity(
            opacity: dimmed ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.selected,
    required this.metrics,
    required this.onOpenPath,
  });

  final _SettingsSection selected;
  final _DesktopMetrics metrics;
  final Future<void> Function(String path) onOpenPath;

  @override
  Widget build(BuildContext context) {
    if (selected == _SettingsSection.syncCenter) {
      return const SyncCenterPanel(key: ValueKey(_SettingsSection.syncCenter));
    }
    final sections = switch (selected) {
      _SettingsSection.storeProfile => [_StoreProfileCard(metrics: metrics)],
      _SettingsSection.general => [_GeneralCard(metrics: metrics)],
      _SettingsSection.appLock => [
        AppLockSettingsCard(padding: metrics.cardPadding),
      ],
      _SettingsSection.currencies => [_CurrencyRegionalCard(metrics: metrics)],
      _SettingsSection.usersRoles => [
        UsersRolesAccessCard(padding: metrics.cardPadding),
      ],
      _SettingsSection.excelTransfer => [
        _ExcelImportExportCard(metrics: metrics),
      ],
      _SettingsSection.invoice => [_InvoiceCard(metrics: metrics)],
      _SettingsSection.notifications => [
        _PlaceholderCard(
          icon: Icons.notifications_outlined,
          title: 'settings.notifications'.tr(),
        ),
      ],
      _SettingsSection.backup => [
        _BackupCard(metrics: metrics, onOpenPath: onOpenPath),
        const _DangerZoneCard(),
      ],
      _SettingsSection.firebase => [_ServerLinkCard(metrics: metrics)],
      _SettingsSection.trialLicense => [
        _TrialStatusCard(metrics: metrics),
        _OwnerPasswordCard(metrics: metrics),
      ],
      _SettingsSection.systemTools => [
        _SystemToolsAccordion(metrics: metrics, onOpenPath: onOpenPath),
      ],
      _SettingsSection.syncCenter => const <Widget>[],
      _SettingsSection.appearance => [_AppearanceCard(metrics: metrics)],
      _SettingsSection.about => [_AboutCard(metrics: metrics)],
    };

    return ListView.separated(
      key: ValueKey(selected),
      itemCount: sections.length,
      separatorBuilder: (_, __) => SizedBox(height: metrics.gap),
      itemBuilder: (context, i) => sections[i],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.actions,
    this.footer,
    this.color,
    this.borderColor,
    this.padding = 20,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? footer;
  final Color? color;
  final Color? borderColor;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: padding * 0.7),
          child,
          if (actions != null) ...[
            SizedBox(height: padding * 0.7),
            Row(
              children: [
                const Spacer(),
                Flexible(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: actions!,
                  ),
                ),
              ],
            ),
          ],
          if (footer != null) ...[SizedBox(height: padding * 0.7), footer!],
        ],
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.left, required this.right, required this.gap});

  final Widget left;
  final Widget right;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: gap),
        Expanded(child: right),
      ],
    );
  }
}

class _StoreProfileCard extends StatelessWidget {
  const _StoreProfileCard({required this.metrics});

  final _DesktopMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    return _SectionCard(
      icon: Icons.storefront_outlined,
      title: 'settings.storeProfile'.tr(),
      padding: metrics.cardPadding,
      footer: Text(
        'settings.storeProfilePdfHint'.tr(),
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _FormRow(
                  gap: metrics.fieldGap,
                  left: GfTextField(
                    label: 'settings.storeName'.tr(),
                    required: true,
                    initialValue: vm.get('store_name'),
                    onChanged: (v) => vm.set('store_name', v),
                  ),
                  right: GfTextField(
                    label: 'settings.phone'.tr(),
                    required: true,
                    prefixIcon: Icons.phone_outlined,
                    initialValue: vm.get('store_phone'),
                    onChanged: (v) => vm.set('store_phone', v),
                  ),
                ),
                SizedBox(height: metrics.fieldGap),
                _FormRow(
                  gap: metrics.fieldGap,
                  left: GfTextField(
                    label: 'settings.email'.tr(),
                    required: true,
                    prefixIcon: Icons.mail_outline,
                    initialValue: vm.get('store_email'),
                    onChanged: (v) => vm.set('store_email', v),
                  ),
                  right: GfTextField(
                    label: 'settings.address'.tr(),
                    prefixIcon: Icons.place_outlined,
                    initialValue: vm.get('store_address'),
                    onChanged: (v) => vm.set('store_address', v),
                  ),
                ),
                SizedBox(height: metrics.fieldGap),
                _FormRow(
                  gap: metrics.fieldGap,
                  left: GfTextField(
                    label: 'settings.city'.tr(),
                    required: true,
                    initialValue: vm.get('store_city'),
                    onChanged: (v) => vm.set('store_city', v),
                  ),
                  right: GfTextField(
                    label: 'settings.country'.tr(),
                    initialValue: vm.get('store_country'),
                    onChanged: (v) => vm.set('store_country', v),
                  ),
                ),
                SizedBox(height: metrics.fieldGap),
                _FormRow(
                  gap: metrics.fieldGap,
                  left: GfTextField(
                    label: 'settings.taxNumber'.tr(),
                    prefixIcon: Icons.percent,
                    initialValue: vm.get('store_tax'),
                    onChanged: (v) => vm.set('store_tax', v),
                  ),
                  right: GfDropdown<String>(
                    label: 'settings.defaultCurrency'.tr(),
                    required: true,
                    value: () {
                      final saved = vm.get('base_currency_code');
                      if (vm.currencies.any((c) => c.code == saved)) {
                        return saved;
                      }
                      if (vm.currencies.isEmpty) return null;
                      final base = vm.currencies.where((c) => c.isBase);
                      return (base.isNotEmpty
                              ? base.first
                              : vm.currencies.first)
                          .code;
                    }(),
                    items: vm.currencies.map((c) => c.code).toList(),
                    labelBuilder: (code) => Formatters.currencyName(code),
                    onChanged: (code) {
                      if (code != null) vm.set('base_currency_code', code);
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: metrics.fieldGap),
          SizedBox(
            width: metrics.logoSize,
            child: _LogoUpload(
              size: metrics.logoSize,
              path: vm.get('store_logo'),
              onPicked: (path) => vm.set('store_logo', path),
            ),
          ),
        ],
      ),
      actions: [
        GfSecondaryButton(
          label: 'common.cancel'.tr(),
          icon: Icons.close,
          onPressed: vm.load,
        ),
        GfPrimaryButton(
          label: 'settings.saveChanges'.tr(),
          icon: Icons.save_outlined,
          onPressed: () {
            GfToast.success(context, 'settings.saved'.tr());
          },
        ),
      ],
    );
  }
}

class _LogoUpload extends StatelessWidget {
  const _LogoUpload({
    required this.size,
    required this.path,
    required this.onPicked,
  });

  final double size;
  final String path;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: AppColors.uploadBg,
            borderRadius: AppRadius.card,
            child: InkWell(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['png', 'jpg', 'jpeg'],
                );
                final picked = result?.files.single.path;
                if (picked == null) return;
                try {
                  final stored = await FileHelpers.copyImageToAppStorage(
                    source: File(picked),
                    imagesDir: AppDatabase.imagesDir,
                  );
                  onPicked(stored);
                } catch (e) {
                  if (context.mounted) GfToast.error(context, e.toString());
                }
              },
              borderRadius: AppRadius.card,
              child: Container(
                width: size,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.card,
                  border: Border.all(color: AppColors.uploadBorder),
                ),
                child: path.isNotEmpty
                    ? ClipRRect(
                        borderRadius: AppRadius.card,
                        child: GfImage(
                          path: path,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          borderRadius: AppRadius.lg,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: AppColors.textMuted,
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'settings.uploadLogo'.tr(),
                              style: AppTypography.caption,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'settings.uploadLogoHint'.tr(),
          style: AppTypography.caption,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CurrencyRegionalCard extends StatelessWidget {
  const _CurrencyRegionalCard({required this.metrics});

  final _DesktopMetrics metrics;

  static const _numberFormats = ['1,234.56', '1.234,56', '1 234.56'];
  static const _calendarTypes = AppCalendarType.values;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final app = context.watch<AppSettingsProvider>();
    final codes = vm.currencies.map((c) => c.code).toList();
    final currentCode = codes.contains(app.baseCurrency)
        ? app.baseCurrency
        : (codes.isEmpty ? null : codes.first);

    String calendarLabel(AppCalendarType t) => switch (t) {
      AppCalendarType.gregorian => 'settings.calendarTypes.gregorian'.tr(),
      AppCalendarType.solar => 'settings.calendarTypes.solar'.tr(),
      AppCalendarType.lunar => 'settings.calendarTypes.lunar'.tr(),
    };

    return _SectionCard(
      icon: Icons.public_outlined,
      title: 'settings.currencyRegional'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: GfDropdown<String>(
                  label: 'settings.defaultCurrency'.tr(),
                  required: true,
                  value: currentCode,
                  items: codes,
                  labelBuilder: (code) => Formatters.currencyName(code),
                  onChanged: (code) {
                    if (code != null) app.setBaseCurrency(code);
                  },
                ),
              ),
              SizedBox(width: metrics.fieldGap),
              Expanded(
                child: GfDropdown<String>(
                  label: 'settings.numberFormat'.tr(),
                  required: true,
                  value: _numberFormats.contains(vm.get('number_format'))
                      ? vm.get('number_format')
                      : _numberFormats.first,
                  items: _numberFormats,
                  onChanged: (v) {
                    if (v != null) vm.set('number_format', v);
                  },
                ),
              ),
              SizedBox(width: metrics.fieldGap),
              Expanded(
                child: GfDropdown<AppCalendarType>(
                  label: 'settings.calendarType'.tr(),
                  required: true,
                  value: app.calendarType,
                  items: _calendarTypes,
                  labelBuilder: calendarLabel,
                  prefixIcon: Icons.calendar_month_outlined,
                  onChanged: (v) {
                    if (v != null) app.setCalendarType(v);
                  },
                ),
              ),
              SizedBox(width: metrics.fieldGap),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'settings.useLocalTime'.tr(),
                          style: AppTypography.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Switch(
                        value: vm.get('use_local_time', '1') != '0',
                        onChanged: (v) =>
                            vm.set('use_local_time', v ? '1' : '0'),
                        activeThumbColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: metrics.fieldGap * 0.5),
          Text(
            'settings.calendarTypeHint'.tr(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.metrics, required this.onOpenPath});

  final _DesktopMetrics metrics;
  final Future<void> Function(String path) onOpenPath;

  String _stamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
  }

  Future<void> _markBackup(BuildContext context, SettingsViewModel vm) async {
    await vm.set('last_backup_at', DateTime.now().toIso8601String());
  }

  Future<void> _exportDatabase(
    BuildContext context,
    SettingsViewModel vm,
  ) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'settings.chooseSaveLocation'.tr(),
      fileName: 'glassflow_backup_${_stamp()}.db',
      type: FileType.custom,
      allowedExtensions: const ['db', 'sqlite'],
      lockParentWindow: true,
    );
    if (path == null || path.isEmpty) return;
    final err = await vm.exportDatabaseTo(path);
    if (!context.mounted) return;
    if (err != null) {
      GfToast.error(context, err);
      return;
    }
    await _markBackup(context, vm);
    if (!context.mounted) return;
    GfToast.success(
      context,
      'settings.exportComplete'.tr(namedArgs: {'path': vm.message ?? path}),
    );
  }

  Future<void> _importDatabase(
    BuildContext context,
    SettingsViewModel vm,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'settings.chooseDbFile'.tr(),
      type: FileType.custom,
      allowedExtensions: const ['db', 'sqlite'],
      lockParentWindow: true,
    );
    final source = result?.files.single.path;
    if (source == null) return;
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.restoreTitle'.tr(),
      message: 'settings.restoreMessage'.tr(),
      danger: true,
      confirmLabel: 'settings.importDatabase'.tr(),
    );
    if (!ok) return;
    final err = await vm.restore(source);
    if (!context.mounted) return;
    err == null
        ? GfToast.success(context, 'settings.restoredHint'.tr())
        : GfToast.error(context, err);
  }

  Future<void> _fetchFromServer(
    BuildContext context,
    SettingsViewModel vm,
  ) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.fetchFromServerTitle'.tr(),
      message: 'settings.fetchFromServerMessage'.tr(),
      confirmLabel: 'settings.fetchFromServer'.tr(),
    );
    if (!ok) return;
    final err = await vm.restoreFromServer();
    if (!context.mounted) return;
    if (err == 'empty') {
      GfToast.error(context, 'settings.fetchFromServerEmpty'.tr());
      return;
    }
    if (err != null) {
      GfToast.error(context, _serverErrorText(err));
      return;
    }
    final parts = (vm.message ?? '').split('|');
    // products|transactions|customers|companies|...|orders|purchases|total
    final total = parts.isNotEmpty ? parts.last : '0';
    final customers = parts.length > 2 ? parts[2] : '0';
    final companies = parts.length > 3 ? parts[3] : '0';
    GfToast.success(
      context,
      'settings.fetchFromServerComplete'.tr(
        namedArgs: {
          'count': total,
          'customers': customers,
          'companies': companies,
        },
      ),
    );
  }

  Future<void> _pushToServer(BuildContext context, SettingsViewModel vm) async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.pushToServerTitle'.tr(),
      message: 'settings.pushToServerMessage'.tr(),
      confirmLabel: 'settings.pushToServer'.tr(),
    );
    if (!ok) return;
    final err = await vm.pushAllToServer();
    if (!context.mounted) return;
    if (err == 'empty') {
      GfToast.error(context, 'settings.pushToServerEmpty'.tr());
      return;
    }
    if (err != null && err != 'partial' && err != 'offline') {
      GfToast.error(context, _serverErrorText(err));
      return;
    }
    if (err == 'offline') {
      GfToast.error(context, vm.error ?? 'settings.pushToServerOffline'.tr());
      return;
    }
    final parts = (vm.message ?? '').split('|');
    final queued = parts.isNotEmpty ? parts[0] : '0';
    final synced = parts.length > 1 ? parts[1] : '0';
    final failed = parts.length > 2 ? parts[2] : '0';
    if (err == 'partial') {
      GfToast.warning(
        context,
        'settings.pushToServerPartial'.tr(
          namedArgs: {'queued': queued, 'synced': synced, 'failed': failed},
        ),
      );
      return;
    }
    GfToast.success(
      context,
      'settings.pushToServerComplete'.tr(
        namedArgs: {'queued': queued, 'synced': synced},
      ),
    );
  }

  Future<void> _importConvertedJson(
    BuildContext context,
    SettingsViewModel vm,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'settings.importConvertedJson'.tr(),
      type: FileType.custom,
      allowedExtensions: const ['json'],
      lockParentWindow: true,
    );
    final source = result?.files.single.path;
    if (source == null) return;
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.importConvertedJsonTitle'.tr(),
      message: 'settings.importConvertedJsonMessage'.tr(),
      confirmLabel: 'settings.importConvertedJson'.tr(),
    );
    if (!ok) return;
    final err = await vm.importConvertedJson(source);
    if (!context.mounted) return;
    if (err == 'empty') {
      GfToast.error(context, 'settings.importConvertedJsonEmpty'.tr());
      return;
    }
    if (err != null) {
      GfToast.error(context, err);
      return;
    }
    final parts = (vm.message ?? '').split('|');
    // Full glassflow export:
    // products|transactions|customers|companies|...|orders|purchases|total
    // Converted accounts JSON: customers|products|movements|total
    final isFullExport = parts.length >= 12;
    if (isFullExport) {
      GfToast.success(
        context,
        'settings.importConvertedJsonCompleteFull'.tr(
          namedArgs: {
            'total': parts.last,
            'customers': parts[2],
            'companies': parts[3],
            'products': parts[0],
            'orders': parts[parts.length - 3],
            'purchases': parts[parts.length - 2],
          },
        ),
      );
      return;
    }
    final customers = parts.isNotEmpty ? parts[0] : '0';
    final products = parts.length > 1 ? parts[1] : '0';
    final movements = parts.length > 2 ? parts[2] : '0';
    GfToast.success(
      context,
      'settings.importConvertedJsonComplete'.tr(
        namedArgs: {
          'customers': customers,
          'products': products,
          'movements': movements,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    String lastBackupLabel = 'settings.noBackupYet'.tr();
    final raw = vm.get('last_backup_at');
    final hasBackup = raw.isNotEmpty;
    if (hasBackup) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) lastBackupLabel = Formatters.dateTime(parsed);
    }

    String lastCloudLabel = 'settings.noCloudRestoreYet'.tr();
    final cloudRaw = vm.get('last_cloud_restore_at');
    final hasCloud = cloudRaw.isNotEmpty;
    if (hasCloud) {
      final parsed = DateTime.tryParse(cloudRaw);
      if (parsed != null) lastCloudLabel = Formatters.dateTime(parsed);
    }

    String lastCloudPushLabel = 'settings.noCloudPushYet'.tr();
    final cloudPushRaw = vm.get('last_cloud_push_at');
    final hasCloudPush = cloudPushRaw.isNotEmpty;
    if (hasCloudPush) {
      final parsed = DateTime.tryParse(cloudPushRaw);
      if (parsed != null) lastCloudPushLabel = Formatters.dateTime(parsed);
    }

    return _SectionCard(
      icon: Icons.folder_outlined,
      title: 'settings.dataBackup'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormRow(
            gap: metrics.fieldGap,
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'settings.databaseLocation'.tr(),
                  style: AppTypography.label,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: GfTextField(
                        initialValue: AppDatabase.databasePath,
                        readOnly: true,
                        prefixIcon: Icons.folder_open_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GfIconButton(
                      icon: Icons.open_in_new,
                      tooltip: 'settings.openFolder'.tr(),
                      size: 48,
                      onPressed: () =>
                          onOpenPath(AppDatabase.appSupportDir.path),
                    ),
                  ],
                ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('settings.lastBackup'.tr(), style: AppTypography.label),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      hasBackup ? Icons.check_circle : Icons.schedule_outlined,
                      size: 18,
                      color: hasBackup
                          ? AppColors.success
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lastBackupLabel,
                            style: AppTypography.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            hasBackup
                                ? 'settings.backupUpToDate'.tr()
                                : 'settings.exportPickHint'.tr(),
                            style: AppTypography.caption.copyWith(
                              color: hasBackup
                                  ? AppColors.success
                                  : AppColors.textMuted,
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
          SizedBox(height: metrics.gap),
          _TransferGroup(
            title: 'settings.cloudRestore'.tr(),
            children: [
              _TransferAction(
                icon: Icons.cloud_download_outlined,
                title: 'settings.fetchFromServer'.tr(),
                hint: 'settings.cloudRestoreHint'.tr(),
                buttonLabel: vm.busy
                    ? 'common.loading'.tr()
                    : 'settings.fetchFromServer'.tr(),
                onPressed: vm.busy ? null : () => _fetchFromServer(context, vm),
              ),
              SizedBox(height: metrics.fieldGap),
              _TransferAction(
                icon: Icons.cloud_upload_outlined,
                title: 'settings.pushToServer'.tr(),
                hint: 'settings.pushToServerHint'.tr(),
                buttonLabel: vm.busy
                    ? 'common.loading'.tr()
                    : 'settings.pushToServer'.tr(),
                onPressed: vm.busy ? null : () => _pushToServer(context, vm),
              ),
              SizedBox(height: metrics.fieldGap),
              _TransferAction(
                icon: Icons.upload_file_outlined,
                title: 'settings.importConvertedJson'.tr(),
                hint: 'settings.importConvertedJsonHint'.tr(),
                buttonLabel: vm.busy
                    ? 'common.loading'.tr()
                    : 'settings.importConvertedJson'.tr(),
                onPressed: vm.busy
                    ? null
                    : () => _importConvertedJson(context, vm),
              ),
              SizedBox(height: metrics.fieldGap),
              Row(
                children: [
                  Icon(
                    hasCloud ? Icons.cloud_done_outlined : Icons.cloud_outlined,
                    size: 18,
                    color: hasCloud ? AppColors.success : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'settings.lastCloudRestore'.tr(),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(lastCloudLabel, style: AppTypography.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: metrics.fieldGap),
              Row(
                children: [
                  Icon(
                    hasCloudPush
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_upload_outlined,
                    size: 18,
                    color: hasCloudPush
                        ? AppColors.success
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'settings.lastCloudPush'.tr(),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          lastCloudPushLabel,
                          style: AppTypography.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: metrics.gap),
          _FormRow(
            gap: metrics.fieldGap,
            left: _TransferGroup(
              title: 'settings.exportData'.tr(),
              children: [
                _TransferAction(
                  icon: Icons.storage_outlined,
                  title: 'settings.exportDatabase'.tr(),
                  hint: 'settings.exportDatabaseHint'.tr(),
                  buttonLabel: 'settings.exportDatabase'.tr(),
                  onPressed: () => _exportDatabase(context, vm),
                ),
              ],
            ),
            right: _TransferGroup(
              title: 'settings.importData'.tr(),
              children: [
                _TransferAction(
                  icon: Icons.dns_outlined,
                  title: 'settings.importDatabase'.tr(),
                  hint: 'settings.importDatabaseHint'.tr(),
                  buttonLabel: 'settings.importDatabase'.tr(),
                  onPressed: () => _importDatabase(context, vm),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.fieldGap),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GfSecondaryButton(
              label: 'settings.openDataFolder'.tr(),
              icon: Icons.folder_open_outlined,
              onPressed: () => onOpenPath(AppDatabase.appSupportDir.path),
            ),
          ),
        ],
      ),
      footer: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'settings.backupHint'.tr(),
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferGroup extends StatelessWidget {
  const _TransferGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTypography.label),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

/// Dedicated System item: import / export business data as Excel.
class _ExcelImportExportCard extends StatelessWidget {
  const _ExcelImportExportCard({required this.metrics});

  final _DesktopMetrics metrics;

  String _stamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
  }

  Future<void> _exportExcel(BuildContext context, SettingsViewModel vm) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'settings.chooseSaveLocation'.tr(),
      fileName: 'pos_export_${_stamp()}.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      lockParentWindow: true,
    );
    if (path == null || path.isEmpty) return;
    final err = await vm.exportExcelTo(path);
    if (!context.mounted) return;
    if (err != null) {
      GfToast.error(context, err);
      return;
    }
    GfToast.success(
      context,
      'settings.exportComplete'.tr(namedArgs: {'path': vm.message ?? path}),
    );
  }

  Future<void> _importExcel(BuildContext context, SettingsViewModel vm) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'settings.chooseExcelFile'.tr(),
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
      lockParentWindow: true,
    );
    final source = result?.files.single.path;
    if (source == null) return;
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.importExcelTitle'.tr(),
      message: 'settings.importExcelMessage'.tr(),
      confirmLabel: 'settings.importExcel'.tr(),
    );
    if (!ok) return;
    final err = await vm.importSpreadsheet(source);
    if (!context.mounted) return;
    if (err != null) {
      GfToast.error(context, err);
      return;
    }
    final parts = (vm.message ?? '0').split('|');
    final count = parts.isNotEmpty ? parts.first : '0';
    final tables = parts.length > 1 ? parts[1] : '';
    GfToast.success(
      context,
      'settings.importedRowsDetail'.tr(
        namedArgs: {
          'count': count,
          'tables': tables == '-' || tables.isEmpty ? '—' : tables,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    return _SectionCard(
      icon: Icons.table_chart_outlined,
      title: 'settings.excelTransfer'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'settings.excelTransferHint'.tr(),
            style: AppTypography.subtitle,
          ),
          SizedBox(height: metrics.gap),
          _FormRow(
            gap: metrics.fieldGap,
            left: _TransferAction(
              icon: Icons.table_view_outlined,
              title: 'settings.exportExcel'.tr(),
              hint: 'settings.exportExcelHint'.tr(),
              buttonLabel: 'settings.exportExcel'.tr(),
              onPressed: () => _exportExcel(context, vm),
            ),
            right: _TransferAction(
              icon: Icons.grid_on_outlined,
              title: 'settings.importExcel'.tr(),
              hint: 'settings.importExcelHint'.tr(),
              buttonLabel: 'settings.importExcel'.tr(),
              onPressed: () => _importExcel(context, vm),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferAction extends StatelessWidget {
  const _TransferAction({
    required this.icon,
    required this.title,
    required this.hint,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: AppRadius.input,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: AppTypography.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          GfSecondaryButton(
            label: buttonLabel,
            onPressed: onPressed,
            expanded: true,
          ),
        ],
      ),
    );
  }
}

class _ServerLinkCard extends StatefulWidget {
  const _ServerLinkCard({required this.metrics});

  final _DesktopMetrics metrics;

  @override
  State<_ServerLinkCard> createState() => _ServerLinkCardState();
}

class _ServerLinkCardState extends State<_ServerLinkCard> {
  late final TextEditingController _link;
  late final TextEditingController _apiKey;
  late final TextEditingController _email;
  late final TextEditingController _password;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _link = TextEditingController(
      text: FirebaseConfig.isCustom ? FirebaseConfig.displayLink : '',
    );
    _apiKey = TextEditingController(
      text: FirebaseConfig.hasApiKey ? FirebaseConfig.apiKey : '',
    );
    _email = TextEditingController(text: FirebaseAuthSession.email ?? '');
    _password = TextEditingController();
  }

  @override
  void dispose() {
    _link.dispose();
    _apiKey.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _saveLink() async {
    final text = _link.text.trim();
    if (text.isEmpty) {
      GfToast.error(context, 'settings.firebaseLinkRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseConfig.saveLink(text);
      await FirebaseConfig.saveApiKey(_apiKey.text);
      if (!mounted) return;
      setState(() {
        _link.text = FirebaseConfig.displayLink;
        _busy = false;
      });
      GfToast.success(context, 'settings.firebaseLinkSaved'.tr());
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GfToast.error(context, e.toString());
    }
  }

  Future<void> _reset() async {
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.firebaseResetTitle'.tr(),
      message: 'settings.firebaseResetMessage'.tr(),
      danger: true,
      confirmLabel: 'settings.firebaseReset'.tr(),
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await FirebaseAuthSession.signOut();
      await FirebaseConfig.clear();
      if (!mounted) return;
      setState(() {
        _link.text = '';
        _apiKey.text = '';
        _email.text = '';
        _password.text = '';
        _busy = false;
      });
      GfToast.success(context, 'settings.firebaseLinkReset'.tr());
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GfToast.error(context, e.toString());
    }
  }

  Future<void> _ensureConfigSaved() async {
    final link = _link.text.trim();
    if (link.isNotEmpty) {
      await FirebaseConfig.saveLink(link);
      _link.text = FirebaseConfig.displayLink;
    }
    await FirebaseConfig.saveApiKey(_apiKey.text);
  }

  Future<void> _signIn({required bool register}) async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      GfToast.error(context, 'errors.formFixFields'.tr());
      return;
    }
    if (_apiKey.text.trim().isEmpty && !FirebaseConfig.hasApiKey) {
      GfToast.error(context, 'settings.firebaseApiKeyRequired'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await _ensureConfigSaved();
      if (register) {
        await FirebaseAuthSession.signUp(email: email, password: password);
      } else {
        await FirebaseAuthSession.signIn(email: email, password: password);
      }
      if (!mounted) return;
      setState(() {
        _password.clear();
        _busy = false;
      });
      GfToast.success(
        context,
        register
            ? 'settings.firebaseAuthAccountCreated'.tr()
            : 'settings.firebaseAuthSignedIn'.tr(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GfToast.error(context, SyncErrorMessages.display(e.toString()));
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuthSession.signOut();
      if (!mounted) return;
      setState(() => _busy = false);
      GfToast.success(context, 'settings.firebaseAuthSignedOut'.tr());
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      GfToast.error(context, SyncErrorMessages.display(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    final signedIn = FirebaseAuthSession.isSignedIn;
    return _SectionCard(
      icon: Icons.link_rounded,
      title: 'settings.firebaseLink'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.firebaseLinkHint'.tr(), style: AppTypography.subtitle),
          SizedBox(height: metrics.fieldGap),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.input,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  signedIn
                      ? Icons.verified_user_outlined
                      : (FirebaseConfig.isCustom
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_outlined),
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    signedIn
                        ? 'settings.firebaseAuthSignedInAs'.tr(
                            namedArgs: {
                              'email': FirebaseAuthSession.email ?? '',
                            },
                          )
                        : (FirebaseConfig.isCustom
                              ? 'settings.firebaseCustomActive'.tr()
                              : 'settings.firebaseDefaultActive'.tr()),
                    style: AppTypography.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.fieldGap),
          GfTextField(
            controller: _link,
            label: 'settings.firebaseLinkLabel'.tr(),
            hint: AppConstants.serverLinkHint,
            prefixIcon: Icons.http_rounded,
          ),
          SizedBox(height: metrics.fieldGap),
          GfTextField(
            controller: _apiKey,
            label: 'settings.firebaseApiKeyLabel'.tr(),
            hint: 'settings.firebaseApiKeyHint'.tr(),
            prefixIcon: Icons.key_outlined,
          ),
          SizedBox(height: metrics.gap),
          Wrap(
            spacing: metrics.fieldGap,
            runSpacing: metrics.fieldGap,
            children: [
              GfPrimaryButton(
                label: _busy
                    ? 'common.loading'.tr()
                    : 'settings.firebaseSave'.tr(),
                icon: Icons.save_outlined,
                onPressed: _busy ? null : _saveLink,
              ),
              GfSecondaryButton(
                label: 'settings.firebaseReset'.tr(),
                icon: Icons.restart_alt_outlined,
                onPressed: _busy ? null : _reset,
              ),
            ],
          ),
          SizedBox(height: metrics.gap),
          Divider(color: AppColors.border),
          SizedBox(height: metrics.fieldGap),
          Text(
            'settings.firebaseAuthTitle'.tr(),
            style: AppTypography.bodySemiBold,
          ),
          const SizedBox(height: 6),
          Text(
            'settings.firebaseAuthHint'.tr(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          SizedBox(height: metrics.fieldGap),
          if (!signedIn) ...[
            GfTextField(
              controller: _email,
              label: 'settings.firebaseAuthEmail'.tr(),
              prefixIcon: Icons.email_outlined,
            ),
            SizedBox(height: metrics.fieldGap),
            GfTextField(
              controller: _password,
              label: 'settings.firebaseAuthPassword'.tr(),
              obscureText: _obscurePassword,
              prefixIcon: Icons.lock_outline,
              suffix: IconButton(
                tooltip: _obscurePassword
                    ? 'auth.showPassword'.tr()
                    : 'auth.hidePassword'.tr(),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            SizedBox(height: metrics.gap),
            Wrap(
              spacing: metrics.fieldGap,
              runSpacing: metrics.fieldGap,
              children: [
                GfPrimaryButton(
                  label: 'settings.firebaseAuthSignIn'.tr(),
                  icon: Icons.login_rounded,
                  onPressed: _busy ? null : () => _signIn(register: false),
                ),
                GfSecondaryButton(
                  label: 'settings.firebaseAuthSignUp'.tr(),
                  icon: Icons.person_add_alt_1_outlined,
                  onPressed: _busy ? null : () => _signIn(register: true),
                ),
              ],
            ),
          ] else ...[
            GfSecondaryButton(
              label: 'settings.firebaseAuthSignOut'.tr(),
              icon: Icons.logout_rounded,
              onPressed: _busy ? null : _signOut,
            ),
          ],
        ],
      ),
      footer: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              FirebaseConfig.isCustom
                  ? 'settings.firebaseLinkFooter'.tr(
                      namedArgs: {'link': FirebaseConfig.displayLink},
                    )
                  : 'settings.firebaseDefaultActive'.tr(),
              style: AppTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerZoneCard extends StatelessWidget {
  const _DangerZoneCard();

  Future<void> _clearServer(BuildContext context) async {
    final vm = context.read<SettingsViewModel>();
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.clearServerTitle'.tr(),
      message: 'settings.clearServerMessage'.tr(),
      danger: true,
      confirmLabel: 'settings.clearServerData'.tr(),
    );
    if (!ok) return;
    final err = await vm.clearServerData();
    if (!context.mounted) return;
    err == null
        ? GfToast.success(context, 'settings.clearServerDone'.tr())
        : GfToast.error(context, _serverErrorText(err));
  }

  Future<void> _clearOffline(BuildContext context) async {
    final vm = context.read<SettingsViewModel>();
    final ok = await GfConfirmDialog.show(
      context,
      title: 'settings.clearOfflineTitle'.tr(),
      message: 'settings.clearOfflineMessage'.tr(),
      danger: true,
      confirmLabel: 'settings.clearOfflineData'.tr(),
    );
    if (!ok) return;
    final err = await vm.clearOfflineData();
    if (!context.mounted) return;
    err == null
        ? GfToast.success(context, 'settings.clearOfflineDone'.tr())
        : GfToast.error(context, err);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    return _SectionCard(
      icon: Icons.warning_amber_rounded,
      title: 'settings.dangerZone'.tr(),
      color: AppColors.dangerZoneBg,
      borderColor: AppColors.dangerZoneBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.dangerZoneHint'.tr(), style: AppTypography.subtitle),
          const SizedBox(height: 14),
          _FormRow(
            gap: 12,
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'settings.clearServerData'.tr(),
                  style: AppTypography.bodySemiBold,
                ),
                const SizedBox(height: 4),
                Text(
                  'settings.clearServerHint'.tr(),
                  style: AppTypography.caption,
                ),
                const SizedBox(height: 10),
                GfDangerButton(
                  label: vm.busy
                      ? 'common.loading'.tr()
                      : 'settings.clearServerData'.tr(),
                  icon: Icons.cloud_off_outlined,
                  onPressed: vm.busy ? null : () => _clearServer(context),
                  expanded: true,
                ),
              ],
            ),
            right: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'settings.clearOfflineData'.tr(),
                  style: AppTypography.bodySemiBold,
                ),
                const SizedBox(height: 4),
                Text(
                  'settings.clearOfflineHint'.tr(),
                  style: AppTypography.caption,
                ),
                const SizedBox(height: 10),
                GfDangerButton(
                  label: vm.busy
                      ? 'common.loading'.tr()
                      : 'settings.clearOfflineData'.tr(),
                  icon: Icons.delete_forever_outlined,
                  onPressed: vm.busy ? null : () => _clearOffline(context),
                  expanded: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralCard extends StatelessWidget {
  const _GeneralCard({required this.metrics});

  final _DesktopMetrics metrics;

  String _calendarLabel(AppCalendarType t) => switch (t) {
    AppCalendarType.gregorian => 'settings.calendarTypes.gregorian'.tr(),
    AppCalendarType.solar => 'settings.calendarTypes.solar'.tr(),
    AppCalendarType.lunar => 'settings.calendarTypes.lunar'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final app = context.watch<AppSettingsProvider>();

    return _SectionCard(
      icon: Icons.tune_outlined,
      title: 'settings.general'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.operations'.tr(), style: AppTypography.subtitle),
          SizedBox(height: metrics.fieldGap),
          GfToggleCard(
            label: 'settings.disableOnline'.tr(),
            subtitle: 'settings.disableOnlineHint'.tr(),
            value: !app.onlineEnabled,
            onChanged: (v) async {
              await app.setOnlineEnabled(!v);
              await vm.set('online_enabled', v ? '0' : '1');
              if (context.mounted) {
                context.read<SyncViewModel>().refreshOnlineFlag();
              }
            },
          ),
          SizedBox(height: metrics.fieldGap),
          GfToggleCard(
            label: 'settings.limitToStock'.tr(),
            subtitle: 'settings.limitToStockHint'.tr(),
            value: app.limitToStock,
            onChanged: (v) async {
              await app.setLimitToStock(v);
              await vm.set('limit_to_stock', v ? '1' : '0');
              // Keep legacy key inverted for older backups.
              await vm.set('allow_oversell', v ? '0' : '1');
            },
          ),
          SizedBox(height: metrics.fieldGap),
          GfToggleCard(
            label: 'settings.reducedMotion'.tr(),
            subtitle: 'settings.reducedMotionHint'.tr(),
            value: app.reducedMotion,
            onChanged: (v) async {
              await app.setReducedMotion(v);
              await vm.set('reduced_motion', v ? '1' : '0');
            },
          ),
          SizedBox(height: metrics.fieldGap),
          Text('settings.businessType'.tr(), style: AppTypography.subtitle),
          SizedBox(height: metrics.fieldGap),
          GfDropdown<String>(
            label: 'settings.storeType'.tr(),
            items: StoreTypes.all,
            value: app.storeType,
            labelBuilder: (v) => 'settings.storeTypes.$v'.tr(),
            prefixIcon: Icons.store_mall_directory_outlined,
            onChanged: (v) async {
              if (v == null) return;
              await app.setStoreType(v);
              await vm.set('store_type', v);
            },
          ),
          SizedBox(height: metrics.fieldGap),
          Text('settings.calendarType'.tr(), style: AppTypography.subtitle),
          SizedBox(height: metrics.fieldGap),
          GfDropdown<AppCalendarType>(
            label: 'settings.calendarType'.tr(),
            required: true,
            value: app.calendarType,
            items: AppCalendarType.values,
            labelBuilder: _calendarLabel,
            prefixIcon: Icons.calendar_month_outlined,
            onChanged: (v) async {
              if (v == null) return;
              await app.setCalendarType(v);
              await vm.set(AppConstants.prefCalendarType, v.storageKey);
            },
          ),
          SizedBox(height: metrics.fieldGap * 0.5),
          Text(
            'settings.calendarTypeHint'.tr(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.metrics});

  final _DesktopMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    return _SectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'settings.invoiceSettings'.tr(),
      padding: metrics.cardPadding,
      child: Row(
        children: [
          Expanded(
            child: GfTextField(
              label: 'settings.invoicePrefix'.tr(),
              initialValue: vm.get('invoice_prefix', 'INV'),
              onChanged: (v) => vm.set('invoice_prefix', v),
            ),
          ),
          SizedBox(width: metrics.fieldGap),
          Expanded(
            child: GfTextField(
              label: 'settings.orderPrefix'.tr(),
              initialValue: vm.get('order_prefix', 'ORD'),
              onChanged: (v) => vm.set('order_prefix', v),
            ),
          ),
          SizedBox(width: metrics.fieldGap),
          Expanded(
            child: GfTextField(
              label: 'settings.jobPrefix'.tr(),
              initialValue: vm.get('job_prefix', 'JOB'),
              onChanged: (v) => vm.set('job_prefix', v),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.metrics});

  final _DesktopMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppSettingsProvider>();
    return _SectionCard(
      icon: Icons.palette_outlined,
      title: 'settings.appearance'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'settings.appearanceSubtitle'.tr(),
            style: AppTypography.subtitle,
          ),
          SizedBox(height: metrics.fieldGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final options = [
                for (final variant in AppThemeVariant.values)
                  _ThemeOptionTile(
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

/// Theme choice with a miniature preview of the app in that theme.
class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.variant,
    required this.selected,
    required this.onSelected,
  });

  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onSelected;

  (String, String, IconData) get _info => switch (variant) {
    AppThemeVariant.light => (
      'settings.lightMode',
      'settings.lightModeHint',
      Icons.light_mode_outlined,
    ),
    AppThemeVariant.dark => (
      'settings.darkMode',
      'settings.darkModeHint',
      Icons.dark_mode_outlined,
    ),
    AppThemeVariant.hadid => (
      'settings.hadidDarkMode',
      'settings.hadidDarkModeHint',
      Icons.nights_stay_outlined,
    ),
  };

  void _select(BuildContext context) {
    if (selected) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      DayNightThemeTransition.revealFrom(
        context,
        globalCenter: box.localToGlobal(box.size.center(Offset.zero)),
      );
    }
    onSelected();
  }

  @override
  Widget build(BuildContext context) {
    final (labelKey, hintKey, icon) = _info;
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.input,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _select(context),
        hoverColor: AppColors.hover,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ThemePreview(variant: variant),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      labelKey.tr(),
                      style: AppTypography.bodySemiBold.copyWith(
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        'settings.themeSelected'.tr(),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                hintKey.tr(),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed-color mock of the app shell (sidebar, header, cards) for a theme.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.variant});

  final AppThemeVariant variant;

  @override
  Widget build(BuildContext context) {
    final light = variant.isLight;
    final d = variant.darkPalette;
    final bg = light ? AppColors.lightBackground : d.background;
    final sidebar = light ? AppColors.lightSidebar : d.sidebar;
    final card = light ? AppColors.lightCard : d.card;
    final border = light ? AppColors.lightBorder : d.border;
    final primary = light ? AppColors.lightPrimary : d.primary;
    final text = light ? AppColors.lightTextMuted : d.textMuted;
    final hadid = variant == AppThemeVariant.hadid;

    Widget bar(double widthFactor, Color color, {double height = 5}) =>
        FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: AppRadius.pill,
            ),
          ),
        );

    Widget miniCard({required bool accent}) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            bar(0.55, text.withValues(alpha: 0.6), height: 4),
            bar(
              accent ? 0.8 : 0.4,
              accent ? primary : text.withValues(alpha: 0.35),
              height: 6,
            ),
          ],
        ),
      ),
    );

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hadid ? null : bg,
          gradient: hadid
              ? const LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [Color(0xFF0B2A3F), Color(0xFF061826)],
                )
              : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 34,
              color: sidebar,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              child: Column(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: hadid ? null : primary,
                      gradient: hadid
                          ? const LinearGradient(
                              colors: [Color(0xFF8EF0C4), Color(0xFF27D3DD)],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < 3; i++) ...[
                    bar(
                      1,
                      i == 0
                          ? primary.withValues(alpha: 0.6)
                          : text.withValues(alpha: 0.35),
                      height: 4,
                    ),
                    const SizedBox(height: 5),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    bar(0.45, text.withValues(alpha: 0.7), height: 6),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          miniCard(accent: true),
                          const SizedBox(width: 6),
                          miniCard(accent: false),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [miniCard(accent: false)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrialStatusCard extends StatelessWidget {
  const _TrialStatusCard({required this.metrics});

  final _DesktopMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final license = context.watch<TrialLicenseProvider>();
    final statusLabel = !license.trialEnabled
        ? 'settings.trial.statusDisabled'.tr()
        : license.isUnlocked
        ? 'settings.trial.statusUnlocked'.tr()
        : license.isLocked
        ? 'settings.trial.statusLocked'.tr()
        : 'settings.trial.statusActive'.tr(
            namedArgs: {'days': '${license.daysRemaining}'},
          );

    return _SectionCard(
      icon: Icons.lock_clock_outlined,
      title: 'settings.trial.title'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.trial.subtitle'.tr(), style: AppTypography.subtitle),
          SizedBox(height: metrics.fieldGap),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.input,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  license.isUnlocked
                      ? Icons.verified_outlined
                      : Icons.hourglass_bottom_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(statusLabel, style: AppTypography.bodyMedium),
                ),
              ],
            ),
          ),
          SizedBox(height: metrics.gap),
          GfToggleCard(
            label: 'settings.trial.enableLock'.tr(),
            subtitle: 'settings.trial.enableLockHint'.tr(),
            value: license.trialEnabled,
            onChanged: (v) => license.setTrialEnabled(v),
          ),
          SizedBox(height: metrics.fieldGap),
          GfTextField(
            label: 'settings.trial.trialDays'.tr(),
            numberMode: true,
            initialValue: '${license.trialDays}',
            onChanged: (v) {
              final days = int.tryParse(v.trim());
              if (days != null) license.setTrialDays(days);
            },
          ),
          SizedBox(height: metrics.gap),
          Wrap(
            spacing: metrics.fieldGap,
            runSpacing: metrics.fieldGap,
            children: [
              if (license.trialEnabled && !license.isLocked)
                GfPrimaryButton(
                  label: 'settings.trial.lockNow'.tr(),
                  icon: Icons.lock_outline,
                  onPressed: () => _promptPasswordAction(
                    context,
                    title: 'settings.trial.lockNow'.tr(),
                    action: (password) => license.lockNow(password),
                    successKey: 'settings.trial.lockedNow',
                  ),
                ),
              GfSecondaryButton(
                label: 'settings.trial.unlockNow'.tr(),
                icon: Icons.lock_open_outlined,
                onPressed: license.isUnlocked
                    ? null
                    : () => _promptPasswordAction(
                        context,
                        title: 'settings.trial.unlockNow'.tr(),
                        action: (password) =>
                            license.unlockWithPassword(password),
                        successKey: 'settings.trial.unlocked',
                      ),
              ),
              GfSecondaryButton(
                label: 'settings.trial.restartTrial'.tr(),
                icon: Icons.restart_alt_outlined,
                onPressed: () => _promptPasswordAction(
                  context,
                  title: 'settings.trial.restartTrial'.tr(),
                  action: (password) => license.restartTrial(password),
                  successKey: 'settings.trial.trialRestarted',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnerPasswordCard extends StatefulWidget {
  const _OwnerPasswordCard({required this.metrics});

  final _DesktopMetrics metrics;

  @override
  State<_OwnerPasswordCard> createState() => _OwnerPasswordCardState();
}

class _OwnerPasswordCardState extends State<_OwnerPasswordCard> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final license = context.read<TrialLicenseProvider>();
    final next = _newCtrl.text;
    if (next.trim().length < 4) {
      GfToast.error(context, 'settings.trial.passwordTooShort'.tr());
      return;
    }
    if (next != _confirmCtrl.text) {
      GfToast.error(context, 'settings.trial.passwordMismatch'.tr());
      return;
    }

    setState(() => _busy = true);
    final ok = license.hasPassword
        ? await license.setPassword(
            newPassword: next,
            currentPassword: _currentCtrl.text,
          )
        : await license.createPassword(next);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      GfToast.error(
        context,
        license.hasPassword
            ? 'settings.trial.wrongPassword'.tr()
            : 'settings.trial.passwordTooShort'.tr(),
      );
      return;
    }

    _currentCtrl.clear();
    _newCtrl.clear();
    _confirmCtrl.clear();
    GfToast.success(context, 'settings.trial.passwordSaved'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<TrialLicenseProvider>();
    final metrics = widget.metrics;

    return _SectionCard(
      icon: Icons.password_outlined,
      title: 'settings.trial.passwordSection'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            license.hasPassword
                ? 'settings.trial.passwordChangeHint'.tr()
                : 'settings.trial.passwordCreateHint'.tr(),
            style: AppTypography.subtitle,
          ),
          SizedBox(height: metrics.fieldGap),
          if (license.hasPassword) ...[
            GfTextField(
              controller: _currentCtrl,
              label: 'settings.trial.currentPassword'.tr(),
              obscureText: _obscure,
            ),
            SizedBox(height: metrics.fieldGap),
          ],
          GfTextField(
            controller: _newCtrl,
            label: 'settings.trial.newPassword'.tr(),
            obscureText: _obscure,
            suffix: IconButton(
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppColors.textMuted,
              ),
            ),
          ),
          SizedBox(height: metrics.fieldGap),
          GfTextField(
            controller: _confirmCtrl,
            label: 'settings.trial.confirmPassword'.tr(),
            obscureText: _obscure,
          ),
          SizedBox(height: metrics.gap),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GfPrimaryButton(
              label: license.hasPassword
                  ? 'settings.trial.changePassword'.tr()
                  : 'settings.trial.setPassword'.tr(),
              onPressed: _busy ? null : _save,
              isLoading: _busy,
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> _promptPasswordDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String fieldLabel,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PasswordPromptDialog(
      title: title,
      subtitle: subtitle,
      fieldLabel: fieldLabel,
    ),
  );
}

/// Owns its [TextEditingController] so dispose runs with the route, not while
/// the dialog exit animation still holds listeners.
class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({
    required this.title,
    required this.subtitle,
    required this.fieldLabel,
  });

  final String title;
  final String subtitle;
  final String fieldLabel;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.lock_outline_rounded,
      iconColor: AppColors.primary,
      title: widget.title,
      subtitle: widget.subtitle,
      primaryLabel: 'common.confirm'.tr(),
      primaryIcon: Icons.check_rounded,
      onCancel: () => Navigator.of(context).pop(),
      onPrimary: _confirm,
      maxWidth: 380,
      maxHeight: 360,
      body: GfTextField(
        controller: _controller,
        label: widget.fieldLabel,
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => _confirm(),
      ),
    );
  }
}

Future<void> _promptPasswordAction(
  BuildContext context, {
  required String title,
  required Future<bool> Function(String password) action,
  required String successKey,
}) async {
  final license = context.read<TrialLicenseProvider>();
  if (!license.hasPassword) {
    GfToast.error(context, 'settings.trial.setPasswordFirst'.tr());
    return;
  }

  final password = await _promptPasswordDialog(
    context,
    title: title,
    subtitle: 'settings.trial.passwordDialogSubtitle'.tr(),
    fieldLabel: 'settings.trial.ownerPassword'.tr(),
  );
  if (password == null || !context.mounted) return;

  final success = await action(password);
  if (!context.mounted) return;
  if (success) {
    GfToast.success(context, successKey.tr());
  } else {
    GfToast.error(context, 'settings.trial.wrongPassword'.tr());
  }
}

String _aboutText(String key) => 'settings.aboutCompany.$key'.tr();

abstract final class _HadidBrand {
  static const logoAsset = 'assets/images/hadid_logo.jpg';
  static const phones = ['0792348941', '0770745869'];

  static const navy = Color(0xFF0B2A3F);
  static const navyDeep = Color(0xFF06182A);
  static const mint = Color(0xFF8EF0C4);
  static const cyan = Color(0xFF27D3DD);
  static const peach = Color(0xFFF6C9A0);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [mint, cyan],
  );

  static const darkGradient = LinearGradient(
    begin: AlignmentDirectional.topStart,
    end: AlignmentDirectional.bottomEnd,
    colors: [navy, navyDeep],
  );

  /// Brand accent that stays readable on the current card surface.
  static Color get accent => AppColors.isLight ? const Color(0xFF0E8C99) : cyan;

  static TextStyle get paragraph =>
      AppTypography.body.copyWith(color: AppColors.textSecondary, height: 1.95);
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.metrics});

  final _DesktopMetrics metrics;

  static const _services = <(IconData, String)>[
    (Icons.calculate_outlined, '۰۱'),
    (Icons.dashboard_customize_outlined, '۰۲'),
    (Icons.code_rounded, '۰۳'),
    (Icons.devices_other_outlined, '۰۴'),
    (Icons.support_agent_rounded, '۰۵'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wide = width >= 860;
        final gap = metrics.gap;
        final serviceColumns = width >= 1100 ? 3 : (width >= 640 ? 2 : 1);

        final sections = <Widget>[
          _AboutHero(wide: wide),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.apartment_rounded,
            title: _aboutText('introTitle'),
            child: _AboutParagraphs(
              texts: [
                _aboutText('intro1'),
                _aboutText('intro2'),
                _aboutText('intro3'),
              ],
            ),
          ),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.design_services_outlined,
            title: _aboutText('servicesTitle'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_aboutText('servicesIntro'), style: _HadidBrand.paragraph),
                const SizedBox(height: 16),
                _AboutGrid(
                  columns: serviceColumns,
                  spacing: metrics.fieldGap,
                  children: [
                    for (var i = 0; i < _services.length; i++)
                      _ServiceTile(
                        icon: _services[i].$1,
                        number: _services[i].$2,
                        title: _aboutText('service${i + 1}Title'),
                        body: _aboutText('service${i + 1}Body'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _AboutGrid(
            columns: wide ? 2 : 1,
            spacing: gap,
            children: [
              _HighlightCard(
                metrics: metrics,
                icon: Icons.visibility_outlined,
                title: _aboutText('visionTitle'),
                body: _aboutText('visionBody'),
              ),
              _HighlightCard(
                metrics: metrics,
                icon: Icons.flag_outlined,
                title: _aboutText('missionTitle'),
                body: _aboutText('missionBody'),
              ),
            ],
          ),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.verified_outlined,
            title: _aboutText('whyTitle'),
            child: _AboutGrid(
              columns: width >= 640 ? 2 : 1,
              spacing: metrics.fieldGap * 0.75,
              children: [
                for (var i = 1; i <= 6; i++)
                  _CheckItem(text: _aboutText('why$i')),
              ],
            ),
          ),
          _AboutPanel(
            metrics: metrics,
            icon: Icons.handshake_outlined,
            title: _aboutText('commitmentTitle'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _aboutText('commitment1'),
                  style: _HadidBrand.paragraph,
                  textAlign: TextAlign.justify,
                ),
                const SizedBox(height: 16),
                _QuoteHighlight(text: _aboutText('commitment2')),
              ],
            ),
          ),
          _AboutContact(wide: wide),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'settings.aboutCompany.footer'.tr(
                namedArgs: {
                  'app': AppConstants.appName,
                  'version': AppConstants.appVersion,
                },
              ),
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              _FadeSlideIn(index: i, child: sections[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Staggered entrance; [index] delays each block slightly after the previous.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = index * 70;
    final total = 420 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
    );
  }
}

/// Equal-height rows; a shorter last row stretches its items to fill.
class _AboutGrid extends StatelessWidget {
  const _AboutGrid({
    required this.columns,
    required this.spacing,
    required this.children,
  });

  final int columns;
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final rowItems = children.sublist(
        i,
        (i + columns).clamp(0, children.length),
      );
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < rowItems.length; j++) ...[
                if (j > 0) SizedBox(width: spacing),
                Expanded(child: rowItems[j]),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color, this.alpha = 0.25});

  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 22.0;
    final paint = Paint()..color = color;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => oldDelegate.color != color;
}

/// Dark brand canvas shared by the hero and contact blocks.
class _BrandBackdrop extends StatelessWidget {
  const _BrandBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: _HadidBrand.darkGradient,
        borderRadius: AppRadius.card,
        boxShadow: [
          BoxShadow(
            color: _HadidBrand.navyDeep.withValues(
              alpha: AppColors.isLight ? 0.22 : 0.5,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          const PositionedDirectional(
            top: -90,
            end: -70,
            child: _GlowOrb(size: 300, color: _HadidBrand.cyan, alpha: 0.28),
          ),
          const PositionedDirectional(
            bottom: -120,
            start: -60,
            child: _GlowOrb(size: 280, color: _HadidBrand.mint, alpha: 0.18),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DotGridPainter(Colors.white.withValues(alpha: 0.05)),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _HadidBrand.mint,
                    _HadidBrand.cyan,
                    _HadidBrand.peach,
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _HadidLogo extends StatelessWidget {
  const _HadidLogo({required this.size, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: _HadidBrand.mint.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: _HadidBrand.cyan.withValues(alpha: 0.35),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1.5),
        child: Image.asset(
          _HadidBrand.logoAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _GradientIconBadge extends StatelessWidget {
  const _GradientIconBadge({required this.icon, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: _HadidBrand.gradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: _HadidBrand.cyan.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.52, color: _HadidBrand.navy),
    );
  }
}

class _AboutHero extends StatelessWidget {
  const _AboutHero({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;

    final info = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            gradient: _HadidBrand.gradient,
            borderRadius: AppRadius.pill,
          ),
          child: Text(
            _aboutText('badge'),
            style: AppTypography.caption.copyWith(
              color: _HadidBrand.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _aboutText('name'),
          textAlign: textAlign,
          style: AppTypography.display.copyWith(
            color: Colors.white,
            fontSize: wide ? 28 : 22,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _aboutText('nameEn'),
          textAlign: textAlign,
          textDirection: TextDirection.ltr,
          style: AppTypography.bodyMedium.copyWith(
            fontFamily: AppFontFamily.inter,
            color: _HadidBrand.mint.withValues(alpha: 0.9),
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: AppRadius.pill,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: _HadidBrand.peach,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _aboutText('tagline'),
                  style: AppTypography.bodySemiBold.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            _HeroStat(
              icon: Icons.workspace_premium_outlined,
              title: _aboutText('statExperienceTitle'),
              caption: _aboutText('statExperienceCaption'),
            ),
            _HeroStat(
              icon: Icons.groups_2_outlined,
              title: _aboutText('statTeamTitle'),
              caption: _aboutText('statTeamCaption'),
            ),
            _HeroStat(
              icon: Icons.auto_fix_high_outlined,
              title: _aboutText('statCustomTitle'),
              caption: _aboutText('statCustomCaption'),
            ),
          ],
        ),
      ],
    );

    return _BrandBackdrop(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? 36 : 22,
          wide ? 36 : 26,
          wide ? 36 : 22,
          wide ? 38 : 28,
        ),
        child: wide
            ? Row(
                children: [
                  const _HadidLogo(size: 156),
                  const SizedBox(width: 32),
                  Expanded(child: info),
                ],
              )
            : Column(
                children: [
                  const _HadidLogo(size: 112),
                  const SizedBox(height: 22),
                  info,
                ],
              ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GradientIconBadge(icon: icon, size: 34),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodySemiBold.copyWith(
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
              Text(
                caption,
                style: AppTypography.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({
    required this.metrics,
    required this.icon,
    required this.title,
    required this.child,
  });

  final _DesktopMetrics metrics;
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(metrics.cardPadding + 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AboutHeading(icon: icon, title: title),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _AboutHeading extends StatelessWidget {
  const _AboutHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GradientIconBadge(icon: icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.sectionTitle),
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 3,
                decoration: const BoxDecoration(
                  gradient: _HadidBrand.gradient,
                  borderRadius: AppRadius.pill,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Renders `**bold**` segments of a translated string.
class _RichParagraph extends StatelessWidget {
  const _RichParagraph({
    required this.text,
    required this.style,
    this.boldColor,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final Color? boldColor;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final bold = style.copyWith(
      fontWeight: FontWeight.w700,
      color: boldColor ?? AppColors.textPrimary,
    );
    final parts = text.split('**');
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].isNotEmpty)
              TextSpan(text: parts[i], style: i.isOdd ? bold : null),
        ],
      ),
      textAlign: textAlign,
    );
  }
}

class _AboutParagraphs extends StatelessWidget {
  const _AboutParagraphs({required this.texts});

  final List<String> texts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < texts.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _RichParagraph(
            text: texts[i],
            style: _HadidBrand.paragraph,
            boldColor: _HadidBrand.accent,
            textAlign: TextAlign.justify,
          ),
        ],
      ],
    );
  }
}

class _ServiceTile extends StatefulWidget {
  const _ServiceTile({
    required this.icon,
    required this.number,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String number;
  final String title;
  final String body;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = _HadidBrand.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppRadius.card,
          border: Border.all(
            color: _hover ? accent.withValues(alpha: 0.55) : AppColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: _hover ? 0.16 : 0),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _GradientIconBadge(icon: widget.icon, size: 42),
                const Spacer(),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: AppTypography.display.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: accent.withValues(alpha: _hover ? 0.55 : 0.22),
                  ),
                  child: Text(widget.number),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: AppTypography.bodySemiBold.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              widget.body,
              style: AppTypography.subtitle.copyWith(height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.metrics,
    required this.icon,
    required this.title,
    required this.body,
  });

  final _DesktopMetrics metrics;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final accent = _HadidBrand.accent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: 0.12), AppColors.card),
            AppColors.card,
          ],
        ),
        borderRadius: AppRadius.card,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -18,
            bottom: -24,
            child: Icon(icon, size: 128, color: accent.withValues(alpha: 0.07)),
          ),
          Padding(
            padding: EdgeInsets.all(metrics.cardPadding + 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AboutHeading(icon: icon, title: title),
                const SizedBox(height: 16),
                Text(
                  body,
                  style: _HadidBrand.paragraph,
                  textAlign: TextAlign.justify,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  const _CheckItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              gradient: _HadidBrand.gradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 16,
              color: _HadidBrand.navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _RichParagraph(
              text: text,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.75,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteHighlight extends StatelessWidget {
  const _QuoteHighlight({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = _HadidBrand.accent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_HadidBrand.mint, _HadidBrand.cyan],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded, size: 30, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RichParagraph(
                        text: text,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          height: 1.9,
                        ),
                        boldColor: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutContact extends StatelessWidget {
  const _AboutContact({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return _BrandBackdrop(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          wide ? 32 : 20,
          wide ? 28 : 22,
          wide ? 32 : 20,
          wide ? 30 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _GradientIconBadge(icon: Icons.phone_in_talk_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _aboutText('contactTitle'),
                    style: AppTypography.sectionTitle.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _aboutText('contactBody'),
              style: AppTypography.body.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.9,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _aboutText('phonesLabel'),
              style: AppTypography.label.copyWith(
                color: _HadidBrand.mint,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final phone in _HadidBrand.phones)
                  _PhoneChip(phone: phone),
              ],
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
            const SizedBox(height: 18),
            Row(
              children: [
                const _HadidLogo(size: 44, glow: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _aboutText('name'),
                        style: AppTypography.bodySemiBold.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _aboutText('slogan'),
                        style: AppTypography.caption.copyWith(
                          color: _HadidBrand.peach,
                          height: 1.6,
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
    );
  }
}

class _PhoneChip extends StatelessWidget {
  const _PhoneChip({required this.phone});

  final String phone;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (context.mounted) GfToast.success(context, _aboutText('phoneCopied'));
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _aboutText('copyPhone'),
      child: Material(
        color: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _copy(context),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 16, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    gradient: _HadidBrand.gradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_rounded,
                    size: 18,
                    color: _HadidBrand.navy,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  phone,
                  textDirection: TextDirection.ltr,
                  style: AppTypography.bodySemiBold.copyWith(
                    fontFamily: AppFontFamily.inter,
                    color: Colors.white,
                    fontSize: 17,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// System settings as a single expandable list (one open section at a time).
class _SystemToolsAccordion extends StatefulWidget {
  const _SystemToolsAccordion({
    required this.metrics,
    required this.onOpenPath,
  });

  final _DesktopMetrics metrics;
  final Future<void> Function(String path) onOpenPath;

  @override
  State<_SystemToolsAccordion> createState() => _SystemToolsAccordionState();
}

class _SystemToolsAccordionState extends State<_SystemToolsAccordion> {
  int? _openIndex;

  void _toggle(int index) {
    setState(() => _openIndex = _openIndex == index ? null : index);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final items = <_SystemAccordionItem>[
      _SystemAccordionItem(
        icon: Icons.lock_clock_outlined,
        titleKey: 'settings.trial.title',
        subtitleKey: 'settings.trial.subtitle',
        builder: () => _TrialStatusCard(metrics: m),
      ),
      _SystemAccordionItem(
        icon: Icons.password_outlined,
        titleKey: 'settings.trial.passwordSection',
        subtitleKey: 'settings.trial.passwordCreateHint',
        builder: () => _OwnerPasswordCard(metrics: m),
      ),
      _SystemAccordionItem(
        icon: Icons.cloud_outlined,
        titleKey: 'settings.firebaseLink',
        subtitleKey: 'settings.firebaseLinkHint',
        builder: () => _ServerLinkCard(metrics: m),
      ),
      _SystemAccordionItem(
        icon: Icons.backup_outlined,
        titleKey: 'settings.dataBackup',
        subtitleKey: 'settings.dataBackupHint',
        builder: () => _BackupCard(metrics: m, onOpenPath: widget.onOpenPath),
      ),
      _SystemAccordionItem(
        icon: Icons.warning_amber_rounded,
        titleKey: 'settings.dangerZone',
        subtitleKey: 'settings.dangerZoneHint',
        danger: true,
        builder: () => const _DangerZoneCard(),
      ),
      _SystemAccordionItem(
        icon: Icons.support_agent_outlined,
        titleKey: 'settings.supportTitle',
        subtitleKey: 'settings.supportHint',
        builder: () => _SupportCard(metrics: m, onOpenPath: widget.onOpenPath),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(m.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.card,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'settings.systemTools'.tr(),
                      style: AppTypography.sectionTitle,
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.fieldGap * 0.4),
              Text(
                'settings.systemToolsHint'.tr(),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: m.gap),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: m.fieldGap * 0.65),
          _SystemExpandableTile(
            item: items[i],
            expanded: _openIndex == i,
            onTap: () => _toggle(i),
          ),
        ],
      ],
    );
  }
}

class _SystemAccordionItem {
  const _SystemAccordionItem({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
    required this.builder,
    this.danger = false,
  });

  final IconData icon;
  final String titleKey;
  final String subtitleKey;
  final Widget Function() builder;
  final bool danger;
}

class _SystemExpandableTile extends StatelessWidget {
  const _SystemExpandableTile({
    required this.item,
    required this.expanded,
    required this.onTap,
  });

  final _SystemAccordionItem item;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = item.danger ? AppColors.error : AppColors.primary;
    final borderColor = item.danger
        ? AppColors.dangerZoneBorder
        : (expanded
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.border);
    final bg = item.danger
        ? AppColors.dangerZoneBg
        : (expanded
              ? AppColors.primarySoft.withValues(alpha: 0.35)
              : AppColors.card);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.card,
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.card,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: AppRadius.input,
                      ),
                      child: Icon(item.icon, size: 22, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.titleKey.tr(),
                            style: AppTypography.bodySemiBold,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.subtitleKey.tr(),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                            maxLines: expanded ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: item.builder(),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.metrics, required this.onOpenPath});

  final _DesktopMetrics metrics;
  final Future<void> Function(String path) onOpenPath;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.support_agent_outlined,
      title: 'settings.supportTitle'.tr(),
      padding: metrics.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('settings.supportHint'.tr(), style: AppTypography.subtitle),
          SizedBox(height: metrics.fieldGap),
          Text(
            'settings.supportVersion'.tr(
              namedArgs: {
                'app': AppConstants.appName,
                'version': AppConstants.appVersion,
              },
            ),
            style: AppTypography.bodyMedium,
          ),
          SizedBox(height: metrics.gap),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: GfSecondaryButton(
              label: 'settings.supportOpenFolder'.tr(),
              icon: Icons.folder_open_outlined,
              onPressed: () => onOpenPath(AppDatabase.appSupportDir.path),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: icon,
      title: title,
      child: Text(
        'settings.comingSoonBody'.tr(),
        style: AppTypography.subtitle,
      ),
    );
  }
}
