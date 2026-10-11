import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_assets.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_routes.dart';
import '../../core/keyboard/gf_keyboard.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_durations.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/gf_scroll_behavior.dart';
import '../../core/widgets/gf_toast.dart';
import '../../domain/security/permissions.dart';
import '../providers/app_lock_provider.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';

class SidebarItem {
  const SidebarItem({
    required this.label,
    required this.route,
    required this.icon,
    this.filledIcon,
    this.badge,
    this.permission,
  });

  /// Persian label (the app is Persian-only).
  final String label;
  final String route;
  final String icon;
  final String? filledIcon;
  final int? badge;
  final String? permission;
}

const kSidebarItems = <SidebarItem>[
  SidebarItem(
    label: 'داشبورد',
    route: AppRoutes.dashboard,
    icon: AppAssets.home,
    filledIcon: AppAssets.home_filled,
  ),
  SidebarItem(
    label: 'خرید و فروش ارز',
    route: AppRoutes.exchange,
    icon: AppAssets.currencies,
    filledIcon: AppAssets.currenciesFilled,
    permission: Permissions.transactionsPost,
  ),
  SidebarItem(
    label: 'رسید و برد',
    route: AppRoutes.cash,
    icon: AppAssets.sales,
    filledIcon: AppAssets.salseFilled,
    permission: Permissions.transactionsPost,
  ),
  SidebarItem(
    label: 'مشتریان',
    route: AppRoutes.customers,
    icon: AppAssets.users,
    filledIcon: AppAssets.usersFilled,
  ),
  SidebarItem(
    label: 'روزنامچه معاملات',
    route: AppRoutes.journal,
    icon: AppAssets.invoice,
    filledIcon: AppAssets.invoiceFilled,
    permission: Permissions.reportsView,
  ),
  SidebarItem(
    label: 'بیلانس روزانه',
    route: AppRoutes.reconciliation,
    icon: AppAssets.inventory,
    filledIcon: AppAssets.inventoryFilled,
    permission: Permissions.reconciliationPerform,
  ),
  SidebarItem(
    label: 'گزارش‌ها',
    route: AppRoutes.reports,
    icon: AppAssets.reports,
    filledIcon: AppAssets.reportsFilled,
    permission: Permissions.reportsView,
  ),
  SidebarItem(
    label: 'نرخ ارز',
    route: AppRoutes.rates,
    icon: AppAssets.analytics,
    filledIcon: AppAssets.analyticsFilled,
  ),
  SidebarItem(
    label: 'تنظیمات',
    route: AppRoutes.settings,
    icon: AppAssets.setting,
    filledIcon: AppAssets.settingFilled,
  ),
];

/// Sidebar entries the current user can see, in display order.
List<SidebarItem> visibleSidebarItems(AppSession session) {
  return kSidebarItems.where((item) {
    final perm = item.permission;
    return perm == null || session.can(perm);
  }).toList();
}

bool isSidebarRouteSelected(String location, String route) {
  if (route == AppRoutes.dashboard) {
    return location == AppRoutes.dashboard || location.isEmpty;
  }
  return location == route || location.startsWith('$route/');
}

/// Width at which labels/profile text become safe to show during animation.
const double _kSidebarLabelThreshold = 140;

class GlassFlowSidebar extends StatelessWidget {
  const GlassFlowSidebar({
    super.key,
    required this.settings,
    this.forceCollapsed = false,
    this.forceExpanded = false,
    this.inDrawer = false,
  });

  final AppSettingsProvider settings;

  /// When true, rail is collapsed regardless of user preference (narrow window).
  final bool forceCollapsed;

  /// When true, rail is expanded regardless of user preference (drawer mode).
  final bool forceExpanded;

