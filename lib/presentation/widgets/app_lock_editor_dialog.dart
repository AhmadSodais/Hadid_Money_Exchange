import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/security/app_lock_crypto.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_button.dart';
import '../../core/widgets/gf_dialog_shell.dart';
import '../../core/widgets/gf_text_field.dart';
import '../../core/widgets/gf_toast.dart';
import '../providers/app_lock_provider.dart';
import 'app_lock_pads.dart';

enum AppLockEditorMode { setup, change, disable, newRecovery }

enum _Phase { choose, enter, confirm, verify, recoveryChoice, recovery }

/// Setup, change, disable, and recovery-code flows for the app lock.
class AppLockEditorDialog extends StatefulWidget {
  const AppLockEditorDialog({super.key, required this.mode});

  final AppLockEditorMode mode;

  @override
  State<AppLockEditorDialog> createState() => _AppLockEditorDialogState();
}

class _AppLockEditorDialogState extends State<AppLockEditorDialog> {
  late _Phase _phase = widget.mode == AppLockEditorMode.setup
      ? _Phase.choose
      : _Phase.verify;

  AppLockMethod? _chosen;
  String? _verified;
  String? _draft;
  String? _recovery;
  String? _confirmedSecret;
  String _passcode = '';
  bool _savedAck = false;
  bool _busy = false;
  bool _committed = false;
  String? _error;
  int _patternReset = 0;

  /// null = not chosen yet, true = user writes it, false = generated.
  bool? _ownRecovery;
  bool _hideOwn = true;
  final _ownCtrl = TextEditingController();
  final _ownRepeatCtrl = TextEditingController();

  @override
  void dispose() {
    _ownCtrl.dispose();
    _ownRepeatCtrl.dispose();
    super.dispose();
  }

  bool get _entering =>
      _phase == _Phase.enter ||
      _phase == _Phase.confirm ||
      _phase == _Phase.verify;

  AppLockMethod _entryMethod(AppLockProvider lock) {
    if (_phase == _Phase.verify) return lock.method;
    return _chosen ?? lock.method;
  }

  int? _slots(AppLockProvider lock) {
    if (_entryMethod(lock) != AppLockMethod.passcode) return null;
    if (_phase == _Phase.verify) return lock.secretLength;
    return AppLockCrypto.passcodeLength;
  }

  String? _primaryLabel(AppLockProvider lock) {
    if (_phase == _Phase.recovery) return 'settings.lock.done'.tr();
    if (_phase == _Phase.choose || _phase == _Phase.recoveryChoice) {
      return 'settings.lock.next'.tr();
    }
    if (_entryMethod(lock) == AppLockMethod.pattern) return null;
    if (_slots(lock) != null) return null;
    return 'settings.lock.next'.tr();
  }

  String _title(AppLockProvider lock) {
    return switch (_phase) {
      _Phase.choose => 'settings.lock.chooseMethod'.tr(),
      _Phase.recoveryChoice => 'settings.lock.recoveryChoiceTitle'.tr(),
      _Phase.recovery => 'settings.lock.recoveryTitle'.tr(),
      _Phase.verify => lock.method == AppLockMethod.pattern
          ? 'settings.lock.verifyPattern'.tr()
          : 'settings.lock.verifyPasscode'.tr(),
      _Phase.enter => _entryMethod(lock) == AppLockMethod.pattern
          ? 'settings.lock.drawPattern'.tr()
          : 'settings.lock.enterPasscode'.tr(),
      _Phase.confirm => _entryMethod(lock) == AppLockMethod.pattern
          ? 'settings.lock.confirmPattern'.tr()
          : 'settings.lock.confirmPasscode'.tr(),
    };
  }

  String _subtitle(AppLockProvider lock) {
    return switch (_phase) {
      _Phase.recovery => 'settings.lock.recoveryHint'.tr(),
      _Phase.recoveryChoice => 'settings.lock.recoveryChoiceHint'.tr(),
      _Phase.choose => 'settings.lock.chooseMethodHint'.tr(),
      _Phase.verify when widget.mode == AppLockEditorMode.disable =>
        'settings.lock.turnOffHint'.tr(),
      _Phase.enter || _Phase.confirm =>
        _entryMethod(lock) == AppLockMethod.pattern
            ? 'settings.lock.patternHint'.tr()
            : 'settings.lock.passcodeHint'.tr(),
      _ => 'settings.lock.verifyHint'.tr(),
    };
  }

  void _clearEntry() {
    _passcode = '';
    _patternReset += 1;
  }

  void _cancel() {
    if (_busy) return;
    if (_phase == _Phase.recovery && !_savedAck) {
      setState(() => _error = 'settings.lock.recoveryRequired'.tr());
      return;
    }
    Navigator.pop(context, _committed);
  }

