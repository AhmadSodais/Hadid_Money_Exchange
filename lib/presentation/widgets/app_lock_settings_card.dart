import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_button.dart';
import '../../core/widgets/gf_toast.dart';
import '../providers/app_lock_provider.dart';
import 'app_lock_editor_dialog.dart';

/// Settings section for the app passcode, pattern, and Windows Hello.
class AppLockSettingsCard extends StatefulWidget {
  const AppLockSettingsCard({super.key, this.padding = 20});

  final double padding;

  @override
  State<AppLockSettingsCard> createState() => _AppLockSettingsCardState();
}

class _AppLockSettingsCardState extends State<AppLockSettingsCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppLockProvider>().refreshHardware();
    });
  }

  Future<void> _open(AppLockEditorMode mode) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppLockEditorDialog(mode: mode),
    );
    if (ok != true || !mounted) return;
    final message = switch (mode) {
      AppLockEditorMode.setup => 'settings.lock.successOn'.tr(),
      AppLockEditorMode.change => 'settings.lock.successChange'.tr(),
      AppLockEditorMode.disable => 'settings.lock.successOff'.tr(),
      AppLockEditorMode.newRecovery => 'settings.lock.successRecovery'.tr(),
    };
    GfToast.success(context, message);
  }

  Future<void> _toggleBiometric(bool value) async {
    final result = await context.read<AppLockProvider>().setBiometricEnabled(
      value,
      'settings.lock.biometricReason'.tr(),
    );
    if (!mounted || !value) return;
    if (result == AppLockBiometricUpdate.notReady) {
      GfToast.error(context, 'settings.lock.helloMissing'.tr());
    } else if (result == AppLockBiometricUpdate.unavailable) {
      GfToast.error(context, 'settings.lock.biometricUnavailable'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final pad = widget.padding;
    final pattern = lock.method == AppLockMethod.pattern;

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
              Icon(Icons.lock_outline, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'settings.appLockTitle'.tr(),
                  style: AppTypography.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: pad * 0.7),
          Text(
            'settings.lock.subtitle'.tr(),
            style: AppTypography.subtitle.copyWith(height: 1.45),
          ),
          SizedBox(height: pad * 0.7),
          if (!lock.isEnabled)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: GfPrimaryButton(
                label: 'settings.lock.setup'.tr(),
                icon: Icons.lock_outline,
                onPressed: () => _open(AppLockEditorMode.setup),
              ),
            )
          else ...[
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
                    pattern ? Icons.gesture : Icons.dialpad,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pattern
                          ? 'settings.lock.methodPattern'.tr()
                          : 'settings.lock.methodPasscode'.tr(),
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            if (lock.hasBiometricHardware) ...[
              SizedBox(height: pad * 0.7),
              _BiometricToggle(
                lock: lock,
                onChanged: _toggleBiometric,
              ),
            ],
            SizedBox(height: pad * 0.8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                GfPrimaryButton(
                  label: pattern
                      ? 'settings.lock.changePattern'.tr()
                      : 'settings.lock.changePasscode'.tr(),
                  icon: Icons.edit_outlined,
                  onPressed: () => _open(AppLockEditorMode.change),
                ),
                GfSecondaryButton(
                  label: 'settings.lock.newRecovery'.tr(),
                  icon: Icons.key_outlined,
                  onPressed: () => _open(AppLockEditorMode.newRecovery),
                ),
                GfDangerButton(
                  label: 'settings.lock.turnOff'.tr(),
                  icon: Icons.lock_open_outlined,
                  onPressed: () => _open(AppLockEditorMode.disable),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BiometricToggle extends StatelessWidget {
  const _BiometricToggle({required this.lock, required this.onChanged});

  final AppLockProvider lock;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = lock.hasFingerprint && lock.hasFace
        ? 'settings.lock.hardwareBoth'.tr()
        : lock.hasFace
        ? 'settings.lock.hardwareFace'.tr()
        : 'settings.lock.hardwareFingerprint'.tr();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.input,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            lock.hasFace && !lock.hasFingerprint
                ? Icons.face_retouching_natural
                : Icons.fingerprint,
            color: AppColors.primary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  'settings.lock.biometricHint'.tr(),
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          Switch(
            value: lock.biometricEnabled,
            onChanged: onChanged,
            activeThumbColor: AppColors.primaryDarkText,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: AppColors.textSecondary,
            inactiveTrackColor: AppColors.input,
          ),
        ],
      ),
    );
  }
}
