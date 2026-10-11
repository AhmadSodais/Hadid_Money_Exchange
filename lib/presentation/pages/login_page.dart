import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/widgets.dart';
import '../providers/auth_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthRequired) {
      context.go(AppRoutes.overview);
      return;
    }
    setState(() => _submitting = true);
    final ok = await auth.login(_username.text, _password.text);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      context.go(AppRoutes.overview);
    } else {
      GfToast.error(
        context,
        (auth.error ?? 'auth.invalidCredentials').tr(),
      );
    }
  }

  Future<void> _forgotPassword() async {
    final recovery = TextEditingController();
    final username = TextEditingController(text: _username.text);
    final newPass = TextEditingController();
    final confirm = TextEditingController();
    var obscure = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return GfDialogShell(
              icon: Icons.lock_reset_outlined,
              iconColor: AppColors.primary,
              title: 'auth.forgotPasswordTitle'.tr(),
              subtitle: 'auth.forgotPasswordHint'.tr(),
              primaryLabel: 'auth.resetPassword'.tr(),
              primaryIcon: Icons.check_rounded,
              onCancel: () => Navigator.of(ctx).pop(false),
              onPrimary: () => Navigator.of(ctx).pop(true),
              maxWidth: 420,
              maxHeight: 520,
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GfTextField(
                    controller: username,
                    label: 'auth.username'.tr(),
                    prefixIcon: Icons.person_outline,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  GfTextField(
                    controller: recovery,
                    label: 'auth.recoveryCode'.tr(),
                    prefixIcon: Icons.key_outlined,
                  ),
                  const SizedBox(height: 12),
                  GfTextField(
                    controller: newPass,
                    label: 'auth.newPassword'.tr(),
                    obscureText: obscure,
                    prefixIcon: Icons.lock_outline,
                    suffix: IconButton(
                      onPressed: () => setLocal(() => obscure = !obscure),
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GfTextField(
                    controller: confirm,
                    label: 'auth.confirmPassword'.tr(),
                    obscureText: obscure,
                    prefixIcon: Icons.lock_outline,
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    final recoveryText = recovery.text;
    final userText = username.text;
    final passText = newPass.text;
    final confirmText = confirm.text;
    recovery.dispose();
    username.dispose();
    newPass.dispose();
    confirm.dispose();

    if (ok != true || !mounted) return;
    if (passText != confirmText) {
      GfToast.error(context, 'auth.passwordMismatch'.tr());
      return;
    }

    final auth = context.read<AuthProvider>();
    final success = await auth.resetPasswordWithRecovery(
      recoveryCode: recoveryText,
      newPassword: passText,
      username: userText,
    );
    if (!mounted) return;
    if (success) {
      GfToast.success(context, 'auth.passwordResetDone'.tr());
      _username.text = userText.trim();
      _password.clear();
    } else {
      GfToast.error(
        context,
        (auth.error ?? 'auth.recoveryInvalid').tr(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          AppAssets.hadidLogo,
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: AppTypography.pageTitle,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'auth.loginSubtitle'.tr(),
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GfTextField(
                      label: 'auth.username'.tr(),
                      controller: _username,
                      prefixIcon: Icons.person_outline,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    GfTextField(
                      label: 'auth.password'.tr(),
                      controller: _password,
                      obscureText: _obscure,
                      prefixIcon: Icons.lock_outline,
                      suffix: IconButton(
                        tooltip: _obscure
                            ? 'auth.showPassword'.tr()
                            : 'auth.hidePassword'.tr(),
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _submitting ? null : _forgotPassword,
                        child: Text('auth.forgotPassword'.tr()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GfPrimaryButton(
                      label: 'auth.login'.tr(),
                      icon: Icons.login,
                      expanded: true,
                      isLoading: _submitting,
                      onPressed: _submitting ? null : _submit,
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