  Future<void> _submit({String? secret}) async {
    if (_busy) return;
    final lock = context.read<AppLockProvider>();
    if (lock.isCoolingDown) {
      setState(() => _error = 'settings.lock.cooldown'.tr());
      return;
    }
    if (_phase == _Phase.choose) {
      if (_chosen == null) {
        setState(() => _error = 'settings.lock.chooseMethodHint'.tr());
        return;
      }
      setState(() {
        _phase = _Phase.enter;
        _error = null;
        _clearEntry();
      });
      return;
    }
    if (_phase == _Phase.recovery) {
      if (!_savedAck) {
        setState(() => _error = 'settings.lock.recoveryRequired'.tr());
        return;
      }
      Navigator.pop(context, true);
      return;
    }
    if (_phase == _Phase.recoveryChoice) {
      await _finishRecovery(lock);
      return;
    }

    final method = _entryMethod(lock);
    final value = secret ?? _typedSecret(method);
    if (value == null) {
      setState(() {
        _error = method == AppLockMethod.passcode
            ? 'settings.lock.tooShort'.tr()
            : 'settings.lock.patternTooShort'.tr();
        _clearEntry();
      });
      return;
    }
    if (_phase == _Phase.enter) {
      setState(() {
        _draft = value;
        _phase = _Phase.confirm;
        _error = null;
        _clearEntry();
      });
      return;
    }
    if (_phase == _Phase.confirm) {
      if (value != _draft) {
        setState(() {
          _error = 'settings.lock.mismatch'.tr();
          _clearEntry();
        });
        return;
      }
      if (widget.mode == AppLockEditorMode.setup) {
        setState(() {
          _confirmedSecret = value;
          _phase = _Phase.recoveryChoice;
          _error = null;
        });
        return;
      }
      await _commit(lock, value);
      return;
    }
    await _verify(lock, value);
  }

  String? _typedSecret(AppLockMethod method) {
    if (method == AppLockMethod.passcode) {
      return AppLockCrypto.isValidPasscode(_passcode) ? _passcode : null;
    }
    return null;
  }

  void _onPattern(List<int> dots) {
    if (_busy) return;
    if (!AppLockCrypto.isValidPattern(dots)) {
      setState(() {
        _error = 'settings.lock.patternTooShort'.tr();
        _clearEntry();
      });
      return;
    }
    _submit(secret: AppLockCrypto.patternSecret(dots));
  }

