// ignore_for_file: dead_code, unnecessary_null_comparison

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/gf_breakpoints.dart';
import '../../core/utils/gf_scale.dart';
import '../../core/widgets/gf_fit_text.dart';
import '../../core/widgets/gf_responsive.dart';
import '../../core/widgets/gf_scroll_behavior.dart';
import '../../core/widgets/gf_search_field.dart';
import '../providers/app_settings_provider.dart';
import '../session/app_session.dart';
import 'glassflow_sidebar.dart';
import 'motion_widgets.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Keeps key events inside the shell so Tab reaches the page-cycle shortcut
  /// even when nothing else is focused (e.g. right after a page change).
  final FocusNode _shellFocus = FocusNode(
    debugLabel: 'AppShell',
    skipTraversal: true,
  );

  late final _CycleSidebarPageAction _cycleAction = _CycleSidebarPageAction(
    canCycle: _canCyclePages,
    onCycle: _cyclePage,
  );

  @override
  void dispose() {
    _shellFocus.dispose();
    super.dispose();
  }

  /// False while a dialog, menu or dropdown is open so Tab moves between its
  /// fields instead of switching pages.
  bool _canCyclePages() {
    if (!ModalRoute.isCurrentOf(context)!) return false;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null && ModalRoute.of(focusContext) is PopupRoute) {
      return false;
    }
    // Inside a form, Tab moves between fields (keyboard data entry).
    if (focusContext?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return false;
    }
    return true;
  }

  void _cyclePage(bool forward) {
    final items = visibleSidebarItems(context.read<AppSession>());
    if (items.isEmpty) return;
    final location = GoRouterState.of(context).uri.path;
    final current = items.indexWhere(
      (item) => isSidebarRouteSelected(location, item.route),
    );
    final next = current == -1
        ? (forward ? 0 : items.length - 1)
        : (current + (forward ? 1 : -1) + items.length) % items.length;
    _scaffoldKey.currentState?.closeDrawer();
    context.go(items[next].route);
    _shellFocus.requestFocus();
  }

  bool _useDrawer = false;
  bool _forceCollapsed = false;

  /// `~` key (matched physically so it works on any keyboard layout) toggles
  /// the sidebar, unless the user is typing in a text field.
  KeyEventResult _handleShellKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.physicalKey != PhysicalKeyboardKey.backquote) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final isTyping =
        focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (isTyping || !_canCyclePages()) return KeyEventResult.ignored;

    if (_useDrawer) {
      final scaffold = _scaffoldKey.currentState;
      if (scaffold == null) return KeyEventResult.ignored;
      scaffold.isDrawerOpen ? scaffold.closeDrawer() : scaffold.openDrawer();
    } else if (!_forceCollapsed) {
      context.read<AppSettingsProvider>().toggleSidebar();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsProvider>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          // Global search focus is handled per-page; this keeps shortcut reserved.
        },
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
          final loc = GoRouterState.of(context).uri.path;
          if (loc == AppRoutes.exchange) return;
          context.go(AppRoutes.exchange);
        },
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.tab, includeRepeats: false):
              _CycleSidebarPageIntent(forward: true),
          SingleActivator(
            LogicalKeyboardKey.tab,
            shift: true,
            includeRepeats: false,
          ): _CycleSidebarPageIntent(
            forward: false,
          ),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _CycleSidebarPageIntent: _cycleAction,
          },
          child: Focus(
            focusNode: _shellFocus,
            autofocus: true,
            onKeyEvent: _handleShellKey,
            child: _buildLayout(settings),
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(AppSettingsProvider settings) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final windowWidth = constraints.maxWidth;
        final uiScale = GfScale.of(context);
        final useDrawer = windowWidth < GfBreakpoints.sidebarAsDrawer;
        final forceCollapsed =
            !useDrawer && windowWidth < GfBreakpoints.sidebarAutoCollapse;
        _useDrawer = useDrawer;
        _forceCollapsed = forceCollapsed;
        final contentWidth = useDrawer
            ? windowWidth
            : windowWidth -
                  AppSpacing.sidebarInset -
                  (forceCollapsed || settings.sidebarCollapsed
                      ? AppSpacing.sidebarCollapsed
                      : AppSpacing.sidebarExpanded);
        final layoutSize = GfBreakpoints.ofWidth(contentWidth);
        final metrics =
            GfBreakpoints.metricsFor(layoutSize, uiScale: uiScale);

        return GfLayoutScope(
          size: layoutSize,
          metrics: metrics,
          contentWidth: contentWidth,
          openDrawer: useDrawer
              ? () => _scaffoldKey.currentState?.openDrawer()
              : null,
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            drawer: useDrawer
                ? Drawer(
                    width: AppSpacing.sidebarExpanded + 8,
                    backgroundColor: AppColors.sidebar,
                    child: FocusTraversalGroup(
                      child: GlassFlowSidebar(
                        settings: settings,
                        forceExpanded: true,
                        inDrawer: true,
                      ),
                    ),
                  )
                : null,
            body: DecoratedBox(
              decoration: BoxDecoration(color: AppColors.background),
              child: Row(
                children: [
                  if (!useDrawer)
                    FocusTraversalGroup(
                      child: GlassFlowSidebar(
                        settings: settings,
                        forceCollapsed: forceCollapsed,
                      ),
                    ),
                  Expanded(child: FocusTraversalGroup(child: widget.child)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CycleSidebarPageIntent extends Intent {
  const _CycleSidebarPageIntent({required this.forward});

  final bool forward;
}

class _CycleSidebarPageAction extends Action<_CycleSidebarPageIntent> {
  _CycleSidebarPageAction({required this.canCycle, required this.onCycle});

  final bool Function() canCycle;
  final void Function(bool forward) onCycle;

  @override
  bool isEnabled(_CycleSidebarPageIntent intent) => canCycle();

  @override
  Object? invoke(_CycleSidebarPageIntent intent) {
    onCycle(intent.forward);
    return null;
  }
}

class ShellTopBar extends StatelessWidget {
  const ShellTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.searchHint,
    this.onSearch,
    this.searchController,
    this.actions = const [],
    this.leading,
    this.headerExtra,
    this.searchFocusNode,
  });

  final String title;
  final String? subtitle;
  final String? searchHint;
  final ValueChanged<String>? onSearch;
  final TextEditingController? searchController;
  final List<Widget> actions;
  final Widget? leading;

  /// Optional content under the title/search row (e.g. category chips).
  final Widget? headerExtra;

  /// Optional focus node for the header search field.
  final FocusNode? searchFocusNode;

  /// Cap search width so it does not stretch across the whole header.
  static double _searchWidthFor(double barWidth) {
    if (barWidth < 520) return barWidth;
    if (barWidth < 720) return 280;
    if (barWidth < 1000) return 340;
    if (barWidth < 1280) return 400;
    return 460;
  }

  /// Below this content width, header actions hide instead of wrapping under
  /// the title when there is no search field (e.g. dashboard chrome toggles).
  static const double _actionsHideBelow = 360;

  @override
  Widget build(BuildContext context) {
    final metrics = GfBreakpoints.metricsOf(context);
    final padTop = metrics.pageVerticalPadding;
    final scope = GfLayoutScope.maybeOf(context);
    final showMenu = scope?.openDrawer != null;
    final hasSearch = onSearch != null || searchController != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        final titleBlock =
            leading ??
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GfFitText(
                  title,
                  style: AppTypography.localize(
                    AppTypography.pageTitle,
                    context: context,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  GfFitText(
                    subtitle!,
                    style: AppTypography.localize(
                      AppTypography.subtitle,
                      context: context,
                    ),
                    maxLines: 2,
                  ),
                ],
              ],
            );

        final searchField = hasSearch
            ? GfSearchField(
                controller: searchController,
                focusNode: searchFocusNode,
                hintText: searchHint ?? 'common.searchAnything'.tr(),
                onChanged: onSearch,
                showShortcutHint: width >= 900,
              )
            : null;

        // Without a search field, keep actions on the title row. Only hide
        // them when the bar is too narrow — never push them onto a second
        // row while horizontal space is still available.
        final showActions = actions.isNotEmpty &&
            (searchField != null || width >= _actionsHideBelow);
        final actionsBar = !showActions
            ? null
            : GfActionBar(alignment: WrapAlignment.end, children: actions);

        Widget menuButton() => IconButton(
          tooltip: 'Menu',
          onPressed: scope!.openDrawer,
          icon: const Icon(Icons.menu_rounded),
          color: AppColors.textPrimary,
        );

        // One row when there is no search (title ellipsizes; actions stay).
        // With search, require width so the field + actions can share a row.
        final singleRow = searchField == null ||
            (width >= 1100 &&
                (actionsBar == null || actions.length <= 2));

        Widget withExtra({
          required double bottom,
          required Widget toolbar,
        }) {
          if (headerExtra == null) {
            return Padding(
              padding: PageScaffold.pageHorizontalInsets(
                context,
                top: padTop,
                bottom: bottom,
              ),
              child: toolbar,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: PageScaffold.pageHorizontalInsets(
                  context,
                  top: padTop,
                  bottom: AppSpacing.sm,
                ),
                child: toolbar,
              ),
              Padding(
                padding: PageScaffold.pageHorizontalInsets(
                  context,
                  bottom: AppSpacing.md,
                ),
                child: headerExtra,
              ),
            ],
          );
        }

        if (singleRow) {
          return withExtra(
            bottom: AppSpacing.md,
            toolbar: Row(
              children: [
                if (showMenu) ...[menuButton(), const SizedBox(width: 4)],
                Expanded(child: titleBlock),
                if (searchField != null) ...[
                  const SizedBox(width: 16),
                  SizedBox(width: _searchWidthFor(width), child: searchField),
                ],
                if (actionsBar != null) ...[
                  const SizedBox(width: 12),
                  actionsBar,
                ],
              ],
            ),
          );
        }

        // Default responsive layout:
        // 1) title
        // 2) search (capped) + buttons on the same row
        // Only stack search above buttons when the bar is very narrow.
        final toolbarTooNarrow =
            width < 560 && searchField != null && actionsBar != null;

        return withExtra(
          bottom: metrics.gridGap * 0.55,
          toolbar: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showMenu) ...[menuButton(), const SizedBox(width: 4)],
                  Expanded(child: titleBlock),
                ],
              ),
              if (searchField != null || actionsBar != null) ...[
                SizedBox(height: metrics.gridGap * 0.7),
                if (toolbarTooNarrow) ...[
                  searchField,
                  if (actionsBar != null) ...[
                    SizedBox(height: metrics.gridGap * 0.6),
                    actionsBar,
                  ],
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (searchField != null)
                        SizedBox(
                          width: _searchWidthFor(width),
                          child: searchField,
                        ),
                      if (searchField != null && actionsBar != null)
                        const SizedBox(width: 12),
                      if (actionsBar != null)
                        Expanded(
                          child: GfActionBar(
                            alignment: WrapAlignment.end,
                            children: actions,
                          ),
                        )
                      else
                        const Spacer(),
                    ],
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.searchHint,
    this.onSearch,
    this.searchController,
    this.actions = const [],
    this.floatingOverlay,
    this.leading,
    this.headerExtra,
    this.searchFocusNode,
    this.padBody = true,
  });

  /// Horizontal page insets. With a docked sidebar, the outer edge (away from
  /// the rail) matches [AppSpacing.sidebarInset] so it aligns with the
  /// sidebar's gap from the window edge; the inner edge keeps [pagePadding].
  static EdgeInsetsGeometry pageHorizontalInsets(
    BuildContext context, {
    double top = 0,
    double bottom = 0,
  }) {
    final metrics = GfBreakpoints.metricsOf(context);
    final pad = metrics.pagePadding;
    final scope = GfLayoutScope.maybeOf(context);
    final dockedSidebar = scope != null && scope.openDrawer == null;
    if (dockedSidebar) {
      return EdgeInsetsDirectional.only(
        start: pad,
        end: AppSpacing.sidebarInset,
        top: top,
        bottom: bottom,
      );
    }
    return EdgeInsets.fromLTRB(pad, top, pad, bottom);
  }

  /// Page body padding. A page that scrolls its whole body should set
  /// [padBody] to `false` and pass this to its scroll view instead, so content
  /// scrolls to the page edges and the scrollbar sits in the margin.
  static EdgeInsetsGeometry pageBodyPadding(BuildContext context) {
    final metrics = GfBreakpoints.metricsOf(context);
    return pageHorizontalInsets(
      context,
      bottom: metrics.pageVerticalPadding,
    );
  }

  final String title;
  final String? subtitle;
  final String? searchHint;
  final ValueChanged<String>? onSearch;
  final TextEditingController? searchController;
  final List<Widget> actions;
  final Widget body;
  final Widget? floatingOverlay;
  final Widget? leading;

  /// Optional strip under the top bar (e.g. category chips above page content).
  final Widget? headerExtra;

  /// Optional focus node for the header search field.
  final FocusNode? searchFocusNode;

  /// Wraps [body] in [pageBodyPadding]; see there.
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    // Re-key entrance motion whenever the route changes.
    final routeKey = GoRouterState.of(context).uri.toString();

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MotionEntrance.stagger(
              key: ValueKey('page-top-$routeKey'),
              index: 0,
              fromY: -24,
              child: ShellTopBar(
                title: title,
                subtitle: subtitle,
                searchHint: searchHint,
                onSearch: onSearch,
                searchController: searchController,
                searchFocusNode: searchFocusNode,
                actions: actions,
                leading: leading,
                headerExtra: headerExtra,
              ),
            ),
            Expanded(
              child: MotionEntrance.stagger(
                key: ValueKey('page-body-$routeKey'),
                index: 1,
                fromY: -32,
                child: padBody
                    ? Padding(padding: pageBodyPadding(context), child: body)
                    : GfNoScrollbarGutter(child: body),
              ),
            ),
          ],
        ),
        if (floatingOverlay != null) floatingOverlay!,
      ],
    );
  }
}
