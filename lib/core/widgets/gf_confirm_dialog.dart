import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'gf_card.dart';
import 'gf_dialog_shell.dart';
import 'gf_loader.dart';

class GfConfirmDialog extends StatelessWidget {
  const GfConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.danger = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GfConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel ?? 'common.confirm'.tr(),
        cancelLabel: cancelLabel ?? 'common.cancel'.tr(),
        danger: danger,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return GfDialogShell(
      icon: danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
      iconColor: danger ? AppColors.error : AppColors.primary,
      title: title,
      cancelLabel: cancelLabel,
      primaryLabel: confirmLabel,
      primaryIcon: danger ? Icons.delete_outline : Icons.check_rounded,
      dangerPrimary: danger,
      onCancel: () => Navigator.of(context).pop(false),
      onPrimary: () => Navigator.of(context).pop(true),
      maxWidth: 380,
      maxHeight: 360,
      body: Text(
        message,
        style: AppTypography.localize(
          AppTypography.subtitle,
          context: context,
        ),
      ),
    );
  }
}

class GfLoadingOverlay extends StatelessWidget {
  const GfLoadingOverlay({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: GfCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: GfLoader(size: 44, message: message),
        ),
      ),
    );
  }
}

class GfSkeleton extends StatelessWidget {
  const GfSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = AppRadius.md,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.hover,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class GfPageHeader extends StatelessWidget {
  const GfPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.pageTitle),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: AppTypography.subtitle),
              ],
            ],
          ),
        ),
        ...actions.map(
          (w) => Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            child: w,
          ),
        ),
      ],
    );
  }
}
