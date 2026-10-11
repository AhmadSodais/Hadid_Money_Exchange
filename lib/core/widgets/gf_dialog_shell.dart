import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../keyboard/gf_keyboard.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';
import '../utils/gf_breakpoints.dart';
import 'gf_button.dart';
import 'gf_scroll_behavior.dart';

/// Exposes dialog Save to descendants (e.g. [GfTextField] on Enter).
class GfDialogActions extends InheritedWidget {
  const GfDialogActions({
    super.key,
    required this.onSave,
    required super.child,
  });

  final VoidCallback? onSave;

  static GfDialogActions? maybeOf(BuildContext context) {
    return context
        .getElementForInheritedWidgetOfExactType<GfDialogActions>()
        ?.widget as GfDialogActions?;
  }

  @override
  bool updateShouldNotify(GfDialogActions oldWidget) =>
      onSave != oldWidget.onSave;
}

/// Shared dialog chrome matching inbound / outbound stock dialogs.
///
/// Escape cancels; Enter / Ctrl+S / Ctrl+Enter saves when [onPrimary] is set.
class GfDialogShell extends StatelessWidget {
  const GfDialogShell({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.onCancel,
    this.iconColor,
    this.subtitle,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.cancelLabel,
    this.saving = false,
    this.dangerPrimary = false,
    this.scrollBody = true,
    this.fixedHeight = false,
    this.headerAction,
    this.maxWidth = 440,
    this.maxHeight = 720,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget body;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;
  final String? cancelLabel;
  final VoidCallback onCancel;
  final bool saving;
  final bool dangerPrimary;
  final bool scrollBody;

  /// Always use the (screen-clamped) [maxHeight] so the dialog does not
  /// shrink when the body content gets shorter, e.g. an empty search result.
  final bool fixedHeight;

  /// Shown in the header instead of the close icon; Cancel / Escape still close.
  final Widget? headerAction;
  final double maxWidth;
  final double maxHeight;

  void _save() {
    if (saving || onPrimary == null) return;
    onPrimary!();
  }

  void _cancel() {
    if (saving) return;
    onCancel();
  }

  void _onEnter() {
    // Allow newline in multi-line fields; otherwise Enter = Save.
    if (gfFocusInMultilineTextInput()) return;
    if (primaryLabel != null && primaryLabel!.trim().isNotEmpty) {
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedCancel = cancelLabel ?? 'common.cancel'.tr();
    final accent = iconColor ?? AppColors.primary;
    final showPrimary = primaryLabel != null && primaryLabel!.trim().isNotEmpty;

    final clampedW = GfBreakpoints.dialogMaxWidth(context, preferred: maxWidth);
    final clampedH = GfBreakpoints.dialogMaxHeight(
      context,
      preferred: maxHeight,
    );

    final lang = context.locale.languageCode;
    final dialogDirection =
        (lang == 'fa' || lang == 'ps') ? TextDirection.rtl : TextDirection.ltr;

    return Dialog(
      backgroundColor: AppColors.modal,
      elevation: 12,
      shadowColor: const Color(0x26502D55),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.modal,
        side: BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Directionality(
        textDirection: dialogDirection,
        child: GfDialogActions(
          onSave: showPrimary ? _save : null,
          child: GfKeyboardScope(
            dialogMode: true,
            autofocus: true,
            onCancel: _cancel,
            onSave: showPrimary ? _save : null,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _onEnter,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): _onEnter,
              },
              child: FocusTraversalGroup(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: clampedW,
                    minHeight: fixedHeight ? clampedH : 0,
                    maxHeight: clampedH,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(icon, color: accent, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: AppTypography.sectionTitle.copyWith(
                                      fontSize: 17,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (subtitle != null &&
                                      subtitle!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (headerAction != null)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 8,
                                  end: 8,
                                ),
                                child: headerAction,
                              )
                            else
                              IconButton(
                                onPressed: saving ? null : _cancel,
                                icon: Icon(
                                  Icons.close,
                                  color: AppColors.textMuted,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ),
                      Flexible(
                        fit: fixedHeight ? FlexFit.tight : FlexFit.loose,
                        child: scrollBody
                            ? ScrollConfiguration(
                                behavior: const GfScrollBehavior(
                                  reserveGutter: false,
                                ),
                                child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 4, 20, 8),
                                  child: ScrollConfiguration(
                                    behavior: const GfScrollBehavior(),
                                    child: body,
                                  ),
                                ),
                              )
                            : Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 4, 20, 8),
                                child: body,
                              ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.divider),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                        // Keep Cancel/Save on the physical right in RTL locales
                        // without flipping the rest of the dialog.
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GfSecondaryButton(
                                  label: resolvedCancel,
                                  compact: true,
                                  onPressed: saving ? null : _cancel,
                                ),
                                if (showPrimary) ...[
                                  const SizedBox(width: 10),
                                  if (dangerPrimary)
                                    GfDangerButton(
                                      label: saving
                                          ? 'common.loading'.tr()
                                          : primaryLabel!,
                                      icon: primaryIcon,
                                      compact: true,
                                      onPressed: saving ? null : _save,
                                    )
                                  else
                                    GfPrimaryButton(
                                      label: saving
                                          ? 'common.loading'.tr()
                                          : primaryLabel!,
                                      icon: primaryIcon,
                                      compact: true,
                                      onPressed: saving ? null : _save,
                                    ),
                                ],
                              ],
                            ),
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
}
