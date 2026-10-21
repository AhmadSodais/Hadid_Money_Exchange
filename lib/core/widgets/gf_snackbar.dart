import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../snackbar/snackbar_model.dart';
import '../snackbar/snackbar_viewmodel.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Glass snackbar colors derived from the active app theme.
@immutable
class _SbColors {
  const _SbColors._({
    required this.isLight,
    required this.glassBg,
    required this.border,
    required this.title,
    required this.description,
    required this.secondaryText,
    required this.close,
    required this.primary,
    required this.success,
    required this.warning,
    required this.error,
  });

  /// Reads [Theme.of] so cards rebuild when the theme variant changes.
  factory _SbColors.of(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return _SbColors._(
      isLight: isLight,
      glassBg: AppColors.modal.withValues(alpha: isLight ? 0.92 : 0.88),
      border: AppColors.border,
      title: AppColors.textPrimary,
      description: AppColors.textSecondary,
      secondaryText: AppColors.textMuted,
      close: AppColors.textSecondary,
      primary: AppColors.primary,
      success: AppColors.success,
      warning: AppColors.warning,
      error: AppColors.error,
    );
  }

  final bool isLight;
  final Color glassBg;
  final Color border;
  final Color title;
  final Color description;
  final Color secondaryText;
  final Color close;
  final Color primary;
  final Color success;
  final Color warning;
  final Color error;

  Color get shadow => Colors.black.withValues(alpha: isLight ? 0.12 : 0.32);
  Color get progressTrack => primary.withValues(alpha: 0.18);

  Color accentFor(SnackbarType type) => switch (type) {
        SnackbarType.success => success,
        SnackbarType.error => error,
        SnackbarType.warning => warning,
        SnackbarType.info => primary,
        SnackbarType.loading => primary,
        SnackbarType.action => primary,
      };

  Color borderFor(SnackbarType type) => switch (type) {
        SnackbarType.error => error.withValues(alpha: 0.55),
        SnackbarType.warning => warning.withValues(alpha: 0.5),
        SnackbarType.success => success.withValues(alpha: 0.4),
        _ => border,
      };
}

/// Overlay host: stacks up to 3 glass snackbars at the bottom-end.
class GfSnackbarHost extends StatelessWidget {
  const GfSnackbarHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        const _SnackbarStack(),
      ],
    );
  }
}

class _SnackbarStack extends StatefulWidget {
  const _SnackbarStack();

  @override
  State<_SnackbarStack> createState() => _SnackbarStackState();
}

class _SnackbarStackState extends State<_SnackbarStack> {
  /// Ids of cards the user expanded with "more". While any card is
  /// expanded, tapping anywhere outside the snackbar dismisses it.
  final Set<String> _expandedIds = {};

  Widget _card(SnackbarViewModel vm, SnackbarModel item, bool isRtl, {required bool spaced}) {
    final card = GfSnackbarCard(
      key: ValueKey(item.id),
      model: item,
      slideFromEnd: true,
      isRtl: isRtl,
      onClose: () => vm.dismiss(item.id),
      onExpandedChanged: (expanded) {
        setState(() {
          if (expanded) {
            _expandedIds.add(item.id);
          } else {
            _expandedIds.remove(item.id);
          }
        });
        if (expanded) {
          // Keep the card while the user is reading.
          vm.pauseDismiss(item.id);
        } else {
          vm.resumeDismiss(item.id);
        }
      },
    );
    return spaced ? Padding(padding: const EdgeInsets.only(top: 10), child: card) : card;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SnackbarViewModel>();
    final items = vm.items;
    if (items.isEmpty) return const SizedBox.shrink();
    // Forget expansions of cards that are already gone.
    _expandedIds.removeWhere((id) => items.every((e) => e.id != id));

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final cards = <Widget>[
      // Newest closest to the bottom edge.
      for (var i = items.length - 1; i >= 0; i--)
        _card(vm, items[i], isRtl, spaced: i < items.length - 1),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_expandedIds.isNotEmpty)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                // Tap outside an expanded snackbar: dismiss it.
                for (final id in _expandedIds.toList()) {
                  vm.dismiss(id);
                }
              },
            ),
          ),
        Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cards,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GfSnackbarCard extends StatefulWidget {
  const GfSnackbarCard({
    super.key,
    required this.model,
    required this.onClose,
    this.slideFromEnd = true,
    this.isRtl = false,
    this.onExpandedChanged,
  });

  final SnackbarModel model;
  final VoidCallback onClose;
  final bool slideFromEnd;
  final bool isRtl;

  /// Called when the user expands/collapses a long message via "more".
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<GfSnackbarCard> createState() => _GfSnackbarCardState();
}

