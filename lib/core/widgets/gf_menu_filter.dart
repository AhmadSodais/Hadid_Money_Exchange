import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'gf_date_filter.dart';

/// One choice of a [GfMenuFilter].
class GfMenuFilterOption<T> {
  const GfMenuFilterOption({
    required this.value,
    required this.label,
    required this.icon,
    this.subtitle = '',
  });

  final T value;
  final String label;
  final IconData icon;
  final String subtitle;
}

/// Single-choice filter with the same trigger and menu panel as [GfDateFilter].
class GfMenuFilter<T> extends StatefulWidget {
  const GfMenuFilter({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon = Icons.filter_alt_outlined,
    this.width = 200,
    this.panelWidth = 280,
  });

  final T value;
  final List<GfMenuFilterOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData icon;
  final double width;
  final double panelWidth;

  @override
  State<GfMenuFilter<T>> createState() => _GfMenuFilterState<T>();
}

class _GfMenuFilterState<T> extends State<GfMenuFilter<T>> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
    setState(() {});
  }

  void _select(T value) {
    _portal.hide();
    setState(() {});
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final open = _portal.isShowing;
    final border = AppColors.primary.withValues(alpha: 0.28);
    // Usually sits at the trailing edge (page or table actions); open the
    // panel from the trailing edge of the trigger so it grows inward.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final targetAnchor = isRtl ? Alignment.bottomLeft : Alignment.bottomRight;
    final followerAnchor = isRtl ? Alignment.topLeft : Alignment.topRight;
    final selected = widget.options.where((o) => o.value == widget.value).firstOrNull;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggle,
                ),
              ),
              CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                targetAnchor: targetAnchor,
                followerAnchor: followerAnchor,
                offset: const Offset(0, 6),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: widget.panelWidth,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        for (final o in widget.options)
                          GfFilterMenuItem(
                            icon: o.icon,
                            title: o.label,
                            subtitle: o.subtitle,
                            selected: o.value == widget.value,
                            onTap: () => _select(o.value),
                          ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: SizedBox(
          width: widget.width,
          height: AppSpacing.controlHeight,
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Icon(selected?.icon ?? widget.icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        selected?.label ?? '',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: AppColors.textSecondary,
                    ),
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
