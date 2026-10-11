import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_durations.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'gf_loader.dart';

typedef GfDropdownItemBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  bool selected,
  bool highlighted,
);

typedef GfDropdownLabelBuilder<T> = String Function(T item);

/// Overlay-based dropdown that never clips inside dialogs.
///
/// Uses [OverlayPortal] + [CompositedTransformTarget]/[CompositedTransformFollower]
/// so the menu paints above modal content, flips above/below based on space,
/// supports keyboard navigation, optional search, and loading/empty/error states.
class GfDropdown<T> extends StatefulWidget {
  const GfDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.value,
    this.label,
    this.hint = '',
    this.itemBuilder,
    this.labelBuilder,
    this.enabled = true,
    this.required = false,
    this.errorText,
    this.isLoading = false,
    this.errorMessage,
    this.emptyMessage = '',
    this.searchable = false,
    this.searchHint = '',
    this.maxHeight = AppSpacing.dropdownMaxHeight,
    this.width,
    this.height,
    this.prefixIcon,
  });

  final List<T> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String hint;
  final GfDropdownItemBuilder<T>? itemBuilder;
  final GfDropdownLabelBuilder<T>? labelBuilder;
  final bool enabled;
  final bool required;
  final String? errorText;
  final bool isLoading;
  final String? errorMessage;
  final String emptyMessage;
  final bool searchable;
  final String searchHint;
  final double maxHeight;
  final double? width;
  final double? height;
  final IconData? prefixIcon;

  @override
  State<GfDropdown<T>> createState() => _GfDropdownState<T>();
}

