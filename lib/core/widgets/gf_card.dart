import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'gf_scroll_behavior.dart';

/// Glass-styled card surface with optional title and trailing actions.
class GfCard extends StatelessWidget {
  const GfCard({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.showBorder = true,
    this.showShadow = false,
    this.color,
  });

  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool showBorder;
  final bool showShadow;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || (actions != null && actions!.isNotEmpty);

    Widget content = child;
    // A titled card scrolls its content; the padding goes inside the scroll
    // view so content scrolls to the card edge and the scrollbar sits in it.
    final EdgeInsetsGeometry outerPadding = hasHeader
        ? EdgeInsets.zero
        : padding;
    if (hasHeader) {
      content = ScrollConfiguration(
        behavior: const GfScrollBehavior(reserveGutter: false),
        child: SingleChildScrollView(
          padding: padding,
          child: ScrollConfiguration(
            behavior: const GfScrollBehavior(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (title != null)
                      Expanded(
                        child: Text(
                          title!,
                          style: AppTypography.localize(
                            AppTypography.sectionTitle,
                            context: context,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    if (actions != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      ...actions!,
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                child,
              ],
            ),
          ),
        ),
      );
    }

    final useSoftShadow = showShadow || AppColors.isLight;
    final decorated = Container(
      margin: margin,
      padding: outerPadding,
      clipBehavior: hasHeader ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: AppRadius.card,
        border: showBorder ? Border.all(color: AppColors.border) : null,
        boxShadow: useSoftShadow ? AppShadows.card : null,
      ),
      child: content,
    );

    if (onTap == null) return decorated;

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: color ?? AppColors.card,
        borderRadius: AppRadius.card,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          hoverColor: AppColors.hover,
          child: Container(
            padding: outerPadding,
            clipBehavior: hasHeader ? Clip.antiAlias : Clip.none,
            decoration: BoxDecoration(
              borderRadius: AppRadius.card,
              border: showBorder ? Border.all(color: AppColors.border) : null,
              boxShadow: showShadow ? AppShadows.card : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
