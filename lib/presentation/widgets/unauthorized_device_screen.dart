import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/security/authorized_devices.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_button.dart';
import '../../core/widgets/gf_toast.dart';
import '../providers/device_authorization_provider.dart';

/// Full-screen block when this workstation is not on the authorized MAC list.
class UnauthorizedDeviceScreen extends StatelessWidget {
  const UnauthorizedDeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<DeviceAuthorizationProvider>();
    final macs = auth.detectedMacs;

    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.modal,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Icon(
                            Icons.desktop_access_disabled_rounded,
                            size: 36,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'deviceAuth.title'.tr(),
                        textAlign: TextAlign.center,
                        style: AppTypography.localize(
                          AppTypography.sectionTitle,
                          context: context,
                        ).copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'deviceAuth.message'.tr(),
                        textAlign: TextAlign.center,
                        style: AppTypography.localize(
                          AppTypography.body,
                          context: context,
                        ).copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _MacPanel(macs: macs),
                      const SizedBox(height: 22),
                      _ContactCard(
                        name: AuthorizedDevices.supportName,
                        phone: AuthorizedDevices.supportPhone,
                      ),
                      const SizedBox(height: 20),
                      GfSecondaryButton(
                        label: 'deviceAuth.retry'.tr(),
                        onPressed: auth.retry,
                        expanded: true,
                        icon: Icons.refresh_rounded,
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
}

class _MacPanel extends StatelessWidget {
  const _MacPanel({required this.macs});

  final List<String> macs;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'deviceAuth.detectedMacs'.tr(),
            style: AppTypography.localize(
              AppTypography.caption,
              context: context,
            ).copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (macs.isEmpty)
            Text(
              'deviceAuth.noMacDetected'.tr(),
              style: AppTypography.localize(
                AppTypography.bodyMedium,
                context: context,
              ).copyWith(color: AppColors.textSecondary),
            )
          else
            ...macs.map(
              (mac) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.lan_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        mac,
                        style: AppTypography.localize(
                          AppTypography.bodyMedium,
                          context: context,
                        ).copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'deviceAuth.copyMac'.tr(),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: mac));
                        if (!context.mounted) return;
                        GfToast.success(
                          context,
                          'deviceAuth.macCopied'.tr(),
                        );
                      },
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
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

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'deviceAuth.contactTitle'.tr(),
            style: AppTypography.localize(
              AppTypography.caption,
              context: context,
            ).copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.person_outline_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: AppTypography.localize(
                    AppTypography.bodyMedium,
                    context: context,
                  ).copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.phone_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  phone,
                  style: AppTypography.localize(
                    AppTypography.bodyMedium,
                    context: context,
                  ).copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'deviceAuth.copyPhone'.tr(),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: phone));
                  if (!context.mounted) return;
                  GfToast.success(context, 'deviceAuth.phoneCopied'.tr());
                },
                icon: Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
