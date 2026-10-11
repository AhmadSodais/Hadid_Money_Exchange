import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/di/service_locator.dart';
import '../../core/security/auth_labels.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/auth_models.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_shell.dart';

/// Dedicated page to enable local login — pick an existing user or create one.
class EnableAuthPage extends StatefulWidget {
  const EnableAuthPage({super.key});

  @override
  State<EnableAuthPage> createState() => _EnableAuthPageState();
}

class _EnableAuthPageState extends State<EnableAuthPage> {
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _recovery = TextEditingController();

  List<AppUserModel> _users = const [];
  List<RoleModel> _roles = const [];
  AppUserModel? _selectedUser;
  int? _roleId;
  bool _loading = true;
  bool _createNew = false;
  bool _obscure = true;
  bool _busy = false;
  bool _savedRecovery = false;

  bool get _showCreateForm => _users.isEmpty || _createNew;

  @override
  void initState() {
    super.initState();
    _recovery.text = _generateRecoveryCode();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirm.dispose();
    _recovery.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = ServiceLocator.instance.auth;
    final usersResult = await auth.listUsers();
    final rolesResult = await auth.listRoles();
    if (!mounted) return;

    usersResult.when(
      success: (v) => _users = v,
      failure: (_) => _users = const [],
    );
    rolesResult.when(
      success: (v) => _roles = v,
      failure: (_) => _roles = const [],
    );

    final admin = _roles.where((r) => r.name.toLowerCase() == 'administrator');
    _roleId = admin.isNotEmpty
        ? admin.first.id
        : _roles.firstOrNull?.id;
    _createNew = _users.isEmpty;
    _selectedUser = _users.isNotEmpty ? _users.first : null;
    if (_selectedUser != null) {
      _roleId = _selectedUser!.roleId;
    }

    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) gfFocusFirstIn(context);
    });
  }

  String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _copyRecovery() async {
    await Clipboard.setData(ClipboardData(text: _recovery.text.trim()));
    if (!mounted) return;
    GfToast.success(context, 'auth.recoveryCopied'.tr());
  }

  bool _validateCommon() {
    final recovery = _recovery.text.trim();
    if (recovery.isEmpty || recovery.length < 4) {
      GfToast.error(context, 'auth.recoveryTooShort'.tr());
      return false;
    }
    if (!_savedRecovery) {
      GfToast.error(context, 'auth.recoveryMustSave'.tr());
      return false;
    }
    if (_roleId == null) {
      GfToast.error(context, 'auth.roleRequired'.tr());
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validateCommon()) return;

    final auth = context.read<AuthProvider>();
    setState(() => _busy = true);
    var ok = false;

    if (_showCreateForm) {
      final user = _username.text.trim();
      final pass = _password.text;
      final confirm = _confirm.text;
      final display = _displayName.text.trim();

      if (user.isEmpty || pass.isEmpty) {
        setState(() => _busy = false);
        GfToast.error(context, 'auth.setupIncomplete'.tr());
        return;
      }
      if (pass.length < 4) {
        setState(() => _busy = false);
        GfToast.error(context, 'auth.passwordTooShort'.tr());
        return;
      }
      if (pass != confirm) {
        setState(() => _busy = false);
        GfToast.error(context, 'auth.passwordMismatch'.tr());
        return;
      }

      ok = await auth.enableAuth(
        username: user,
        password: pass,
        displayName: display.isEmpty ? user : display,
        recoveryCode: _recovery.text.trim(),
        roleId: _roleId,
      );
    } else {
      final selected = _selectedUser;
      if (selected == null) {
        setState(() => _busy = false);
        GfToast.error(context, 'auth.selectExistingUser'.tr());
        return;
      }
      final pass = _password.text.trim();
      final confirm = _confirm.text.trim();
      if (pass.isNotEmpty) {
        if (pass.length < 4) {
          setState(() => _busy = false);
          GfToast.error(context, 'auth.passwordTooShort'.tr());
          return;
        }
        if (pass != confirm) {
          setState(() => _busy = false);
          GfToast.error(context, 'auth.passwordMismatch'.tr());
          return;
        }
      }

      ok = await auth.enableAuthForExistingUser(
        userId: selected.id,
        recoveryCode: _recovery.text.trim(),
        roleId: _roleId,
        newPassword: pass.isEmpty ? null : pass,
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      GfToast.error(context, (auth.error ?? 'auth.setupIncomplete').tr());
      return;
    }
    GfToast.success(context, 'auth.enabledDone'.tr());
    context.go(AppRoutes.settings);
  }

  Widget _recoverySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('auth.recoveryCode'.tr(), style: AppTypography.label),
        const SizedBox(height: 6),
        Text(
          'auth.recoverySetupHint'.tr(),
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        GfTextField(
          controller: _recovery,
          label: 'auth.recoveryCode'.tr(),
          prefixIcon: Icons.key_outlined,
          required: true,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: _copyRecovery,
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: Text('auth.copyRecovery'.tr()),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _recovery.text = _generateRecoveryCode();
                  _savedRecovery = false;
                });
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('auth.regenerateRecovery'.tr()),
            ),
          ],
        ),
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            value: _savedRecovery,
            onChanged: (v) => setState(() => _savedRecovery = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              'auth.recoverySavedConfirm'.tr(),
              style: AppTypography.caption.copyWith(height: 1.35),
            ),
          ),
        ),
      ],
    );
  }

  Widget _roleDropdown() {
    if (_roles.isEmpty) {
      return Text(
        'auth.noRoles'.tr(),
        style: AppTypography.caption.copyWith(color: AppColors.error),
      );
    }
    return GfDropdown<RoleModel>(
      label: 'auth.role'.tr(),
      required: true,
      hint: 'auth.selectRole'.tr(),
      items: _roles,
      value: _roles.where((r) => r.id == _roleId).firstOrNull,
      labelBuilder: (r) => AuthLabels.roleName(r.name),
      prefixIcon: Icons.badge_outlined,
      onChanged: (r) => setState(() => _roleId = r?.id),
    );
  }

  Widget _passwordFields({required bool requiredPassword}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GfTextField(
          controller: _password,
          label: requiredPassword
              ? 'auth.password'.tr()
              : 'auth.newPasswordOptional'.tr(),
          obscureText: _obscure,
          prefixIcon: Icons.lock_outline,
          required: requiredPassword,
          suffix: SizedBox(
            height: AppSpacing.controlHeight - 2,
            child: Align(
              alignment: Alignment.center,
              child: IconButton(
                tooltip: _obscure
                    ? 'auth.showPassword'.tr()
                    : 'auth.hidePassword'.tr(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GfTextField(
          controller: _confirm,
          label: 'auth.confirmPassword'.tr(),
          obscureText: _obscure,
          prefixIcon: Icons.lock_outline,
          required: requiredPassword,
        ),
      ],
    );
  }

  Widget _createForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_users.isNotEmpty) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _createNew = false;
                _password.clear();
                _confirm.clear();
                _selectedUser ??= _users.first;
                _roleId = _selectedUser?.roleId ?? _roleId;
              }),
              icon: const Icon(Icons.people_outline, size: 18),
              label: Text('auth.chooseExistingUser'.tr()),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'auth.enableHint'.tr(),
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        GfTextField(
          controller: _username,
          label: 'auth.username'.tr(),
          prefixIcon: Icons.person_outline,
          required: true,
          autofocus: true,
        ),
        const SizedBox(height: 12),
        GfTextField(
          controller: _displayName,
          label: 'auth.displayName'.tr(),
          prefixIcon: Icons.badge_outlined,
        ),
        const SizedBox(height: 12),
        _passwordFields(requiredPassword: true),
        const SizedBox(height: 12),
        _roleDropdown(),
        const SizedBox(height: 18),
        _recoverySection(),
      ],
    );
  }

  Widget _selectExistingForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'auth.selectExistingUserHint'.tr(),
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        ..._users.map((u) {
          final selected = _selectedUser?.id == u.id;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => setState(() {
                  _selectedUser = u;
                  _roleId = u.roleId;
                }),
                borderRadius: AppRadius.input,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primarySoft.withValues(alpha: 0.55)
                        : AppColors.input,
                    borderRadius: AppRadius.input,
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.surface,
                        child: Icon(
                          Icons.person_outline,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AuthLabels.userDisplayName(u.displayName),
                              style: AppTypography.bodySemiBold,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${u.username}'
                              '${u.roleName != null ? ' · ${AuthLabels.roleName(u.roleName)}' : ''}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _createNew = true;
              _selectedUser = null;
              _password.clear();
              _confirm.clear();
            }),
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: Text('auth.createNewAdmin'.tr()),
          ),
        ),
        const SizedBox(height: 8),
        _roleDropdown(),
        const SizedBox(height: 12),
        Text(
          'auth.existingPasswordHint'.tr(),
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        _passwordFields(requiredPassword: false),
        const SizedBox(height: 18),
        _recoverySection(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'auth.enablePageTitle'.tr(),
      subtitle: 'auth.enablePageSubtitle'.tr(),
      body: GfKeyboardScope(
        autofocus: true,
        onSave: _busy || _loading ? null : _save,
        onCancel: _busy ? null : () => context.pop(false),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _loading
                ? const SizedBox(height: 240, child: GfPageLoader())
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_showCreateForm)
                            _createForm()
                          else
                            _selectExistingForm(),
                          const SizedBox(height: 16),
                          GfPrimaryButton(
                            label: 'common.save'.tr(),
                            icon: Icons.save_outlined,
                            expanded: true,
                            isLoading: _busy,
                            onPressed: _busy ? null : _save,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
