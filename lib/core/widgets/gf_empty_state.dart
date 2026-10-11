import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'gf_button.dart';

/// Empty / no-data placeholder with optional action.
///
/// Adapts to tight height constraints (e.g. during sidebar resize) without overflowing.
class GfEmptyState extends StatelessWidget {
  const GfEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tightH =
            constraints.maxHeight.isFinite && constraints.maxHeight < 120;
        final showIcon = !tightH &&
            (!constraints.maxHeight.isFinite || constraints.maxHeight >= 90);
        final showSubtitle = subtitle != null &&
            (!constraints.maxHeight.isFinite || constraints.maxHeight >= 70);
        final showAction = actionLabel != null &&
            onAction != null &&
            (!constraints.maxHeight.isFinite || constraints.maxHeight >= 140);

        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showIcon) ...[
              Container(
                width: compact ? 48 : 72,
                height: compact ? 48 : 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.hover,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  icon,
                  size: compact ? 22 : 32,
                  color: AppColors.textMuted,
                ),
              ),
              SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tightH
                  ? AppTypography.bodyMedium
                  : AppTypography.sectionTitle,
            ),
            if (showSubtitle) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.subtitle,
              ),
            ],
            if (showAction) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              GfPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
              ),
            ],
          ],
        );

        return Center(
          child: Padding(
            padding: EdgeInsets.all(
              tightH
                  ? AppSpacing.xs
                  : (compact ? AppSpacing.sm : AppSpacing.xxl),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: constraints.maxHeight.isFinite
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: content,
                    )
                  : content,
            ),
          ),
        );
      },
    );
  }
}
