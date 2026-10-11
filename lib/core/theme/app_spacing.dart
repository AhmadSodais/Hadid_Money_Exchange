/// GlassFlow spacing tokens.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  static const double pagePadding = 24;
  static const double sectionGap = 20;
  static const double cardGap = 16;

  /// Default height for text fields, dropdowns, search, and primary buttons.
  /// Keep dialog and page form controls on this single value.
  static const double controlHeight = 40;
  static const double tableRowHeight = 56;

  static const double sidebarExpanded = 260;
  static const double sidebarCollapsed = 76;

  /// Gap between the docked sidebar and the window edges / page content.
  static const double sidebarInset = 10;

  /// Soft minimum for desktop window chrome; UI still adapts below this.
  static const double minWindowWidth = 900;
  static const double minWindowHeight = 640;

  static const double dropdownMaxHeight = 280;
  static const double drawerWidth = 420;
}
