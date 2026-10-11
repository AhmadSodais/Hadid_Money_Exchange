import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../snackbar/snackbar_model.dart';
import '../snackbar/snackbar_viewmodel.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'gf_card.dart';
import 'toast_message_localizer.dart';

/// Toast facade — routes to the Violet Dusk glass snackbar overlay.
///
/// Existing call sites pass a single [message]; it becomes the snackbar title.
/// Prefer [show] with explicit [title] + [message] for richer notifications.
/// Messages are localized to the active app language when possible.
class GfToast {
  static SnackbarViewModel? _vm;

  /// Called once from app bootstrap so toasts work without a context lookup.
  static void bind(SnackbarViewModel vm) => _vm = vm;

  static SnackbarViewModel _requireVm([BuildContext? context]) {
    if (_vm != null) return _vm!;
    if (context != null) {
      return context.read<SnackbarViewModel>();
    }
    throw StateError('SnackbarViewModel is not bound. Call GfToast.bind().');
  }

  static String show(
    BuildContext context, {
    String? title,
    required String message,
    GfToastType type = GfToastType.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
    double? progress,
  }) {
    final vm = _requireVm(context);
    final mapped = switch (type) {
      GfToastType.success => SnackbarType.success,
      GfToastType.error => SnackbarType.error,
      GfToastType.warning => SnackbarType.warning,
      GfToastType.info => SnackbarType.info,
      GfToastType.loading => SnackbarType.loading,
      GfToastType.action => SnackbarType.action,
    };

    final localizedMessage = ToastMessageLocalizer.resolve(message);
    final localizedTitle = title == null || title.trim().isEmpty
        ? null
        : ToastMessageLocalizer.resolve(title);
    final hasTitle = localizedTitle != null && localizedTitle.trim().isNotEmpty;
    final hasMessage = localizedMessage.trim().isNotEmpty;
    return vm.show(
      title: hasTitle ? localizedTitle.trim() : localizedMessage,
      message: hasTitle
          ? (hasMessage ? localizedMessage : null)
          : null,
      type: mapped,
      actionLabel: actionLabel == null || actionLabel.trim().isEmpty
          ? null
          : ToastMessageLocalizer.resolve(actionLabel),
      onAction: onAction,
      duration: duration,
      progress: progress,
    );
  }

  static void success(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(
        context,
        title: title,
        message: message,
        type: GfToastType.success,
        duration: duration,
      );

  static void error(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(
        context,
        title: title,
        message: message,
        type: GfToastType.error,
        duration: duration,
      );

  static void warning(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(
        context,
        title: title,
        message: message,
        type: GfToastType.warning,
        duration: duration,
      );

  static void info(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) =>
      show(
        context,
        title: title,
        message: message,
        type: GfToastType.info,
        duration: duration,
      );

  static String loading(
    BuildContext context, {
    required String title,
    String? message,
    double? progress,
  }) =>
      show(
        context,
        title: title,
        message: message ?? '',
        type: GfToastType.loading,
        progress: progress,
        duration: Duration.zero,
      );

  static void updateLoading(
    BuildContext context,
    String id, {
    String? title,
    String? message,
    double? progress,
  }) {
    _requireVm(context).update(
      id,
      title: title == null ? null : ToastMessageLocalizer.resolve(title),
      message: message == null ? null : ToastMessageLocalizer.resolve(message),
      progress: progress,
    );
  }

  static void dismiss(BuildContext context, String id) =>
      _requireVm(context).dismiss(id);

  static String action(
    BuildContext context, {
    required String title,
    String? message,
    required String actionLabel,
    required VoidCallback onAction,
    Duration? duration,
  }) =>
      show(
        context,
        title: title,
        message: message ?? '',
        type: GfToastType.action,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration ?? const Duration(seconds: 6),
      );
}

enum GfToastType { success, error, warning, info, loading, action }

class GfToggleCard extends StatelessWidget {
  const GfToggleCard({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GfCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.localize(
                    AppTypography.bodyMedium,
                    context: context,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTypography.localize(
                      AppTypography.caption,
                      context: context,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
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
