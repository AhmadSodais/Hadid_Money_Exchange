import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_button.dart';
import '../../core/widgets/gf_loader.dart';
import '../../core/widgets/gf_text_field.dart';
import '../providers/trial_license_provider.dart';

/// Full-screen spinner while license prefs are loading.
class AuthLoadingOverlay extends StatelessWidget {
  const AuthLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background.withValues(alpha: 0.97),
      child: Center(
        child: GfLoader.hero(
          message: 'settings.trial.checkingAuth'.tr(),
        ),
      ),
    );
  }
}

/// Full-screen overlay when the free trial has ended.
class TrialLockScreen extends StatefulWidget {
  const TrialLockScreen({super.key});

  @override
  State<TrialLockScreen> createState() => _TrialLockScreenState();
}

class _TrialLockScreenState extends State<TrialLockScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final license = context.read<TrialLicenseProvider>();
    final password = _passwordCtrl.text;
    setState(() {
      _busy = true;
      _error = null;
    });

    // Brief delay so the spinner is visible even on fast unlocks.
    await Future<void>.delayed(const Duration(milliseconds: 150));

    bool ok;
    if (!license.hasPassword) {
      if (password.trim().length < 4) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'settings.trial.passwordTooShort'.tr();
        });
        return;
      }
      if (password != _confirmCtrl.text) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = 'settings.trial.passwordMismatch'.tr();
        });
        return;
      }
      ok = await license.bootstrapAndUnlock(password);
    } else {
      ok = await license.unlockWithPassword(password);
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'settings.trial.wrongPassword'.tr();
    });
  }

  @override
  Widget build(BuildContext context) {
    final license = context.watch<TrialLicenseProvider>();
    final needsCreate = !license.hasPassword;

    return Material(
      color: AppColors.background.withValues(alpha: 0.97),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.modal,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'settings.trial.lockedTitle'.tr(),
                          textAlign: TextAlign.center,
                          style: AppTypography.localize(
                            AppTypography.sectionTitle,
                            context: context,
                          ).copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          needsCreate
                              ? 'settings.trial.lockedCreateHint'.tr()
                              : 'settings.trial.lockedHint'.tr(),
                          textAlign: TextAlign.center,
                          style: AppTypography.localize(
                            AppTypography.body,
                            context: context,
                          ).copyWith(
                            color: AppColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                        GfTextField(
                          controller: _passwordCtrl,
                          label: needsCreate
                              ? 'settings.trial.newPassword'.tr()
                              : 'settings.trial.ownerPassword'.tr(),
                          obscureText: _obscure,
                          enabled: !_busy,
                          onSubmitted: (_) {
                            if (!_busy) _submit();
                          },
                          // No IconButton tooltip — this screen sits outside
                          // Navigator Overlay (MaterialApp.builder).
                          suffix: IconButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        if (needsCreate) ...[
                          const SizedBox(height: 12),
                          GfTextField(
                            controller: _confirmCtrl,
                            label: 'settings.trial.confirmPassword'.tr(),
                            obscureText: _obscure,
                            enabled: !_busy,
                            onSubmitted: (_) {
                              if (!_busy) _submit();
                            },
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: AppTypography.localize(
                              AppTypography.caption,
                              context: context,
                            ).copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        GfPrimaryButton(
                          label: needsCreate
                              ? 'settings.trial.createAndUnlock'.tr()
                              : 'settings.trial.unlock'.tr(),
                          onPressed: _busy ? null : _submit,
                          isLoading: _busy,
                          expanded: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_busy)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.28),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.modal,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GfLoader.hero(
                          message: 'settings.trial.verifying'.tr(),
                        ),
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
