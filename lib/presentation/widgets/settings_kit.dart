import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/day_night_transition.dart';
import '../../core/widgets/widgets.dart';

/// Responsive spacing for the settings layout (sidebar + section cards).
class SettingsMetrics {
  const SettingsMetrics({
    required this.navWidth,
    required this.gap,
    required this.fieldGap,
    required this.logoSize,
    required this.cardPadding,
    required this.stackNav,
  });

  final double navWidth;
  final double gap;
  final double fieldGap;
  final double logoSize;
  final double cardPadding;
  final bool stackNav;

  factory SettingsMetrics.of(double width) {
    if (width >= 1400) {
      return const SettingsMetrics(
        navWidth: 300,
        gap: 24,
        fieldGap: 20,
        logoSize: 176,
        cardPadding: 24,
        stackNav: false,
      );
    }
    if (width >= 1100) {
      return const SettingsMetrics(
        navWidth: 260,
        gap: 20,
        fieldGap: 16,
        logoSize: 148,
        cardPadding: 20,
        stackNav: false,
      );
    }
    if (width >= 720) {
      return const SettingsMetrics(
        navWidth: 220,
        gap: 16,
        fieldGap: 12,
        logoSize: 120,
        cardPadding: 16,
        stackNav: false,
      );
    }
    return const SettingsMetrics(
      navWidth: double.infinity,
      gap: 12,
      fieldGap: 12,
      logoSize: 100,
      cardPadding: 14,
      stackNav: true,
    );
  }

  /// Default metrics for cards rendered outside the settings layout.
  static const standard = SettingsMetrics(
    navWidth: 260,
    gap: 20,
    fieldGap: 16,
    logoSize: 148,
    cardPadding: 20,
    stackNav: false,
  );
}

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.actions,
    this.footer,
    this.color,
    this.borderColor,
    this.padding = 20,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final List<Widget>? actions;
  final Widget? footer;
  final Color? color;
  final Color? borderColor;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: color ?? AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.sectionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
          SizedBox(height: padding * 0.7),
          child,
          if (actions != null && actions!.isNotEmpty) ...[
            SizedBox(height: padding * 0.7),
            Row(
              children: [
                const Spacer(),
                Flexible(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: actions!,
                  ),
                ),
              ],
            ),
          ],
          if (footer != null) ...[SizedBox(height: padding * 0.7), footer!],
        ],
      ),
    );
  }
}

/// Two side-by-side columns; stacks below [breakpoint].
class SettingsFormRow extends StatelessWidget {
  const SettingsFormRow({
    super.key,
    required this.left,
    required this.right,
    required this.gap,
    this.breakpoint = 560,
  });

  final Widget left;
  final Widget right;
  final double gap;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, SizedBox(height: gap), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            SizedBox(width: gap),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class SettingsTransferGroup extends StatelessWidget {
  const SettingsTransferGroup({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTypography.label),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

class SettingsTransferAction extends StatelessWidget {
  const SettingsTransferAction({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.buttonLabel,
    required this.onPressed,
    this.danger = false,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
              Icon(icon, size: 18, color: danger ? AppColors.error : AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(hint, style: AppTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          danger
              ? GfDangerButton(label: buttonLabel, onPressed: onPressed, expanded: true, isLoading: busy)
              : GfSecondaryButton(label: buttonLabel, onPressed: onPressed, expanded: true, isLoading: busy),
        ],
      ),
    );
  }
}

/// Icon + caption label + value, used for "last backup"-style status lines.
class SettingsStatusLine extends StatelessWidget {
  const SettingsStatusLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.ok = false,
    this.hint,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              Text(value, style: AppTypography.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (hint != null) Text(hint!, style: AppTypography.caption.copyWith(color: color)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Footer info row (icon + caption) at the bottom of a section card.
class SettingsFooterNote extends StatelessWidget {
  const SettingsFooterNote(this.text, {super.key, this.warning = true});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: warning ? AppColors.warning : AppColors.info),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: AppTypography.caption)),
      ],
    );
  }
}

class SettingsNavEntry<T> {
  const SettingsNavEntry(this.section, this.icon, this.label);

  final T section;
  final IconData icon;
  final String label;
}