class _GfDropdownState<T> extends State<GfDropdown<T>>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portalController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode(debugLabel: 'GfDropdown');
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final AnimationController _animController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  bool _openAbove = false;
  int _highlightIndex = -1;
  double _triggerWidth = 0;
  String _query = '';

  bool get _isOpen => _portalController.isShowing;

  String get _resolvedSearchHint => widget.searchHint.isEmpty
      ? 'products.add.dropdown.search'.tr()
      : widget.searchHint;

  String get _resolvedEmptyMessage => widget.emptyMessage.isEmpty
      ? 'products.add.dropdown.noOptions'.tr()
      : widget.emptyMessage;

  String get _resolvedHint =>
      widget.hint.isEmpty ? 'common.select'.tr() : widget.hint;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: AppDurations.normal,
    );
    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant GfDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items || oldWidget.value != widget.value) {
      _syncHighlight();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _animController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isOpen) {
      _close();
    }
  }

  List<T> get _filteredItems {
    if (!widget.searchable || _query.trim().isEmpty) return widget.items;
    final q = _query.trim().toLowerCase();
    return widget.items.where((item) {
      return _itemLabel(item).toLowerCase().contains(q);
    }).toList();
  }

  String _itemLabel(T item) {
    if (widget.labelBuilder != null) return widget.labelBuilder!(item);
    return item.toString();
  }

  void _syncHighlight() {
    final filtered = _filteredItems;
    if (widget.value == null || filtered.isEmpty) {
      _highlightIndex = filtered.isEmpty ? -1 : 0;
      return;
    }
    final idx = filtered.indexWhere((e) => e == widget.value);
    _highlightIndex = idx >= 0 ? idx : 0;
  }

  void _toggle() {
    if (!widget.enabled || widget.isLoading) return;
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    _triggerWidth = box.size.width;
    final offset = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final spaceBelow = screen.height - padding.bottom - offset.dy - box.size.height;
    final spaceAbove = offset.dy - padding.top;
    _openAbove = spaceBelow < widget.maxHeight && spaceAbove > spaceBelow;

    _query = '';
    _searchController.clear();
    _syncHighlight();

    _portalController.show();
    _animController.forward(from: 0);
    _focusNode.requestFocus();
    setState(() {});
  }

  Future<void> _close() async {
    if (!_isOpen) return;
    await _animController.reverse();
    _portalController.hide();
    if (mounted) setState(() {});
  }

  void _select(T item) {
    widget.onChanged?.call(item);
    _close();
  }

  void _moveHighlight(int delta) {
    final filtered = _filteredItems;
    if (filtered.isEmpty) return;
    setState(() {
      if (_highlightIndex < 0) {
        _highlightIndex = 0;
      } else {
        _highlightIndex =
            (_highlightIndex + delta).clamp(0, filtered.length - 1);
      }
    });
    _ensureHighlightVisible();
  }

  void _ensureHighlightVisible() {
    if (!_scrollController.hasClients || _highlightIndex < 0) return;
    const itemExtent = 44.0;
    final target = _highlightIndex * itemExtent;
    final viewTop = _scrollController.offset;
    final viewBottom = viewTop + _scrollController.position.viewportDimension;
    if (target < viewTop) {
      _scrollController.jumpTo(target);
    } else if (target + itemExtent > viewBottom) {
      _scrollController.jumpTo(target + itemExtent - _scrollController.position.viewportDimension);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_isOpen) {
        _close();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_isOpen) {
        final filtered = _filteredItems;
        if (_highlightIndex >= 0 && _highlightIndex < filtered.length) {
          _select(filtered[_highlightIndex]);
        }
        return KeyEventResult.handled;
      } else {
        _open();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (!_isOpen) {
        _open();
      } else {
        _moveHighlight(1);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_isOpen) {
        _moveHighlight(-1);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (context) => _buildOverlay(context),
        child: CompositedTransformTarget(
          link: _layerLink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.label != null) ...[
                Text.rich(
                  TextSpan(
                    text: widget.label,
                    style: AppTypography.localize(
                      AppTypography.label,
                      context: context,
                    ),
                    children: [
                      if (widget.required)
                        TextSpan(
                          text: ' *',
                          style: AppTypography.localize(
                            AppTypography.label.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                            context: context,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              SizedBox(
                width: widget.width,
                height: widget.height ?? AppSpacing.controlHeight,
                child: Material(
                  color: AppColors.input,
                  borderRadius: AppRadius.input,
                  child: InkWell(
                    onTap: widget.enabled ? _toggle : null,
                    borderRadius: AppRadius.input,
                    hoverColor: AppColors.hover,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.input,
                        border: Border.all(
                          color: widget.errorText != null
                              ? AppColors.error
                              : (_isOpen || _focusNode.hasFocus)
                                  ? AppColors.primary
                                  : AppColors.border,
                          width: (_isOpen || _focusNode.hasFocus) &&
                                  widget.errorText == null
                              ? 1.5
                              : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (widget.prefixIcon != null) ...[
                            Icon(
                              widget.prefixIcon,
                              size: 18,
                              color: widget.enabled
                                  ? AppColors.textSecondary
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(child: _buildTriggerLabel()),
                          if (widget.isLoading)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          else
                            AnimatedRotation(
                              turns: _isOpen ? 0.5 : 0,
                              duration: AppDurations.fast,
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: widget.enabled
                                    ? AppColors.textSecondary
                                    : AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.errorText != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.errorText!,
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTriggerLabel() {
    if (widget.value != null) {
      return Text(
        _itemLabel(widget.value as T),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.start,
        style: AppTypography.localize(
          AppTypography.body.copyWith(
            color:
                widget.enabled ? AppColors.textPrimary : AppColors.textMuted,
          ),
          context: context,
        ),
      );
    }
    return Text(
      _resolvedHint,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.start,
      style: AppTypography.localize(
        AppTypography.body.copyWith(color: AppColors.textMuted),
        context: context,
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final filtered = _filteredItems;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    // Align menu to the start edge: left in English (LTR), right in Persian (RTL).
    final Alignment targetAnchor;
    final Alignment followerAnchor;
    if (_openAbove) {
      targetAnchor = isRtl ? Alignment.topRight : Alignment.topLeft;
      followerAnchor = isRtl ? Alignment.bottomRight : Alignment.bottomLeft;
    } else {
      targetAnchor = isRtl ? Alignment.bottomRight : Alignment.bottomLeft;
      followerAnchor = isRtl ? Alignment.topRight : Alignment.topLeft;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: Offset(0, _openAbove ? -6 : 6),
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              alignment: _openAbove
                  ? (isRtl ? Alignment.bottomRight : Alignment.bottomLeft)
                  : (isRtl ? Alignment.topRight : Alignment.topLeft),
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: widget.width ?? _triggerWidth,
                  child: Container(
                    constraints: BoxConstraints(maxHeight: widget.maxHeight),
                    decoration: BoxDecoration(
                      color: AppColors.modal,
                      borderRadius: AppRadius.input,
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.dropdown,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.searchable) _buildSearch(),
                        Flexible(child: _buildMenuBody(filtered)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchController,
          autofocus: true,
          style: AppTypography.localize(AppTypography.body, context: context),
          cursorColor: AppColors.primary,
          textAlign: TextAlign.start,
          onChanged: (v) {
            setState(() {
              _query = v;
              _syncHighlight();
            });
          },
          decoration: InputDecoration(
            hintText: _resolvedSearchHint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 32),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuBody(List<T> filtered) {
    if (widget.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: GfLoader.compact()),
      );
    }

    if (widget.errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          widget.errorMessage!,
          textAlign: TextAlign.center,
          style: AppTypography.subtitle.copyWith(color: AppColors.error),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          _resolvedEmptyMessage,
          textAlign: TextAlign.center,
          style: AppTypography.subtitle,
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      shrinkWrap: true,
      itemExtent: 44,
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        final selected = widget.value == item;
        final highlighted = index == _highlightIndex;

        return Material(
          color: highlighted
              ? AppColors.hover
              : selected
                  ? AppColors.activeGlow.withValues(alpha: 0.12)
                  : Colors.transparent,
          child: InkWell(
            onTap: () => _select(item),
            onHover: (hovering) {
              if (hovering && _highlightIndex != index) {
                setState(() => _highlightIndex = index);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: widget.itemBuilder != null
                  ? widget.itemBuilder!(context, item, selected, highlighted)
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _itemLabel(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.start,
                        style: AppTypography.body.copyWith(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
