import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// One entry of a [GfActionMenu].
class GfActionMenuItem {
  const GfActionMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
}

/// Compact trigger that opens a list of actions, styled like [GfDateFilter]
/// so the two can sit side by side in page actions.
class GfActionMenu extends StatefulWidget {
  const GfActionMenu({
    super.key,
    required this.label,
    required this.items,
    this.icon = Icons.more_horiz_rounded,
    this.width = 200,
  });

  final String label;
  final IconData icon;
  final List<GfActionMenuItem> items;
  final double width;

  @override
  State<GfActionMenu> createState() => _GfActionMenuState();
}

class _GfActionMenuState extends State<GfActionMenu> {
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

  void _select(GfActionMenuItem item) {
    _portal.hide();
    setState(() {});
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final open = _portal.isShowing;
    final border = AppColors.primary.withValues(alpha: 0.28);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final targetAnchor = isRtl ? Alignment.bottomLeft : Alignment.bottomRight;
    final followerAnchor = isRtl ? Alignment.topLeft : Alignment.topRight;

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
                  onTap: () {
                    _portal.hide();
                    setState(() {});
                  },
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
                    width: 300,
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
                        for (final item in widget.items)
                          _MenuItem(item: item, onTap: () => _select(item)),
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
          height: AppSpacing.controlHeightOf(context),
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
                    Icon(widget.icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
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

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.item, required this.onTap});

  final GfActionMenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: AppTypography.bodySemiBold.copyWith(
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
