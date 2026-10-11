import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/security/app_lock_crypto.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';

/// Passcode boxes typed with the physical keyboard (no on-screen keypad).
///
/// Backed by an invisible [TextField] so dialog autofocus lands here and any
/// keyboard layout (Latin, Persian, Arabic digits, numpad, paste) works.
class PasscodeInput extends StatefulWidget {
  const PasscodeInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.onFilled,
    this.onSubmit,
    this.maxLength = AppLockCrypto.passcodeLength,
    this.slotCount,
    this.enabled = true,
    this.hasError = false,
    this.refocusToken = 0,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// Changing this pulls keyboard focus back to the field.
  final int refocusToken;

  /// Called once [value] reaches [slotCount].
  final ValueChanged<String>? onFilled;

  /// Called on Enter. Inside a dialog, Enter is handled by the dialog itself.
  final VoidCallback? onSubmit;
  final int maxLength;

  /// When set, exactly that many boxes are shown and entry submits when full.
  final int? slotCount;
  final bool enabled;

  /// Turning this on shakes the boxes and tints them red.
  final bool hasError;

  @override
  State<PasscodeInput> createState() => _PasscodeInputState();
}

class _PasscodeInputState extends State<PasscodeInput>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _focus = FocusNode();
  final _eyeFocus = FocusNode(skipTraversal: true);
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.value,
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _reveal = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _grabFocus());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _grabFocus());
    }
  }

  @override
  void didUpdateWidget(PasscodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ctrl.text != widget.value) {
      _ctrl.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
    if ((widget.enabled && !oldWidget.enabled) ||
        widget.refocusToken != oldWidget.refocusToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _grabFocus());
    }
    if (widget.hasError && !oldWidget.hasError) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _eyeFocus.dispose();
    _ctrl.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  void _grabFocus() {
    if (mounted) _focus.requestFocus();
  }

  int get _limit => widget.slotCount ?? widget.maxLength;

  int get _boxes {
    final slots = widget.slotCount;
    if (slots != null && slots > 0) return slots;
    return (widget.value.length + 1).clamp(4, widget.maxLength);
  }

  void _changed(String text) {
    if (text == widget.value) return;
    widget.onChanged(text);
    final slots = widget.slotCount;
    if (slots != null && text.length == slots) {
      widget.onFilled?.call(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                const eye = 40.0;
                final count = _boxes;
                final room = constraints.maxWidth - (eye + gap) * 2;
                final size = math.min(52.0, (room - gap * (count - 1)) / count);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: eye + gap),
                    Stack(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < count; i++) ...[
                              if (i > 0) const SizedBox(width: gap),
                              _box(i, size, focused),
                            ],
                          ],
                        ),
                        Positioned.fill(child: _hiddenField()),
                      ],
                    ),
                    const SizedBox(width: gap),
                    SizedBox(
                      width: eye,
                      height: eye,
                      child: IconButton(
                        onPressed: () => setState(() => _reveal = !_reveal),
                        focusNode: _eyeFocus,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          _reveal
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _grabFocus,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Row(
              key: ValueKey(focused),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  focused ? Icons.keyboard_outlined : Icons.touch_app_outlined,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  focused
                      ? 'settings.lock.typeHint'.tr()
                      : 'settings.lock.clickToType'.tr(),
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _hiddenField() {
    return Opacity(
      opacity: 0,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: true,
        readOnly: !widget.enabled,
        showCursor: false,
        enableInteractiveSelection: false,
        enableSuggestions: false,
        autocorrect: false,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [_PasscodeFormatter(_limit)],
        style: const TextStyle(color: Colors.transparent, fontSize: 1),
        decoration: const InputDecoration.collapsed(hintText: null),
        onChanged: _changed,
        onSubmitted: (_) => widget.onSubmit?.call(),
      ),
    );
  }

  Widget _box(int index, double size, bool focused) {
    final filled = index < widget.value.length;
    final active = focused && widget.enabled && index == widget.value.length;
    final error = widget.hasError;
    final borderColor = error
        ? AppColors.error
        : active
        ? AppColors.primary
        : filled
        ? AppColors.primary.withValues(alpha: 0.45)
        : AppColors.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size * 1.12,
      decoration: BoxDecoration(
        color: filled ? AppColors.primarySoft : AppColors.input,
        borderRadius: AppRadius.input,
        border: Border.all(color: borderColor, width: active ? 2 : 1.2),
        boxShadow: active
            ? [BoxShadow(color: AppColors.focusRing, spreadRadius: 3)]
            : null,
      ),
      alignment: Alignment.center,
      child: !filled
          ? (active ? _Caret(height: size * 0.42) : null)
          : _reveal
          ? Text(
              widget.value[index],
              style: AppTypography.sectionTitle.copyWith(
                fontSize: 22,
                color: AppColors.textPrimary,
              ),
            )
          : Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: error ? AppColors.error : AppColors.primary,
              ),
            ),
    );
  }
}