class _GfSnackbarCardState extends State<GfSnackbarCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Timer? _tick;

  /// True after the user taps "more" on a long message: the full text is
  /// shown (wrapped over as many lines as it needs) until the user
  /// collapses it, closes the card, or taps outside the snackbar.
  bool _expanded = false;

  /// A message counts as long — and gets a "more" toggle — when it is
  /// likely to be clipped at the collapsed line limit: more than ~90
  /// characters, or explicit line breaks beyond two lines.
  bool get _isLong {
    final m = widget.model;
    final text = '${m.title}\n${m.message ?? ''}';
    return text.length > 90 || '\n'.allMatches(text).length > 1;
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() => _expanded = value);
    widget.onExpandedChanged?.call(value);
  }

  TextStyle _messageStyle(BuildContext context, _SbColors colors) => AppTypography.localize(
        TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1.35,
          color: colors.description,
        ),
        context: context,
      );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 250),
    );
    final beginX = widget.slideFromEnd
        ? (widget.isRtl ? -1.2 : 1.2)
        : (widget.isRtl ? 1.2 : -1.2);
    _slide = Tween<Offset>(
      begin: Offset(beginX, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _controller.reverse();
    if (mounted) widget.onClose();
  }

  IconData get _icon => switch (widget.model.type) {
        SnackbarType.success => Icons.check_circle_outline_rounded,
        SnackbarType.error => Icons.error_outline_rounded,
        SnackbarType.warning => Icons.warning_amber_rounded,
        SnackbarType.info => Icons.info_outline_rounded,
        SnackbarType.loading => Icons.hourglass_top_rounded,
        SnackbarType.action => Icons.undo_rounded,
      };

  String get _relativeTime {
    final created = widget.model.createdAt;
    if (created == null) return '';
    final sec = DateTime.now().difference(created).inSeconds;
    if (sec < 1) return 'snackbar.justNow'.tr();
    if (sec < 60) {
      return 'snackbar.secondsAgo'.tr(namedArgs: {'n': '$sec'});
    }
    final min = sec ~/ 60;
    return 'snackbar.minutesAgo'.tr(namedArgs: {'n': '$min'});
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final hasMessage =
        model.message != null && model.message!.trim().isNotEmpty;
    final radius = BorderRadius.circular(8);
    final colors = _SbColors.of(context);
    final accent = colors.accentFor(model.type);

    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 20,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                decoration: BoxDecoration(
                  color: colors.glassBg,
                  borderRadius: radius,
                  border: Border.all(color: colors.borderFor(model.type)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IconBox(
                          accent: accent,
                          child: model.isLoading
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: accent,
                                  ),
                                )
                              : Icon(_icon, size: 20, color: accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.title,
                                style: AppTypography.localize(
                                  TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                    color: colors.title,
                                  ),
                                  context: context,
                                ),
                                // Wrap onto the next lines instead of
                                // clipping with an ellipsis; collapsed
                                // cards cap at 3 lines, expanded show all.
                                softWrap: true,
                                maxLines: _expanded ? null : 3,
                              ),
                              if (hasMessage) ...[
                                const SizedBox(height: 2),
                                if (_expanded)
                                  // Very long text scrolls inside the
                                  // card instead of overflowing the screen.
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                                    ),
                                    child: SingleChildScrollView(
                                      child: Text(
                                        model.message!,
                                        style: _messageStyle(context, colors),
                                        softWrap: true,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    model.message!,
                                    style: _messageStyle(context, colors),
                                    softWrap: true,
                                    maxLines: 3,
                                  ),
                              ],
                              if (_isLong) ...[
                                const SizedBox(height: 4),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: InkWell(
                                    onTap: () => _setExpanded(!_expanded),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Text(
                                        '${(_expanded ? 'snackbar.less' : 'snackbar.more').tr()} ${_expanded ? '▴' : '▾'}',
                                        style: AppTypography.localize(
                                          TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: accent,
                                          ),
                                          context: context,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (model.hasAction) ...[
                                  _ActionButton(
                                    label: model.actionLabel!,
                                    onPressed: () {
                                      model.onAction?.call();
                                      _close();
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                _CloseButton(onPressed: _close),
                              ],
                            ),
                            if (_relativeTime.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _relativeTime,
                                style: AppTypography.localize(
                                  TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: colors.secondaryText,
                                  ),
                                  context: context,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    if (model.isLoading) ...[
                      const SizedBox(height: 10),
                      _ProgressRow(progress: model.progress ?? 0),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.child, required this.accent});

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.2),
            blurRadius: 10,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 20,
        height: 20,
        child: Icon(
          Icons.close_rounded,
          size: 16,
          color: _SbColors.of(context).close,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = _SbColors.of(context).primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: primary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.undo_rounded, size: 13, color: primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTypography.localize(
                  TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final colors = _SbColors.of(context);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: colors.progressTrack),
                  FractionallySizedBox(
                    widthFactor: p,
                    alignment: AlignmentDirectional.centerStart,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            colors.primary.withValues(alpha: 0.6),
                            colors.primary,
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
        const SizedBox(width: 12),
        Text(
          '${(p * 100).round()}%',
          style: AppTypography.localize(
            TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.description,
            ),
            context: context,
          ),
        ),
      ],
    );
  }
}
