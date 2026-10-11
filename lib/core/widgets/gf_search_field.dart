import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Search input with magnifying glass — same height as header buttons.
class GfSearchField extends StatefulWidget {
  const GfSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = '',
    this.onChanged,
    this.onSubmitted,
    this.showShortcutHint = true,
    this.enabled = true,
    this.width,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool showShortcutHint;
  final bool enabled;
  final double? width;

  @override
  State<GfSearchField> createState() => _GfSearchFieldState();
}

class _GfSearchFieldState extends State<GfSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final bool _ownsController;
  late final bool _ownsFocusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ownsFocusNode = widget.focusNode == null;
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused ? AppColors.primary : AppColors.border;
    final borderWidth = _focused ? 1.5 : 1.0;

    final field = SizedBox(
      height: AppSpacing.controlHeight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: AppRadius.input,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) {
                  // Avoid Flutter VerticalCaretMovementRun assert (RTL / non-left).
                  if (event is KeyDownEvent || event is KeyRepeatEvent) {
                    final key = event.logicalKey;
                    if (key == LogicalKeyboardKey.arrowDown ||
                        key == LogicalKeyboardKey.arrowUp) {
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: AppColors.primary,
                  textAlign: TextAlign.start,
                  textAlignVertical: TextAlignVertical.center,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText.isEmpty
                        ? 'common.search'.tr()
                        : widget.hintText,
                    hintStyle: AppTypography.localize(
                      AppTypography.body.copyWith(color: AppColors.textMuted),
                      context: context,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );

    return widget.width != null
        ? SizedBox(width: widget.width, child: field)
        : field;
  }
}

/// Optional intent for wiring Ctrl+K / Cmd+K to focus a search field.
class GfSearchFocusIntent extends Intent {
  const GfSearchFocusIntent();
}

/// Helper to bind Ctrl+K / Cmd+K to a [FocusNode].
Map<ShortcutActivator, Intent> gfSearchShortcuts() {
  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.keyK, control: true):
        const GfSearchFocusIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
        const GfSearchFocusIntent(),
  };
}