  Future<void> _verify(AppLockProvider lock, String value) async {
    setState(() => _busy = true);
    if (widget.mode == AppLockEditorMode.disable) {
      final ok = await lock.disable(value);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = lock.isCoolingDown
              ? 'settings.lock.cooldown'.tr()
              : 'settings.lock.wrong'.tr();
          _clearEntry();
        });
        return;
      }
      Navigator.pop(context, true);
      return;
    }
    final ok = await lock.checkSecret(value);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = lock.isCoolingDown
            ? 'settings.lock.cooldown'.tr()
            : 'settings.lock.wrong'.tr();
        _clearEntry();
      });
      return;
    }
    setState(() {
      _busy = false;
      _verified = value;
      _phase = widget.mode == AppLockEditorMode.newRecovery
          ? _Phase.recoveryChoice
          : _Phase.choose;
      _chosen = null;
      _error = null;
      _clearEntry();
    });
  }

  /// Saves the recovery code (written by the user or generated).
  Future<void> _finishRecovery(AppLockProvider lock) async {
    final own = _ownRecovery;
    if (own == null) {
      setState(() => _error = 'settings.lock.recoveryChooseRequired'.tr());
      return;
    }
    String? custom;
    if (own) {
      final text = _ownCtrl.text.trim();
      if (!AppLockCrypto.isValidRecovery(text)) {
        setState(() => _error = 'settings.lock.recoveryTooShort'.tr());
        return;
      }
      if (AppLockCrypto.normalizeRecovery(text) !=
          AppLockCrypto.normalizeRecovery(_ownRepeatCtrl.text)) {
        setState(() => _error = 'settings.lock.recoveryMismatch'.tr());
        return;
      }
      custom = text;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final code = widget.mode == AppLockEditorMode.setup
        ? await lock.enable(
            method: _chosen!,
            secret: _confirmedSecret!,
            recovery: custom,
          )
        : await lock.regenerateRecovery(_verified!, custom: custom);
    if (!mounted) return;
    if (code == null) {
      setState(() {
        _busy = false;
        _error = lock.isCoolingDown
            ? 'settings.lock.cooldown'.tr()
            : 'settings.lock.wrong'.tr();
      });
      return;
    }
    setState(() {
      _busy = false;
      _recovery = code;
      _phase = _Phase.recovery;
      _committed = true;
      _error = null;
    });
  }

  Future<void> _commit(AppLockProvider lock, String value) async {
    setState(() => _busy = true);
    final ok = await lock.changeSecret(
      current: _verified!,
      method: _chosen!,
      next: value,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'settings.lock.wrong'.tr();
        _clearEntry();
      });
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _copy() async {
    final code = _recovery;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    GfToast.success(context, 'settings.lock.copied'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final method = _entryMethod(lock);
    final cooling = lock.isCoolingDown;
    final inputEnabled = !_busy && !cooling;
    final label = _primaryLabel(lock);

    return GfDialogShell(
      icon: Icons.lock_outline,
      title: _title(lock),
      subtitle: _subtitle(lock),
      maxWidth: 460,
      scrollBody: !_entering,
      saving: _busy,
      primaryLabel: label,
      onPrimary: label == null ? null : () => _submit(),
      onCancel: _cancel,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_phase == _Phase.choose) _methodPicker(),
          if (_phase == _Phase.recoveryChoice) _recoveryChoiceBody(),
          if (_phase == _Phase.recovery) _recoveryBody(),
          if (_entering && method == AppLockMethod.pattern)
            PatternLockPad(
              enabled: inputEnabled,
              resetToken: _patternReset,
              hasError: _error != null,
              onComplete: _onPattern,
            ),
          if (_entering && method == AppLockMethod.passcode)
            PasscodeInput(
              key: ValueKey(_phase),
              value: _passcode,
              enabled: inputEnabled,
              hasError: _error != null,
              slotCount: _slots(lock),
              onChanged: (value) => setState(() {
                _passcode = value;
                _error = null;
              }),
              onFilled: (code) {
                _passcode = code;
                _submit(secret: code);
              },
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _methodPicker() {
    return Row(
      children: [
        Expanded(
          child: _MethodTile(
            label: 'settings.lock.passcode'.tr(),
            icon: Icons.dialpad,
            selected: _chosen == AppLockMethod.passcode,
            onTap: () => setState(() {
              _chosen = AppLockMethod.passcode;
              _error = null;
            }),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MethodTile(
            label: 'settings.lock.pattern'.tr(),
            icon: Icons.gesture,
            selected: _chosen == AppLockMethod.pattern,
            onTap: () => setState(() {
              _chosen = AppLockMethod.pattern;
              _error = null;
            }),
          ),
        ),
      ],
    );
  }

  Widget _recoveryChoiceBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _MethodTile(
                label: 'settings.lock.recoveryOwn'.tr(),
                icon: Icons.edit_note,
                selected: _ownRecovery == true,
                onTap: () => setState(() {
                  _ownRecovery = true;
                  _error = null;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MethodTile(
                label: 'settings.lock.recoveryAuto'.tr(),
                icon: Icons.auto_awesome_outlined,
                selected: _ownRecovery == false,
                onTap: () => setState(() {
                  _ownRecovery = false;
                  _error = null;
                }),
              ),
            ),
          ],
        ),
        if (_ownRecovery == true) ...[
          const SizedBox(height: 16),
          GfTextField(
            controller: _ownCtrl,
            label: 'settings.lock.recoveryOwnLabel'.tr(),
            autofocus: true,
            obscureText: false,
            maxLength: AppLockCrypto.recoveryMaxLength,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            // suffix: Align(
            //   alignment: Alignment.centerLeft,
            //   child: InkWell(
            //     onTap: () => setState(() => _hideOwn = !_hideOwn),
            //     child: Icon(
            //       _hideOwn
            //           ? Icons.visibility_outlined
            //           : Icons.visibility_off_outlined,
            //       size: 20,
            //       color: AppColors.textMuted,
            //     ),
            //   ),
            // ),
          ),
          const SizedBox(height: 12),
          GfTextField(
            controller: _ownRepeatCtrl,
            label: 'settings.lock.recoveryOwnRepeat'.tr(),
            obscureText: _hideOwn,
            maxLength: AppLockCrypto.recoveryMaxLength,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'settings.lock.recoveryOwnHint'.tr(),
            style: AppTypography.caption.copyWith(height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _recoveryBody() {
    final code = _recovery ?? '';
    return Column(
      children: [
        SelectableText(
          code,
          textAlign: TextAlign.center,
          style: AppTypography.sectionTitle.copyWith(letterSpacing: 1.4),
        ),
        const SizedBox(height: 12),
        GfSecondaryButton(
          label: 'settings.lock.copy'.tr(),
          icon: Icons.copy_outlined,
          onPressed: _copy,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _savedAck,
          onChanged: (value) => setState(() {
            _savedAck = value ?? false;
            _error = null;
          }),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: AppColors.primary,
          title: Text(
            'settings.lock.recoverySaved'.tr(),
            style: AppTypography.body,
          ),
        ),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.input,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.input,
          borderRadius: AppRadius.input,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
