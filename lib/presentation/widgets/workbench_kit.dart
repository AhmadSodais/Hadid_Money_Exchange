import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import 'settings_kit.dart';

/// Desk layout for data-entry screens: numbered form steps on the start side
/// and a live summary panel on the end side. Below [breakpoint] the panel
/// stacks under the form.
class WorkbenchLayout extends StatelessWidget {
  const WorkbenchLayout({
    super.key,
    required this.main,
    required this.side,
    this.sideWidth = 380,
    this.compactSideWidth = 330,
    this.breakpoint = 900,
  });

  final List<Widget> Function(SettingsMetrics metrics) main;
  final List<Widget> Function(SettingsMetrics metrics) side;
  final double sideWidth;

  /// Panel width used while the screen is narrower than 1280.
  final double compactSideWidth;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = SettingsMetrics.of(constraints.maxWidth);
        List<Widget> spaced(List<Widget> items) => [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(height: m.gap),
                items[i],
              ],
            ];
        if (constraints.maxWidth < breakpoint) {
          return ListView(children: spaced([...main(m), ...side(m)]));
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ListView(children: spaced(main(m)))),
            SizedBox(width: m.gap),
            SizedBox(
              width: constraints.maxWidth < 1280 ? compactSideWidth : sideWidth,
              child: ListView(children: spaced(side(m))),
            ),
          ],
        );
      },
    );
  }
}

class WorkbenchModeOption<T> {
  const WorkbenchModeOption(this.value, this.title, this.description, this.icon, {this.color});

  final T value;
  final String title;
  final String description;
  final IconData icon;
  final Color? color;
}

/// Large selectable cards for the screen's main mode (e.g. buy / sell).
class WorkbenchModeSelector<T> extends StatelessWidget {
  const WorkbenchModeSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.gap = 12,
  });

  final List<WorkbenchModeOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = [
          for (final o in options)
            _ModeTile(option: o, selected: o.value == value, onTap: () => onChanged(o.value)),
        ];
        if (constraints.maxWidth < 180.0 * options.length) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                tiles[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ModeTile<T> extends StatelessWidget {
  const _ModeTile({required this.option, required this.selected, required this.onTap});

  final WorkbenchModeOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = option.color ?? AppColors.primary;
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.hover,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: selected ? 0.18 : 0.10),
                  borderRadius: AppRadius.input,
                ),
                child: Icon(option.icon, size: 22, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.title,
                            style: AppTypography.bodySemiBold.copyWith(
                              color: selected ? AppColors.primary : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selected) Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.description,
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Customer / drawer / date fields: one row when wide, customer on its own
/// row above drawer and date when medium, fully stacked when narrow.
class WorkbenchPartyFields extends StatelessWidget {
  const WorkbenchPartyFields({
    super.key,
    this.customer,
    required this.drawer,
    required this.date,
    this.gap = 16,
  });

  final Widget? customer;
  final Widget drawer;
  final Widget date;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        Widget pair() => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: drawer),
                SizedBox(width: gap),
                Expanded(child: date),
              ],
            );
        if (w < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (customer != null) ...[customer!, SizedBox(height: gap)],
              drawer,
              SizedBox(height: gap),
              date,
            ],
          );
        }
        if (customer == null) return pair();
        if (w < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [customer!, SizedBox(height: gap), pair()],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: customer!),
            SizedBox(width: gap),
            Expanded(flex: 2, child: drawer),
            SizedBox(width: gap),
            Expanded(flex: 2, child: date),
          ],
        );
      },
    );
  }
}

/// Section card whose header carries a step number, so the form reads as an
/// ordered sequence.
class WorkbenchSection extends StatelessWidget {
  const WorkbenchSection({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = 20,
  });

  final int step;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              WorkbenchStepBadge(step: step),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          SizedBox(height: padding * 0.8),
          child,
        ],
      ),
    );
  }
}

class WorkbenchStepBadge extends StatelessWidget {
  const WorkbenchStepBadge({super.key, required this.step, this.done = false});

  final int step;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.primary;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? color : color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 16, color: AppColors.onPrimary)
          : Text('$step', style: AppTypography.bodySemiBold.copyWith(color: color, height: 1)),
    );
  }
}

/// End-side panel: tinted header, body, and a footer for the main action.
///
/// With [height] the panel keeps that size whatever its content: the body
/// scrolls when it overflows and [centerChildren] centers a short body (e.g.
/// a placeholder hint).
class WorkbenchSummaryPanel extends StatelessWidget {
  const WorkbenchSummaryPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
    this.accent,
    this.footer,
    this.height,
    this.centerChildren = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? accent;
  final List<Widget> children;
  final Widget? footer;
  final double? height;
  final bool centerChildren;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.primary;
    const bodyPadding = 16.0;
    final items = [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: 14),
        children[i],
      ],
    ];
    final Widget body = height == null
        ? Padding(
            padding: const EdgeInsets.all(bodyPadding),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items),
          )
        : Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(bodyPadding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - bodyPadding * 2).clamp(0, double.infinity),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: centerChildren ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: items,
                  ),
                ),
              ),
            ),
          );
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: AppRadius.input),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body,
          if (footer != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
              child: footer,
            ),
        ],
      ),
    );
  }
}

/// One money movement in a summary: incoming (green) or outgoing (red).
class WorkbenchFlowLine extends StatelessWidget {
  const WorkbenchFlowLine({
    super.key,
    required this.incoming,
    required this.label,
    required this.amount,
    this.hint,
    this.amountColor,
  });

  final bool incoming;
  final String label;
  final String amount;
  final String? hint;
  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    final color = incoming ? AppColors.success : AppColors.error;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: incoming ? AppColors.successBg : AppColors.errorBg, shape: BoxShape.circle),
          child: Icon(incoming ? Icons.south_west_rounded : Icons.north_east_rounded, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(
                amount,
                textDirection: TextDirection.ltr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.kpiValue.copyWith(fontSize: 20, color: amountColor ?? AppColors.textPrimary),
              ),
              if (hint != null)
                Text(hint!, style: AppTypography.caption.copyWith(color: AppColors.textMuted), maxLines: 2),
            ],
          ),
        ),
      ],
    );
  }
}

/// Label / value line inside a summary panel.
class WorkbenchValueRow extends StatelessWidget {
  const WorkbenchValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.ltr = false,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool ltr;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            textDirection: ltr ? TextDirection.ltr : null,
            style: (bold ? AppTypography.bodySemiBold : AppTypography.bodyMedium).copyWith(color: valueColor),
          ),
        ),
      ],
    );
  }
}

/// Before → after balance, used to preview the effect of a transaction.
class WorkbenchBalanceChange extends StatelessWidget {
  const WorkbenchBalanceChange({
    super.key,
    required this.label,
    required this.before,
    required this.after,
    this.afterColor,
    this.icon,
  });

  final String label;
  final String before;
  final String after;
  final Color? afterColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: AppRadius.input,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  before,
                  style: AppTypography.body.copyWith(color: AppColors.textMuted),
                  maxLines: 2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(rtl ? Icons.west_rounded : Icons.east_rounded, size: 16, color: AppColors.textMuted),
              ),
              Expanded(
                child: Text(
                  after,
                  textAlign: TextAlign.end,
                  style: AppTypography.bodySemiBold.copyWith(color: afterColor ?? AppColors.textPrimary),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Muted placeholder shown in a summary panel before the form is complete.
class WorkbenchHint extends StatelessWidget {
  const WorkbenchHint({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