class SettingsNav<T> extends StatelessWidget {
  const SettingsNav({
    super.key,
    required this.title,
    required this.items,
    required this.selected,
    required this.query,
    required this.onSelected,
  });

  final String title;
  final List<SettingsNavEntry<T>> items;
  final T selected;
  final String query;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Text(title, style: AppTypography.sectionTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: GfNoScrollbarGutter(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                children: [
                  for (final item in items)
                    SettingsNavTile(
                      icon: item.icon,
                      label: item.label,
                      selected: selected == item.section,
                      dimmed: query.isNotEmpty && !item.label.toLowerCase().contains(query.toLowerCase()),
                      onTap: () => onSelected(item.section),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsNavTile extends StatelessWidget {
  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dimmed = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.primarySoft : Colors.transparent,
        borderRadius: AppRadius.navItem,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.navItem,
          hoverColor: AppColors.hover,
          child: Opacity(
            opacity: dimmed ? 0.45 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: selected ? AppColors.primary : AppColors.textPrimary,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme choice with a miniature preview of the app in that theme.
class SettingsThemeOptionTile extends StatelessWidget {
  const SettingsThemeOptionTile({
    super.key,
    required this.variant,
    required this.selected,
    required this.onSelected,
  });

  final AppThemeVariant variant;
  final bool selected;
  final VoidCallback onSelected;

  (String, String, IconData) get _info => switch (variant) {
        AppThemeVariant.light => ('حالت روشن', 'ظاهر روشن و پرکنتراست برای محیط‌های پرنور.', Icons.light_mode_outlined),
        AppThemeVariant.dark => ('حالت تاریک', 'رنگ‌های تیره برای کار طولانی و کاهش خستگی چشم.', Icons.dark_mode_outlined),
        AppThemeVariant.hadid => ('حالت تاریک حدید', 'پوسته تاریک با رنگ‌های برند حدید.', Icons.nights_stay_outlined),
      };

  void _select(BuildContext context) {
    if (selected) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      DayNightThemeTransition.revealFrom(
        context,
        globalCenter: box.localToGlobal(box.size.center(Offset.zero)),
      );
    }
    onSelected();
  }

  @override
  Widget build(BuildContext context) {
    final (label, hint, icon) = _info;
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.input,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _select(context),
        hoverColor: AppColors.hover,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ThemePreview(variant: variant),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodySemiBold.copyWith(
                        color: selected ? AppColors.primary : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
                      child: Text(
                        'فعال',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(hint, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed-color mock of the app shell (sidebar, header, cards) for a theme.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.variant});

  final AppThemeVariant variant;

  @override
  Widget build(BuildContext context) {
    final light = variant.isLight;
    final d = variant.darkPalette;
    final bg = light ? AppColors.lightBackground : d.background;
    final sidebar = light ? AppColors.lightSidebar : d.sidebar;
    final card = light ? AppColors.lightCard : d.card;
    final border = light ? AppColors.lightBorder : d.border;
    final primary = light ? AppColors.lightPrimary : d.primary;
    final text = light ? AppColors.lightTextMuted : d.textMuted;
    final hadid = variant == AppThemeVariant.hadid;

    Widget bar(double widthFactor, Color color, {double height = 5}) => FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: AppRadius.pill),
          ),
        );

    Widget miniCard({required bool accent}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                bar(0.55, text.withValues(alpha: 0.6), height: 4),
                bar(accent ? 0.8 : 0.4, accent ? primary : text.withValues(alpha: 0.35), height: 6),
              ],
            ),
          ),
        );

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hadid ? null : bg,
          gradient: hadid
              ? const LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [Color(0xFF0B2A3F), Color(0xFF061826)],
                )
              : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 34,
              color: sidebar,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              child: Column(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: hadid ? null : primary,
                      gradient: hadid
                          ? const LinearGradient(colors: [Color(0xFF8EF0C4), Color(0xFF27D3DD)])
                          : null,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < 3; i++) ...[
                    bar(1, i == 0 ? primary.withValues(alpha: 0.6) : text.withValues(alpha: 0.35), height: 4),
                    const SizedBox(height: 5),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    bar(0.45, text.withValues(alpha: 0.7), height: 6),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          miniCard(accent: true),
                          const SizedBox(width: 6),
                          miniCard(accent: false),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [miniCard(accent: false)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