  /// True when rendered inside a [Drawer].
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final collapsed = forceExpanded
        ? false
        : (forceCollapsed || settings.sidebarCollapsed);
    final duration = settings.anim(AppDurations.sidebar);
    final location = GoRouterState.of(context).uri.path;
    final height = MediaQuery.of(context).size.height;
    final visibleItems = visibleSidebarItems(context.watch<AppSession>());
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      width: inDrawer
          ? double.infinity
          : (collapsed
                ? AppSpacing.sidebarCollapsed
                : AppSpacing.sidebarExpanded),
      margin: inDrawer
          ? null
          : const EdgeInsetsDirectional.only(
              start: AppSpacing.sidebarInset,
              end: 0,
              top: AppSpacing.sidebarInset,
              bottom: AppSpacing.sidebarInset,
            ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.sidebar,
        borderRadius: inDrawer ? null : BorderRadius.circular(20),
        border: inDrawer ? null : Border.all(color: AppColors.border),
        boxShadow: AppColors.isLight && !inDrawer ? AppShadows.card : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Drive label visibility from *actual* animated width, not the
          // boolean flag (which flips immediately and causes mid-animation overflow).
          final showLabels = constraints.maxWidth >= _kSidebarLabelThreshold;

          return Column(
            children: [
              const SizedBox(height: 14),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: showLabels ? 12 : 10),
                child: _BrandHeader(showLabels: showLabels, duration: duration),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GfArrowFocusGroup(
                  includeHorizontal: false,
                  child: GfNoScrollbarGutter(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        for (final item in visibleItems)
                          _NavTile(
                            item: item,
                            showLabels: showLabels,
                            selected: isSidebarRouteSelected(
                              location,
                              item.route,
                            ),
                            duration: duration,
                            onTap: () {
                              Scaffold.maybeOf(context)?.closeDrawer();
                              context.go(item.route);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showLabels ? 14 : 10,
                  vertical: 8,
                ),
                child: _UserSessionTile(
                  showLabels: showLabels,
                  duration: duration,
                ),
              ),
              Visibility(
                visible: height > 700 && !forceCollapsed && !inDrawer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: _SidebarCollapseButton(
                    collapsed: collapsed,
                    onToggle: settings.toggleSidebar,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SidebarCollapseButton extends StatefulWidget {
  const _SidebarCollapseButton({
    required this.collapsed,
    required this.onToggle,
  });

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<_SidebarCollapseButton> createState() => _SidebarCollapseButtonState();
}

class _SidebarCollapseButtonState extends State<_SidebarCollapseButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) {
        if (mounted) setState(() => _focused = value);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onToggle();
            return null;
          },
        ),
      },
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: AppRadius.input,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.input,
            border: Border.all(
              color: _focused ? AppColors.primary : AppColors.border,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Icon(
            widget.collapsed ? Icons.chevron_right : Icons.chevron_left,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.showLabels, required this.duration});

  final bool showLabels;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        showLabels ? 10 : 6,
        showLabels ? 10 : 8,
        showLabels ? 12 : 6,
        showLabels ? 10 : 8,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          begin: Alignment.topLeft, 
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(
              alpha: AppColors.isLight ? 0.10 : 0.18,
            ),
            AppColors.surface.withValues(
              alpha: AppColors.isLight ? 0.65 : 0.35,
            ),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22))
      ),
      child: Row(
        children: [
          if (!showLabels) const Spacer(),
          _AppLogoMark(size: showLabels ? 42 : 36),
          if (showLabels) ...[
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedOpacity(
                opacity: showLabels ? 1 : 0,
                duration: duration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppConstants.appName,
                      style:
                          AppTypography.localize(
                            AppTypography.brand,
                            context: context,
                          ).copyWith(
                            fontSize: 17,
                            letterSpacing: 0.2,
                            height: 1.15,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'صرافی و حسابداری ارز',
                      style:
                          AppTypography.localize(
                            AppTypography.caption,
                            context: context,
                          ).copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            height: 1.2,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

class _AppLogoMark extends StatelessWidget {
  const _AppLogoMark({this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      // decoration: BoxDecoration(
      //   borderRadius: BorderRadius.circular(size * 0.28),
      //   boxShadow: [
      //     BoxShadow(
      //       color: AppColors.primary.withValues(alpha: 0.22),
      //       blurRadius: 10,
      //       offset: const Offset(0, 3),
      //     ),
      //   ],
      // ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          AppAssets.hadidLogo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Container(
            color: AppColors.primary.withValues(alpha: 0.15),
            alignment: Alignment.center,
            child: Icon(
              Icons.hexagon_outlined,
              color: AppColors.primary,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.showLabels,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final SidebarItem item;
  final bool showLabels;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> with TickerProviderStateMixin {
  bool _hover = false;
  bool _focused = false;

  static const _tileHeight = 46.0;
  static const _iconSize = 21.0;

  late AnimationController _controller;
  late AnimationController _labelController;
  late Animation<double> _iconScaleAnim;
  late Animation<double> _barScaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _labelSlideAnim;
  late Animation<double> _labelFadeAnim;

  // Add animation for "on tap" press effect
  late AnimationController _tapController;
  late Animation<double> _tapAnim;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.selected ? 1.0 : 0.0,
    );

    _iconScaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));

    _barScaleAnim = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutExpo));

    _fadeAnim = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _labelController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 340),
      value: widget.showLabels ? 1.0 : 0.0,
    );

    _labelSlideAnim =
        Tween<Offset>(begin: const Offset(0.17, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: _labelController, curve: Curves.easeInOut),
        );
    _labelFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _labelController, curve: Curves.easeInOutCubic),
    );

    if (widget.selected) _controller.value = 1.0;
    if (widget.showLabels) _labelController.value = 1.0;

    // Animation for tap/press feedback
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
      reverseDuration: const Duration(milliseconds: 90),
      value: 1.0,
    );
    _tapAnim = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(
        parent: _tapController,
        curve: Curves.easeInCubic,
        reverseCurve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _NavTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selection state change animation
    if (widget.selected && !oldWidget.selected) {
      _controller.forward();
    } else if (!widget.selected && oldWidget.selected) {
      _controller.reverse();
    }
    // Label visibility animation
    if (widget.showLabels && !oldWidget.showLabels) {
      _labelController.forward();
    } else if (!widget.showLabels && oldWidget.showLabels) {
      _labelController.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _labelController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _tapController.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final highlighted = selected || _hover || _focused;
    final showLabels = widget.showLabels;
    // English = LTR (left); fa / ps = RTL (right).
    final isLtr = context.locale.languageCode == 'en';
    final textDir = isLtr ? ui.TextDirection.ltr : ui.TextDirection.rtl;
    final labelAlign = AlignmentDirectional.centerStart;
    final textAlign = TextAlign.start;

    final backgroundColor = selected
        ? AppColors.primarySoft
        : (_hover || _focused)
        ? AppColors.hover
        : Colors.transparent;

    Widget buildSmoothIcon() {
      return ScaleTransition(
        scale: _iconScaleAnim,
        child: SvgPicture.asset(
          selected
              ? widget.item.filledIcon ?? widget.item.icon
              : widget.item.icon,
          width: _iconSize,
          height: _iconSize,
          colorFilter: ColorFilter.mode(
            selected ? AppColors.primary : AppColors.textSecondary,
            BlendMode.srcIn,
          ),
        ),
      );
    }

    final badgeCount = widget.item.badge;
    final showBadge = badgeCount != null && badgeCount > 0;
    final badgeText = badgeCount == null
        ? ''
        : (badgeCount > 9 ? '9+' : '$badgeCount');

    Widget badgeChip({bool compact = false}) {
      // Alerts: number only — no background or border.
      return Text(
        badgeText,
        style: AppTypography.caption.copyWith(
          color: AppColors.error,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10 : 12,
          height: 1.1,
        ),
      );
    }

    final tile = FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) {
        if (mounted) setState(() => _focused = value);
      },
      onShowHoverHighlight: (value) {
        if (mounted) setState(() => _hover = value);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _handleTap();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onTapDown: (_) {
            _tapController.forward();
          },
          onTapCancel: () {
            _tapController.reverse();
          },
          child: ScaleTransition(
            scale: _tapAnim,
            child: AnimatedContainer(
              duration: widget.duration,
              curve: Curves.easeInOutCubicEmphasized,
              height: _tileHeight,
              margin: const EdgeInsets.symmetric(vertical: 3),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: AppRadius.navItem,
                border: _focused
                    ? Border.all(color: AppColors.primary, width: 2)
                    : Border.all(color: Colors.transparent, width: 2),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.28),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                    : selected && !AppColors.isLight
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Directionality(
                textDirection: textDir,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Animated start bar with smooth scale and fade.
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Positioned(
                          left: isLtr ? (selected ? 0 : -8) : null,
                          right: isLtr ? null : (selected ? 0 : -8),
                          top: selected
                              ? 9 + (1.0 - _barScaleAnim.value) * 16
                              : 18,
                          bottom: selected
                              ? 9 + (1.0 - _barScaleAnim.value) * 16
                              : 18,
                          child: FadeTransition(
                            opacity: _fadeAnim,
                            child: ScaleTransition(
                              scale: _barScaleAnim,
                              alignment: Alignment.centerLeft,
                              child: Opacity(
                                opacity: selected ? 1 : 0.0,
                                child: Container(
                                  width: AppColors.isLight ? 4 : 3,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(15),
                                    boxShadow: AppColors.isLight
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.65),
                                              blurRadius: 8,
                                            ),
                                          ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: showLabels ? 13 : 0,
                      ),
                      child: Row(
                        textDirection: textDir,
                        mainAxisAlignment: showLabels
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (!showLabels)
                            Expanded(
                              child: Center(
                                child: FadeTransition(
                                  opacity: _fadeAnim,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      buildSmoothIcon(),
                                      if (showBadge)
                                        Positioned(
                                          top: -6,
                                          right: -10,
                                          child: badgeChip(compact: true),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else ...[
                            FadeTransition(
                              opacity: _fadeAnim,
                              child: buildSmoothIcon(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SlideTransition(
                                position: _labelSlideAnim,
                                child: FadeTransition(
                                  opacity: _labelFadeAnim,
                                  child: Align(
                                    alignment: labelAlign,
                                    child: Text(
                                      widget.item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: textAlign,
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.textPrimary,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (showBadge)
                              SlideTransition(
                                position: _labelSlideAnim,
                                child: FadeTransition(
                                  opacity: _labelFadeAnim,
                                  child: Padding(
                                    padding: const EdgeInsetsDirectional.only(
                                      start: 6,
                                    ),
                                    child: badgeChip(),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (!showLabels && highlighted)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.input,
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary.withValues(alpha: 0.45)
                                    : Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return tile;
  }
}

// class _ProfileTile extends StatelessWidget {
//   ...
// }

class _UserSessionTile extends StatelessWidget {
  const _UserSessionTile({required this.showLabels, required this.duration});

  final bool showLabels;
  final Duration duration;

  /// Needs more width than nav labels (avatar + name + lock).
  static const _expandedMinWidth = 200.0;

  /// Manual lock. Without a configured app lock there is nothing to lock
  /// with, so the user is pointed to Settings instead.
  void _logout(BuildContext context) {
    final lock = context.read<AppLockProvider>();
    if (!lock.isEnabled) {
      GfToast.warning(context, 'قفل برنامه فعال نیست؛ آن را از تنظیمات فعال کنید.');
      context.go(AppRoutes.settings);
      return;
    }
    lock.lock();
  }

  @override
  Widget build(BuildContext context) {
    final actor = context.watch<AppSession>().actor;
    final displayName = actor.displayName;
    const roleLine = 'قفل دستی برنامه';

    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded =
            showLabels && constraints.maxWidth >= _expandedMinWidth;

        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 10 : 6,
            vertical: expanded ? 10 : 8,
          ),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: AppRadius.input,
            border: Border.all(color: AppColors.border),
          ),
          child: expanded
              ? Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.input,
                      child: Icon(
                        Icons.person,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: AppTypography.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            roleLine,
                            style: AppTypography.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'قفل برنامه',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => _logout(context),
                    ),
                  ],
                )
              : Center(
                  child: PopupMenuButton<void>(
                    tooltip: displayName,
                    padding: EdgeInsets.zero,
                    offset: const Offset(0, -48),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.input,
                    ),
                    itemBuilder: (ctx) => [
                      PopupMenuItem<void>(
                        enabled: false,
                        height: 40,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              style: AppTypography.bodySemiBold,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              roleLine,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(height: 1),
                      PopupMenuItem<void>(
                        onTap: () => _logout(context),
                        height: 40,
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            const Text('قفل برنامه'),
                          ],
                        ),
                      ),
                    ],
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.input,
                      child: Icon(
                        Icons.person,
                        size: 17,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
