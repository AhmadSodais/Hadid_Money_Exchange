import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/di/service_locator.dart';
import '../../core/security/app_permissions.dart';
import '../../core/security/auth_labels.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/auth_models.dart';
import '../providers/auth_provider.dart';

/// Settings: users, roles, and section access — Persian, grouped, app-styled.
class UsersRolesAccessCard extends StatefulWidget {
  const UsersRolesAccessCard({super.key, this.padding = 20});

  final double padding;

  @override
  State<UsersRolesAccessCard> createState() => _UsersRolesAccessCardState();
}

class _UsersRolesAccessCardState extends State<UsersRolesAccessCard> {
  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<AppUserModel> _users = const [];
  List<RoleModel> _roles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = context.read<AuthProvider>().isAuthEnabled;
    if (!enabled) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = ServiceLocator.instance.auth;
    final users = await auth.listUsers();
    final roles = await auth.listRoles();
    if (!mounted) return;
    users.when(
      success: (v) => _users = v,
      failure: (f) => _error = f.message,
    );
    roles.when(
      success: (v) => _roles = v,
      failure: (f) => _error ??= f.message,
    );
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.padding;
    final authEnabled = context.watch<AuthProvider>().isAuthEnabled;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'settings.usersRoles'.tr(),
                  style: AppTypography.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: pad * 0.35),
          if (!authEnabled)
            _AuthEnablePanel(
              onEnabled: () async {
                await _load();
                if (mounted) setState(() {});
              },
            )
          else ...[
            Text(
              'settings.usersRolesHint'.tr(),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () async {
                  final ok = await GfConfirmDialog.show(
                    context,
                    title: 'auth.disableTitle'.tr(),
                    message: 'auth.disableBody'.tr(),
                    danger: true,
                    confirmLabel: 'auth.disable'.tr(),
                  );
                  if (!ok || !mounted) return;
                  final success =
                      await context.read<AuthProvider>().disableAuth();
                  if (!mounted) return;
                  if (success) {
                    GfToast.success(context, 'auth.disabledDone'.tr());
                    setState(() {});
                  }
                },
                icon: Icon(Icons.lock_open_outlined,
                    size: 18, color: AppColors.error),
                label: Text(
                  'auth.disable'.tr(),
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ),
            SizedBox(height: pad * 0.4),
            _SegmentedTabs(
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
              items: [
                _SegItem(
                  icon: Icons.people_outline,
                  label: 'auth.users'.tr(),
                  count: _users.length,
                ),
                _SegItem(
                  icon: Icons.badge_outlined,
                  label: 'auth.roles'.tr(),
                  count: _roles.length,
                ),
                _SegItem(
                  icon: Icons.shield_outlined,
                  label: 'auth.access'.tr(),
                ),
              ],
            ),
            SizedBox(height: pad * 0.6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _loading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      height: 360,
                      child: GfPageLoader(),
                    )
                  : _error != null
                      ? SizedBox(
                          key: const ValueKey('error'),
                          height: 360,
                          child: GfEmptyState(title: _error!, compact: true),
                        )
                      : SizedBox(
                          key: ValueKey('tab-$_tab'),
                          height: 500,
                          child: switch (_tab) {
                            0 => _UsersPane(
                                users: _users,
                                roles: _roles,
                                onChanged: _load,
                              ),
                            1 => _RolesPane(
                                roles: _roles,
                                onChanged: _load,
                              ),
                            _ => _AccessPane(
                                roles: _roles,
                                onChanged: _load,
                              ),
                          },
                        ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opt-in entry: open a dedicated page to create admin credentials.
class _AuthEnablePanel extends StatelessWidget {
  const _AuthEnablePanel({required this.onEnabled});

  final Future<void> Function() onEnabled;

  Future<void> _openSetup(BuildContext context) async {
    await context.push<bool>(AppRoutes.enableAuth);
    if (!context.mounted) return;
    if (context.read<AuthProvider>().isAuthEnabled) {
      await onEnabled();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primarySoft.withValues(alpha: 0.45),
            borderRadius: AppRadius.input,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 22, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'auth.enableTitle'.tr(),
                      style: AppTypography.bodySemiBold,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'auth.enableHint'.tr(),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GfPrimaryButton(
            label: 'auth.enableSetup'.tr(),
            icon: Icons.person_add_alt_1_outlined,
            onPressed: () => _openSetup(context),
          ),
        ),
      ],
    );
  }
}

class _SegItem {
  const _SegItem({required this.icon, required this.label, this.count});
  final IconData icon;
  final String label;
  final int? count;
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.index,
    required this.onChanged,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<_SegItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: AppRadius.input,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Material(
                color: index == i ? AppColors.card : Colors.transparent,
                borderRadius: AppRadius.input,
                elevation: index == i ? 0 : 0,
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: AppRadius.input,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.input,
                      border: Border.all(
                        color: index == i
                            ? AppColors.primary.withValues(alpha: 0.35)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].icon,
                          size: 17,
                          color: index == i
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              fontWeight: index == i
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: index == i
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (items[i].count != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: index == i
                                  ? AppColors.primarySoft
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: index == i
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              '${items[i].count}',
                              style: AppTypography.caption.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: index == i
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({
    required this.hint,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final String hint;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            hint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(width: 12),
        GfSecondaryButton(
          label: actionLabel,
          icon: actionIcon,
          compact: true,
          onPressed: onAction,
        ),
      ],
    );
  }
}

class _EntityTile extends StatelessWidget {
  const _EntityTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.badges,
    required this.actions,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final List<Widget> badges;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodySemiBold),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: badges),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _UsersPane extends StatelessWidget {
  const _UsersPane({
    required this.users,
    required this.roles,
    required this.onChanged,
  });

  final List<AppUserModel> users;
  final List<RoleModel> roles;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneHeader(
          hint: 'auth.usersTabHint'.tr(),
          actionLabel: 'auth.addUser'.tr(),
          actionIcon: Icons.person_add_outlined,
          onAction: () async {
            final ok = await _UserFormDialog.show(context, roles: roles);
            if (ok == true) await onChanged();
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: users.isEmpty
              ? GfEmptyState(title: 'auth.noUsers'.tr(), compact: true)
              : ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, i) {
                    final u = users[i];
                    return _EntityTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(
                          u.displayName.trim().isNotEmpty
                              ? u.displayName.trim().substring(0, 1)
                              : '؟',
                          style: AppTypography.bodySemiBold.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      title: AuthLabels.userDisplayName(u.displayName),
                      subtitle: '@${u.username}',
                      badges: [
                        GfStatusBadge(
                          label: AuthLabels.roleName(u.roleName),
                          color: AppColors.primary,
                          compact: true,
                        ),
                        if (!u.isActive)
                          GfStatusBadge(
                            label: 'auth.inactive'.tr(),
                            color: AppColors.warning,
                            compact: true,
                          ),
                      ],
                      actions: [
                        IconButton(
                          tooltip: 'common.edit'.tr(),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () async {
                            final ok = await _UserFormDialog.show(
                              context,
                              roles: roles,
                              existing: u,
                            );
                            if (ok == true) await onChanged();
                          },
                        ),
                        if (u.username != 'admin')
                          IconButton(
                            tooltip: 'common.delete'.tr(),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.error,
                            ),
                            onPressed: () async {
                              final confirm = await GfConfirmDialog.show(
                                context,
                                title: 'auth.deleteUserTitle'.tr(),
                                message: 'auth.deleteUserBody'.tr(),
                                confirmLabel: 'common.delete'.tr(),
                                danger: true,
                              );
                              if (confirm != true) return;
                              await ServiceLocator.instance.auth
                                  .deleteUser(u.id);
                              await onChanged();
                            },
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RolesPane extends StatelessWidget {
  const _RolesPane({required this.roles, required this.onChanged});

  final List<RoleModel> roles;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PaneHeader(
          hint: 'auth.rolesTabHint'.tr(),
          actionLabel: 'auth.addRole'.tr(),
          actionIcon: Icons.add_rounded,
          onAction: () async {
            final ok = await _RoleFormDialog.show(context);
            if (ok == true) await onChanged();
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: roles.isEmpty
              ? GfEmptyState(title: 'auth.noRoles'.tr(), compact: true)
              : ListView.builder(
                  itemCount: roles.length,
                  itemBuilder: (context, i) {
                    final r = roles[i];
                    return _EntityTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: AppRadius.input,
                        ),
                        child: Icon(
                          r.isSystem
                              ? Icons.verified_user_outlined
                              : Icons.badge_outlined,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      title: AuthLabels.roleName(r.name),
                      subtitle: AuthLabels.roleDescription(r.description)?.trim().isNotEmpty == true
                          ? AuthLabels.roleDescription(r.description)!
                          : 'auth.permissionCount'.tr(
                              namedArgs: {
                                'count': '${r.permissions.length}',
                              },
                            ),
                      badges: [
                        GfStatusBadge(
                          label: r.isSystem
                              ? 'auth.systemRole'.tr()
                              : 'auth.customRole'.tr(),
                          color: r.isSystem
                              ? AppColors.info
                              : AppColors.textSecondary,
                          compact: true,
                        ),
                        GfStatusBadge(
                          label: 'auth.permissionCount'.tr(
                            namedArgs: {
                              'count': '${r.permissions.length}',
                            },
                          ),
                          color: AppColors.primary,
                          compact: true,
                        ),
                      ],
                      actions: [
                        IconButton(
                          tooltip: 'common.edit'.tr(),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () async {
                            final ok = await _RoleFormDialog.show(
                              context,
                              existing: r,
                            );
                            if (ok == true) await onChanged();
                          },
                        ),
                        if (!r.isSystem)
                          IconButton(
                            tooltip: 'common.delete'.tr(),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppColors.error,
                            ),
                            onPressed: () async {
                              final confirm = await GfConfirmDialog.show(
                                context,
                                title: 'auth.deleteRoleTitle'.tr(),
                                message: 'auth.deleteRoleBody'.tr(),
                                confirmLabel: 'common.delete'.tr(),
                                danger: true,
                              );
                              if (confirm != true) return;
                              final result = await ServiceLocator
                                  .instance.auth
                                  .deleteRole(r.id);
                              if (context.mounted) {
                                result.when(
                                  success: (_) {},
                                  failure: (f) =>
                                      GfToast.error(context, f.message),
                                );
                              }
                              await onChanged();
                            },
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PermissionGroup {
  const _PermissionGroup(this.titleKey, this.keys);
  final String titleKey;
  final List<String> keys;
}

const _kPermissionGroups = [
  _PermissionGroup('auth.permissionGroups.operations', [
    AppPermissions.overview,
    AppPermissions.sales,
    AppPermissions.orders,
  ]),
  _PermissionGroup('auth.permissionGroups.inventory', [
    AppPermissions.products,
    AppPermissions.purchases,
    AppPermissions.purchasesEdit,
    AppPermissions.warehouses,
    AppPermissions.alerts,
  ]),
  _PermissionGroup('auth.permissionGroups.finance', [
    AppPermissions.expenses,
    AppPermissions.tradingCompanies,
    AppPermissions.customers,
    AppPermissions.reportsView,
  ]),
  _PermissionGroup('auth.permissionGroups.admin', [
    AppPermissions.employees,
    AppPermissions.settings,
    AppPermissions.rolesManage,
    AppPermissions.syncCenter,
  ]),
];

class _AccessPane extends StatefulWidget {
  const _AccessPane({required this.roles, required this.onChanged});

  final List<RoleModel> roles;
  final Future<void> Function() onChanged;

  @override
  State<_AccessPane> createState() => _AccessPaneState();
}

class _AccessPaneState extends State<_AccessPane> {
  int? _roleId;
  Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.roles.isNotEmpty) {
      _selectRole(widget.roles.first);
    }
  }

  @override
  void didUpdateWidget(covariant _AccessPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_roleId != null) {
      final role = widget.roles.where((r) => r.id == _roleId).firstOrNull;
      if (role != null) {
        _selected = role.permissions.toSet();
      }
    } else if (widget.roles.isNotEmpty) {
      _selectRole(widget.roles.first);
    }
  }

  void _selectRole(RoleModel role) {
    setState(() {
      _roleId = role.id;
      _selected = role.permissions.toSet();
    });
  }

  String _permissionLabel(String key) => AuthLabels.permission(key);

  Future<void> _save() async {
    final id = _roleId;
    if (id == null) return;
    setState(() => _saving = true);
    final result = await ServiceLocator.instance.auth.setRolePermissions(
      id,
      _selected.toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    result.when(
      success: (_) async {
        GfToast.success(context, 'auth.permissionsSaved'.tr());
        await context.read<AuthProvider>().refreshSession();
        await widget.onChanged();
      },
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  void _setGroup(List<String> keys, bool enable) {
    setState(() {
      if (enable) {
        _selected.addAll(keys);
      } else {
        _selected.removeAll(keys);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.roles.isEmpty) {
      return GfEmptyState(title: 'auth.noRoles'.tr(), compact: true);
    }

    final role = widget.roles.where((r) => r.id == _roleId).firstOrNull;
    final granted = _selected.length;
    final total = AppPermissions.all.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'auth.accessTabHint'.tr(),
          style: AppTypography.caption.copyWith(
            color: AppColors.textMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        GfDropdown<RoleModel>(
          label: 'auth.selectRole'.tr(),
          items: widget.roles,
          value: role,
          labelBuilder: (r) => AuthLabels.roleName(r.name),
          onChanged: (r) {
            if (r != null) _selectRole(r);
          },
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: AppRadius.input,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'auth.configureAccess'.tr(),
                  style: AppTypography.bodySemiBold.copyWith(
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                'auth.grantedCount'.tr(
                  namedArgs: {
                    'granted': '$granted',
                    'total': '$total',
                  },
                ),
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(
                () => _selected = AppPermissions.all.toSet(),
              ),
              child: Text('auth.selectAllPermissions'.tr()),
            ),
            TextButton(
              onPressed: () => setState(() => _selected = {}),
              child: Text(
                'auth.clearAllPermissions'.tr(),
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              for (final group in _kPermissionGroups)
                _PermissionGroupCard(
                  title: group.titleKey.tr(),
                  keys: group.keys,
                  selected: _selected,
                  labelOf: _permissionLabel,
                  onToggle: (key, enabled) {
                    setState(() {
                      if (enabled) {
                        _selected.add(key);
                      } else {
                        _selected.remove(key);
                      }
                    });
                  },
                  onSetAll: (enable) => _setGroup(group.keys, enable),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: GfPrimaryButton(
            label: 'common.save'.tr(),
            icon: Icons.save_outlined,
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

class _PermissionGroupCard extends StatelessWidget {
  const _PermissionGroupCard({
    required this.title,
    required this.keys,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
    required this.onSetAll,
  });

  final String title;
  final List<String> keys;
  final Set<String> selected;
  final String Function(String key) labelOf;
  final void Function(String key, bool enabled) onToggle;
  final ValueChanged<bool> onSetAll;

  @override
  Widget build(BuildContext context) {
    final enabledCount = keys.where(selected.contains).length;
    final allOn = enabledCount == keys.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Text(title, style: AppTypography.bodySemiBold),
                ),
                Text(
                  '$enabledCount/${keys.length}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => onSetAll(!allOn),
                  child: Text(
                    allOn
                        ? 'auth.clearGroup'.tr()
                        : 'auth.selectAllInGroup'.tr(),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          for (final key in keys)
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                controlAffinity: ListTileControlAffinity.leading,
                value: selected.contains(key),
                title: Text(labelOf(key), style: AppTypography.body),
                onChanged: (v) => onToggle(key, v == true),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({required this.roles, this.existing});

  final List<RoleModel> roles;
  final AppUserModel? existing;

  static Future<bool?> show(
    BuildContext context, {
    required List<RoleModel> roles,
    AppUserModel? existing,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => _UserFormDialog(roles: roles, existing: existing),
    );
  }

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  late final TextEditingController _username;
  late final TextEditingController _displayName;
  late final TextEditingController _password;
  late int? _roleId;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _username = TextEditingController(text: e?.username ?? '');
    _displayName = TextEditingController(text: e?.displayName ?? '');
    _password = TextEditingController();
    _roleId = e?.roleId ?? widget.roles.firstOrNull?.id;
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_username.text.trim().isEmpty ||
        _displayName.text.trim().isEmpty ||
        _roleId == null) {
      GfToast.error(context, 'errors.formFixFields'.tr());
      return;
    }
    if (widget.existing == null && _password.text.trim().isEmpty) {
      GfToast.error(context, 'auth.passwordRequired'.tr());
      return;
    }
    setState(() => _saving = true);
    final auth = ServiceLocator.instance.auth;
    final result = widget.existing == null
        ? await auth.createUser(
            username: _username.text,
            password: _password.text,
            displayName: _displayName.text,
            roleId: _roleId!,
          )
        : await auth.updateUser(
            id: widget.existing!.id,
            username: _username.text,
            password: _password.text.trim().isEmpty ? null : _password.text,
            displayName: _displayName.text,
            roleId: _roleId,
            isActive: _active,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    result.when(
      success: (_) => Navigator.pop(context, true),
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.person_outline,
      iconColor: AppColors.primary,
      title: widget.existing == null
          ? 'auth.addUser'.tr()
          : 'auth.editUser'.tr(),
      subtitle: 'auth.roleAssignedHint'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      saving: _saving,
      onCancel: () => Navigator.pop(context, false),
      onPrimary: _save,
      maxWidth: 440,
      maxHeight: 640,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GfTextField(
            label: 'auth.username'.tr(),
            controller: _username,
            required: true,
            autofocus: true,
            prefixIcon: Icons.person_outline,
          ),
          const SizedBox(height: AppSpacing.sm),
          GfTextField(
            label: 'auth.displayName'.tr(),
            controller: _displayName,
            required: true,
            prefixIcon: Icons.badge_outlined,
          ),
          const SizedBox(height: AppSpacing.sm),
          GfTextField(
            label: widget.existing == null
                ? 'auth.password'.tr()
                : 'auth.newPasswordOptional'.tr(),
            controller: _password,
            obscureText: true,
            prefixIcon: Icons.lock_outline,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'auth.assignRole'.tr(),
            style: AppTypography.label,
          ),
          const SizedBox(height: 6),
          Text(
            'auth.assignRoleHint'.tr(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          if (widget.roles.isEmpty)
            Text(
              'auth.noRoles'.tr(),
              style: AppTypography.caption.copyWith(color: AppColors.error),
            )
          else
            GfDropdown<RoleModel>(
              label: 'auth.role'.tr(),
              required: true,
              hint: 'auth.selectRole'.tr(),
              items: widget.roles,
              value: widget.roles.where((r) => r.id == _roleId).firstOrNull,
              labelBuilder: (r) => AuthLabels.roleName(r.name),
              prefixIcon: Icons.shield_outlined,
              onChanged: (r) => setState(() => _roleId = r?.id),
            ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('auth.active'.tr()),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleFormDialog extends StatefulWidget {
  const _RoleFormDialog({this.existing});

  final RoleModel? existing;

  static Future<bool?> show(BuildContext context, {RoleModel? existing}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => _RoleFormDialog(existing: existing),
    );
  }

  @override
  State<_RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<_RoleFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _description =
        TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      GfToast.error(context, 'errors.formFixFields'.tr());
      return;
    }
    setState(() => _saving = true);
    final auth = ServiceLocator.instance.auth;
    final result = widget.existing == null
        ? await auth.createRole(
            name: _name.text,
            description: _description.text,
            permissions: AppPermissions.all,
          )
        : await auth.updateRole(
            id: widget.existing!.id,
            name: _name.text,
            description: _description.text,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    result.when(
      success: (_) => Navigator.pop(context, true),
      failure: (f) => GfToast.error(context, f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: Icons.badge_outlined,
      iconColor: AppColors.primary,
      title: widget.existing == null
          ? 'auth.addRole'.tr()
          : 'auth.editRole'.tr(),
      primaryLabel: 'common.save'.tr(),
      primaryIcon: Icons.save_outlined,
      saving: _saving,
      onCancel: () => Navigator.pop(context, false),
      onPrimary: _save,
      maxWidth: 420,
      maxHeight: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GfTextField(
            label: 'auth.roleName'.tr(),
            controller: _name,
            required: true,
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          GfTextField(
            label: 'auth.roleDescription'.tr(),
            controller: _description,
            minLines: 2,
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}
