import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/app_biometric.dart';
import '../../core/security/app_lock_crypto.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_button.dart';
import '../../core/widgets/gf_text_field.dart';
import '../providers/app_lock_provider.dart';
import 'app_lock_pads.dart';

/// Full-screen lock shown after the app is closed or minimized.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

enum _LockStep { unlock, recovery, resetEnter, resetConfirm }

class _AppLockScreenState extends State<AppLockScreen> {
  _LockStep _step = _LockStep.unlock;
  String _passcode = '';
  String? _draft;
  String? _error;
  bool _busy = false;

  /// Windows Hello prompt is open. Kept apart from [_busy] so the passcode
  /// stays typeable while the prompt is pending.
  bool _bioBusy = false;
  int _patternReset = 0;
  int _refocus = 0;
  Timer? _cooldownTimer;
  final _recoveryCtrl = TextEditingController();

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _recoveryCtrl.dispose();
    super.dispose();
  }

  void _watchCooldown() {
    _cooldownTimer?.cancel();
    if (!context.read<AppLockProvider>().isCoolingDown) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!context.read<AppLockProvider>().isCoolingDown) {
        _cooldownTimer?.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _useBiometric() async {
    if (_busy || _bioBusy) return;
    final lock = context.read<AppLockProvider>();
    if (lock.isCoolingDown) {
      setState(() => _error = 'settings.lock.cooldown'.tr());
      _watchCooldown();
      return;
    }
    setState(() {
      _bioBusy = true;
      _error = null;
    });
    final status = await lock.unlockWithBiometric(
      'settings.lock.biometricReason'.tr(),
    );
    if (!mounted) return;
    if (status == AppBiometricStatus.success) return;
    setState(() {
      _bioBusy = false;
      _refocus += 1;
      _error = switch (status) {
        AppBiometricStatus.canceled => null,
        AppBiometricStatus.notReady => 'settings.lock.helloMissing'.tr(),
        _ => 'settings.lock.biometricUnavailable'.tr(),
      };
    });
  }

  Future<void> _submitPasscode(String code) async {
    final lock = context.read<AppLockProvider>();
    if (_step == _LockStep.unlock) {
      await _tryUnlock(code);
      return;
    }
    if (_step == _LockStep.resetEnter) {
      if (!AppLockCrypto.isValidPasscode(code)) {
        setState(() => _error = 'settings.lock.tooShort'.tr());
        return;
      }
      setState(() {
        _draft = code;
        _passcode = '';
        _step = _LockStep.resetConfirm;
        _error = null;
      });
      return;
    }
    if (code != _draft) {
      setState(() {
        _passcode = '';
        _error = 'settings.lock.mismatch'.tr();
      });
      return;
    }
    setState(() => _busy = true);
    final ok = await lock.replaceAndUnlock(
      method: AppLockMethod.passcode,
      secret: code,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'settings.lock.wrong'.tr();
      });
    }
  }

  Future<void> _tryUnlock(String secret) async {
    if (_busy) return;
    final lock = context.read<AppLockProvider>();
    if (lock.isCoolingDown) {
      setState(() => _error = 'settings.lock.cooldown'.tr());
      _watchCooldown();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await lock.unlockWithSecret(secret);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _passcode = '';
        _patternReset += 1;
        _error = lock.isCoolingDown
            ? 'settings.lock.cooldown'.tr()
            : 'settings.lock.wrong'.tr();
      });
      _watchCooldown();
    }
  }

  Future<void> _onPattern(List<int> dots) async {
    if (!AppLockCrypto.isValidPattern(dots)) {
      setState(() {
        _error = 'settings.lock.patternTooShort'.tr();
        _patternReset += 1;
      });
      return;
    }
    final secret = AppLockCrypto.patternSecret(dots);
    if (_step == _LockStep.unlock) {
      await _tryUnlock(secret);
      return;
    }
    if (_step == _LockStep.resetEnter) {
      setState(() {
        _draft = secret;
        _step = _LockStep.resetConfirm;
        _patternReset += 1;
        _error = null;
      });
      return;
    }
    if (secret != _draft) {
      setState(() {
        _error = 'settings.lock.mismatch'.tr();
        _patternReset += 1;
      });
      return;
    }
    setState(() => _busy = true);
    final ok = await context.read<AppLockProvider>().replaceAndUnlock(
      method: AppLockMethod.pattern,
      secret: secret,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _patternReset += 1;
        _error = 'settings.lock.wrong'.tr();
      });
    }
  }

  Future<void> _submitRecovery() async {
    if (_busy) return;
    final lock = context.read<AppLockProvider>();
    if (lock.isCoolingDown) {
      setState(() => _error = 'settings.lock.cooldown'.tr());
      _watchCooldown();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await lock.acceptRecovery(_recoveryCtrl.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = lock.isCoolingDown
            ? 'settings.lock.cooldown'.tr()
            : 'settings.lock.wrongRecovery'.tr();
      });
      _watchCooldown();
      return;
    }
    setState(() {
      _busy = false;
      _step = _LockStep.resetEnter;
      _passcode = '';
      _draft = null;
      _error = null;
      _patternReset += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final pattern = _usesPattern(lock);
    final cooling = lock.isCoolingDown;
    final inputEnabled = !_busy && !cooling;

    return PopScope(
      canPop: false,
      child: Material(
        color: AppColors.background,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [AppColors.background, AppColors.backgroundEnd],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.modal,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 36, 32, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _badge(),
                      const SizedBox(height: 18),
                      Text(
                        _title(pattern),
                        textAlign: TextAlign.center,
                        style: AppTypography.sectionTitle.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _subtitle(pattern),
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 26),
                      if (_step == _LockStep.recovery)
                        _recoveryForm(inputEnabled)
                      else if (pattern)
                        PatternLockPad(
                          enabled: inputEnabled,
                          resetToken: _patternReset,
                          hasError: _error != null,
                          onComplete: _onPattern,
                        )
                      else
                        PasscodeInput(
                          value: _passcode,
                          enabled: inputEnabled,
                          refocusToken: _refocus,
                          hasError: _error != null,
                          key: ValueKey(_step),
                          slotCount: _step == _LockStep.unlock
                              ? lock.secretLength
                              : AppLockCrypto.passcodeLength,
                          onChanged: (value) => setState(() {
                            _passcode = value;
                            _error = null;
                          }),
                          onFilled: _submitPasscode,
                        ),
                      _errorLine(),
                      if (_step == _LockStep.unlock && lock.biometricEnabled) ...[
                        const SizedBox(height: 6),
                        GfSecondaryButton(
                          label: _biometricLabel(lock),
                          icon: lock.hasFace && !lock.hasFingerprint
                              ? Icons.face_retouching_natural
                              : Icons.fingerprint,
                          expanded: true,
                          isLoading: _bioBusy,
                          onPressed: inputEnabled ? _useBiometric : null,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 6),
                      if (_step == _LockStep.unlock)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _step = _LockStep.recovery;
                                  _error = null;
                                  _passcode = '';
                                }),
                          child: Text(
                            'settings.lock.forgot'.tr(),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      else if (_step == _LockStep.recovery)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _step = _LockStep.unlock;
                                  _error = null;
                                }),
                          child: Text(
                            'settings.lock.backToLock'.tr(),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge() {
    final icon = switch (_step) {
      _LockStep.unlock => Icons.lock_outline_rounded,
      _LockStep.recovery => Icons.key_outlined,
      _LockStep.resetEnter || _LockStep.resetConfirm => Icons.lock_reset,
    };
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primarySoft,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 6,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      child: Icon(icon, size: 34, color: AppColors.primary),
    );
  }

  Widget _errorLine() {
    return SizedBox(
      height: 34,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _error == null
              ? const SizedBox.shrink()
              : Row(
                  key: ValueKey(_error),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _recoveryForm(bool enabled) {
    return Column(
      children: [
        GfTextField(
          controller: _recoveryCtrl,
          label: 'settings.lock.recoveryPrompt'.tr(),
          prefixIcon: Icons.key_outlined,
          enabled: enabled,
          textAlign: TextAlign.center,
          autofocus: true,
          onSubmitted: (_) {
            if (enabled) _submitRecovery();
          },
        ),
        const SizedBox(height: 14),
        GfPrimaryButton(
          label: 'settings.lock.next'.tr(),
          expanded: true,
          isLoading: _busy,
          onPressed: enabled ? _submitRecovery : null,
        ),
      ],
    );
  }

  bool _usesPattern(AppLockProvider lock) {
    if (_step == _LockStep.recovery) return false;
    return lock.method == AppLockMethod.pattern;
  }

  String _title(bool pattern) {
    return switch (_step) {
      _LockStep.recovery => 'settings.lock.recoveryTitle'.tr(),
      _LockStep.resetEnter || _LockStep.resetConfirm => 'settings.lock.setNew'.tr(),
      _LockStep.unlock => 'settings.lock.unlockTitle'.tr(),
    };
  }

  String _subtitle(bool pattern) {
    return switch (_step) {
      _LockStep.recovery => 'settings.lock.recoveryEnterHint'.tr(),
      _LockStep.resetEnter =>
        pattern
            ? 'settings.lock.drawPattern'.tr()
            : 'settings.lock.enterPasscode'.tr(),
      _LockStep.resetConfirm =>
        pattern
            ? 'settings.lock.confirmPattern'.tr()
            : 'settings.lock.confirmPasscode'.tr(),
      _LockStep.unlock =>
        pattern
            ? 'settings.lock.unlockPattern'.tr()
            : 'settings.lock.unlockPasscode'.tr(),
    };
  }

  String _biometricLabel(AppLockProvider lock) {
    if (lock.hasFingerprint && lock.hasFace) {
      return 'settings.lock.hardwareBoth'.tr();
    }
    if (lock.hasFace) return 'settings.lock.hardwareFace'.tr();
    return 'settings.lock.hardwareFingerprint'.tr();
  }
}