/// Keeps digits only (Persian / Arabic digits become 0–9) up to [limit].
class _PasscodeFormatter extends TextInputFormatter {
  _PasscodeFormatter(this.limit);

  final int limit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    for (final rune in newValue.text.runes) {
      final digit = _asciiDigit(rune);
      if (digit != null) buffer.write(digit);
    }
    var text = buffer.toString();
    if (text.length > limit) text = text.substring(0, limit);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

String? _asciiDigit(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return String.fromCharCode(rune);
  if (rune >= 0x06F0 && rune <= 0x06F9) return '${rune - 0x06F0}';
  if (rune >= 0x0660 && rune <= 0x0669) return '${rune - 0x0660}';
  return null;
}

class _Caret extends StatefulWidget {
  const _Caret({required this.height});

  final double height;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) => Opacity(
        opacity: _blink.value < 0.5 ? 1 : 0,
        child: Container(
          width: 2,
          height: widget.height,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// 3×3 pattern pad. Completes when the pointer is released.
class PatternLockPad extends StatefulWidget {
  const PatternLockPad({
    super.key,
    required this.onComplete,
    this.enabled = true,
    this.resetToken = 0,
    this.hasError = false,
  });

  final ValueChanged<List<int>> onComplete;
  final bool enabled;
  final int resetToken;
  final bool hasError;

  @override
  State<PatternLockPad> createState() => _PatternLockPadState();
}

class _PatternLockPadState extends State<PatternLockPad> {
  static const double _size = 240;

  final List<int> _dots = [];
  Offset? _finger;

  @override
  void didUpdateWidget(PatternLockPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _dots.clear();
      _finger = null;
    }
  }

  Offset _center(int index) {
    const cell = _size / 3;
    return Offset(
      cell * (index % 3) + cell / 2,
      cell * (index ~/ 3) + cell / 2,
    );
  }

  void _add(int index) {
    if (_dots.contains(index)) return;
    if (_dots.isNotEmpty) {
      final middle = AppLockCrypto.patternBridge(_dots.last, index);
      if (middle != null && !_dots.contains(middle)) {
        _dots.add(middle);
      }
    }
    if (!_dots.contains(index)) _dots.add(index);
  }

  void _track(Offset local) {
    if (!widget.enabled) return;
    const cell = _size / 3;
    for (var i = 0; i < 9; i++) {
      if ((local - _center(i)).distance <= cell * 0.34) {
        _add(i);
        break;
      }
    }
    setState(() => _finger = local);
  }

  void _finish() {
    final drawn = List<int>.from(_dots);
    setState(() => _finger = null);
    if (drawn.isEmpty) return;
    widget.onComplete(drawn);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.precise
            : SystemMouseCursors.basic,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: widget.enabled
              ? (event) {
                  _dots.clear();
                  _track(event.localPosition);
                }
              : null,
          onPointerMove: widget.enabled
              ? (event) => _track(event.localPosition)
              : null,
          onPointerUp: widget.enabled ? (_) => _finish() : null,
          onPointerCancel: widget.enabled
              ? (_) => setState(() => _finger = null)
              : null,
          child: CustomPaint(
            size: const Size(_size, _size),
            painter: _PatternPainter(
              dots: List<int>.from(_dots),
              finger: _finger,
              centerFor: _center,
              color: widget.hasError && _dots.isEmpty
                  ? AppColors.error
                  : AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.dots,
    required this.finger,
    required this.centerFor,
    required this.color,
  });

  final List<int> dots;
  final Offset? finger;
  final Offset Function(int index) centerFor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < dots.length - 1; i++) {
      canvas.drawLine(centerFor(dots[i]), centerFor(dots[i + 1]), line);
    }
    if (dots.isNotEmpty && finger != null) {
      canvas.drawLine(centerFor(dots.last), finger!, line);
    }

    for (var i = 0; i < 9; i++) {
      final center = centerFor(i);
      final selected = dots.contains(i);
      if (selected) {
        canvas.drawCircle(
          center,
          22,
          Paint()..color = color.withValues(alpha: 0.16),
        );
      }
      canvas.drawCircle(
        center,
        selected ? 9 : 6,
        Paint()
          ..color = selected
              ? color
              : color == AppColors.error
              ? AppColors.error.withValues(alpha: 0.6)
              : AppColors.textMuted,
      );
    }
  }

  @override
  bool shouldRepaint(_PatternPainter oldDelegate) => true;
}
