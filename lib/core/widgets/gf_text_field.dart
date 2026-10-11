import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/formatters.dart';
import 'gf_dialog_shell.dart';

/// Shared app text field — use this for **all** dialogs and forms.
///
/// Change height, padding, or chrome here; every screen that uses
/// [GfTextField] picks it up. Prefer this over raw [TextField].
///
/// **Height:** single-line = [AppSpacing.controlHeight] (aligned with
/// [GfDropdown] / search / buttons). Text is vertically centered.
/// Errors render below the chrome.
///
/// Notes: `minLines: 1, maxLines: 2` stays one line until a second is needed.
class GfTextField extends StatefulWidget {
  const GfTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.errorText,
    this.prefix,
    this.prefixIcon,
    this.suffix,
    this.suffixIcon,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.required = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.numberMode = false,
    this.autofocus = false,
    this.onTap,
    this.height,
    this.textAlign = TextAlign.start,
    this.borderless = false,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final Widget? prefix;
  final IconData? prefixIcon;
  final Widget? suffix;
  final IconData? suffixIcon;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool required;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool numberMode;
  final bool autofocus;
  final VoidCallback? onTap;

  /// Override for single-line height. Defaults to [AppSpacing.controlHeight].
  final double? height;

  final TextAlign textAlign;

  /// No outline chrome (e.g. qty stepper cell inside an existing border).
  final bool borderless;

  @override
  State<GfTextField> createState() => _GfTextFieldState();
}

class _GfTextFieldState extends State<GfTextField> {
  late TextEditingController _controller;
  late bool _ownsController;
  FocusNode? _ownedFocus;
  bool _focused = false;
  String? _validationError;

  bool get _isSingleLine {
    if (widget.obscureText) return true;
    final max = widget.maxLines ?? 1;
    final min = widget.minLines ?? 1;
    return max <= 1 && min <= 1;
  }

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocus!;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        TextEditingController(text: widget.initialValue ?? '');
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode();
    }
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(GfTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller =
          widget.controller ??
          TextEditingController(text: widget.initialValue ?? '');
    } else if (_ownsController &&
        oldWidget.initialValue != widget.initialValue &&
        widget.initialValue != null &&
        !_focusNode.hasFocus) {
      _controller.text = widget.initialValue!;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      _focusNode.removeListener(_onFocusChange);
      if (oldWidget.focusNode == null) {
        _ownedFocus?.dispose();
        _ownedFocus = null;
      }
      if (widget.focusNode == null) {
        _ownedFocus = FocusNode();
      }
      _focusNode.addListener(_onFocusChange);
    }
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
    _ownedFocus?.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    if (widget.validator != null) {
      final err = widget.validator!(value);
      if (err != _validationError) {
        setState(() => _validationError = err);
      }
    }
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final formatters = <TextInputFormatter>[
      ...?widget.inputFormatters,
      if (widget.numberMode) ...[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
        const ThousandsSeparatorInputFormatter(),
      ],
    ];
    final textStyle = AppTypography.fieldStyle(context: context);
    final controlH = widget.height ?? AppSpacing.controlHeight;
    final externalError = widget.errorText;
    final showError =
        (externalError != null && externalError.isNotEmpty) ||
        (_validationError != null && _validationError!.isNotEmpty);
    final errorMessage = (externalError != null && externalError.isNotEmpty)
        ? externalError
        : (_validationError ?? '');

    final borderColor = !widget.enabled
        ? AppColors.border
        : showError
        ? AppColors.error
        : _focused
        ? AppColors.primary
        : AppColors.border;
    final borderWidth = _focused && !showError ? 1.5 : 1.0;

    final minLines = widget.obscureText
        ? 1
        : (widget.minLines ?? (_isSingleLine ? 1 : 1));
    final maxLines = widget.obscureText ? 1 : (widget.maxLines ?? 1);

    final textField = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        // Flutter bug: VerticalCaretMovementRun asserts when textAlign is not
        // left (common with RTL TextAlign.start). Swallow ↑/↓ in fields.
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
        onChanged: _handleChanged,
        onSubmitted: (value) {
          widget.onSubmitted?.call(value);
          // In dialogs, Enter on a single-line field triggers Save.
          if (_isSingleLine) {
            GfDialogActions.maybeOf(context)?.onSave?.call();
          }
        },
        enabled: widget.enabled,
        readOnly: widget.readOnly,
        obscureText: widget.obscureText,
        maxLines: maxLines,
        minLines: minLines,
        maxLength: widget.maxLength,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        keyboardType: widget.numberMode
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : widget.keyboardType,
        textInputAction:
            widget.textInputAction ??
            (_isSingleLine ? TextInputAction.done : TextInputAction.newline),
        inputFormatters: formatters.isEmpty ? null : formatters,
        style: textStyle,
        cursorColor: AppColors.primary,
        // Text fields follow locale (RTL for fa/ps). Number fields default to
        // the trailing edge unless [textAlign] is explicitly center.
        textAlign: widget.numberMode
            ? (widget.textAlign == TextAlign.center
                ? TextAlign.center
                : (Directionality.of(context) == TextDirection.rtl
                    ? TextAlign.right
                    : TextAlign.left))
            : widget.textAlign,
        textDirection: widget.numberMode
            ? TextDirection.ltr
            : Directionality.of(context),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: (widget.hint != null && widget.hint!.trim().isNotEmpty)
              ? widget.hint
              : (widget.numberMode ? '0' : null),
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          hintStyle: AppTypography.localize(
            AppTypography.body.copyWith(color: AppColors.textMuted),
            context: context,
          ),
          prefixIcon: widget.prefixIcon != null
              ? Icon(widget.prefixIcon, size: 18, color: AppColors.textMuted)
              : null,
          prefixIconConstraints: widget.prefixIcon != null
              ? BoxConstraints(minWidth: 40, minHeight: controlH - 2)
              : null,
          prefix: widget.prefix,
          suffixIcon: widget.suffixIcon != null
              ? Icon(widget.suffixIcon, size: 18, color: AppColors.textMuted)
              : null,
          suffixIconConstraints: widget.suffixIcon != null
              ? BoxConstraints(minWidth: 40, minHeight: controlH - 2)
              : null,
          suffix: widget.suffix,
          counterText: '',
        ),
      ),
    );

    final sized = _isSingleLine
        ? SizedBox(height: controlH, child: textField)
        : textField;

    final chrome = widget.borderless
        ? sized
        : DecoratedBox(
            decoration: BoxDecoration(
              color: widget.enabled ? AppColors.input : AppColors.surface,
              borderRadius: AppRadius.input,
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: sized,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          _FieldLabel(label: widget.label!, required: widget.required),
          const SizedBox(height: AppSpacing.xs),
        ],
        chrome,
        if (showError) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            errorMessage,
            style: AppTypography.localize(
              AppTypography.caption.copyWith(color: AppColors.error),
              context: context,
            ),
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.required});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTypography.localize(
      AppTypography.label,
      context: context,
    );
    return Text.rich(
      TextSpan(
        text: label,
        style: labelStyle,
        children: [
          if (required)
            TextSpan(
              text: ' *',
              style: labelStyle.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
