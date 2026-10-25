# Prompt: Hadid Money Exchange — UI design system (widgets, colors, space, issues)

Copy and follow this when redesigning, fixing, or extending the app UI. Focus on **widgets, color tokens, spacing, radius, typography, and known design bugs** — not page-by-page feature sections.

Source of truth in code:
- Colors / themes: `lib/core/theme/app_colors.dart`, `app_theme.dart`
- Space / radius / type / shadow / motion: `app_spacing.dart`, `app_radius.dart`, `app_typography.dart`, `app_shadows.dart`, `app_durations.dart`
- Scale / breakpoints: `lib/core/utils/gf_scale.dart`, `gf_breakpoints.dart`
- Shared widgets: `lib/core/widgets/*` (exported via `widgets.dart`)
- Shell / workbench / dialog helpers: `lib/presentation/widgets/app_shell.dart`, `workbench_kit.dart`, `settings_kit.dart`, `dialog_shared.dart`, `glassflow_sidebar.dart`, `order_detail_dialog_style.dart`

---

```
You are working on Hadid Money Exchange — a Flutter Windows desktop money-exchange app
(RTL Persian-first, GlassFlow design system). Preserve the existing visual language unless
explicitly asked to rebrand. Prefer editing shared Gf* / theme tokens over one-off styles
on individual pages.

═══════════════════════════════════════════════════════════════
1. PRODUCT / LAYOUT CONTEXT (for widget decisions only)
═══════════════════════════════════════════════════════════════
- Desktop-first Windows app; soft minimum window ~900×640.
- RTL UI (fa / Dari). Fonts: Inter (en), YekanBakh (fa), Vazirmatn (ps).
- Shell: docked GlassFlow sidebar + content. Sidebar expanded 260 / collapsed 76,
  inset 10 from window edges. Auto-collapse < 1180; drawer mode < 900.
- Content padding comes from GfLayoutMetrics (desktop 28 / tablet 20 / mobile 14),
  scaled by GfScale; outer edge next to window matches sidebarInset (10).
- Design reference size: 1536×864 logical (1920×1080 @ 125% DPI). GfScale factor
  stays 1.0 at/above ~96% of that; shrinks to min 0.78. Text gets +10% textBoost
  via TextScaler; control heights use layout factor only. Sidebar widths do NOT scale.

═══════════════════════════════════════════════════════════════
2. THEME VARIANTS
═══════════════════════════════════════════════════════════════
AppThemeVariant: light | dark (charcoal + lime) | hadid (navy + cyan/mint).
- light → ThemeMode.light, Violet Dusk palette.
- dark / hadid → ThemeMode.dark; differ only by AppDarkPalette (lime vs hadid).
Always drive UI through AppColors semantic getters (background, primary, card, …)
so light/dark/hadid stay consistent. Do not hardcode Colors.white / Colors.black
except where a surface is intentionally fixed (e.g. About hero, lock screen).

═══════════════════════════════════════════════════════════════
3. COLOR SYSTEM — USE THESE TOKENS
═══════════════════════════════════════════════════════════════

── LIGHT (Violet Dusk) ──
Primary scale:
  primary900 #502D55  |  primary800 #643765  |  primary700 #7A4477
  primary600 #935073 (= lightPrimary)  |  primary500 #A95D82 (= accent / hover base)

Surfaces:
  background      #F8F4E9
  backgroundEnd   #F6E8EF
  sidebar / card / modal / input  #FFF9F2
  surface / soft / tableHeader / uploadBg  #F6E8EF
  rowHover        #F8EEF3

Text:
  textPrimary   #2D1933
  textSecondary #6F6073  (= icon)
  textMuted     #A89CA8
  onPrimary     #FFFFFF

Borders:
  border / inputBorder  #E6D9E1
  secondaryBorder       #DCC9D7
  divider               #EFE5DD
  borderActive          primary600

Semantic:
  success #218739 / bg #DDF3E4
  warning #B76A00 / bg #FFF1D8
  error   #C43D55 / bg #FCE3E7
  info    #643765 / bg #E8E1F4
  dangerZoneBg #FCEBEC / border #F1B8C2
  hover / activeGlow / focusRing  rgba of primary (~15–15%)

Charts (light accents, fixed):
  purple #935073, pink #A95D82, blue #643765, yellow #D99A32, olive #4E9F65

── DARK LIME (default dark) ──
  background #061114 | sidebar #07161A | card #0B171A | modal #111B1E
  input #0B1316 | softSurface #0E1A1E
  primary #C8FF00 | onPrimary #101500
  textPrimary #F4F7F5 | textSecondary #8F9A9C | textMuted #687477
  border 0x1AFFFFFF | divider 0x14FFFFFF
  success #78D64B | warning #F5B700 | error #FF4D3D | info #56B4E9
  hover 0x14FFFFFF | activeGlow 0x33C8FF00 | focusRing 0x66C8FF00
  *Bg semantics in dark = tone @ ~16% alpha (not solid pastel chips)

── DARK HADID (navy + cyan) ──
  background #061826 | sidebar #071C2D | card #0A2336 | modal #0F2C42
  input #081E2F | softSurface #0D283C
  primary #2FD6D8 | onPrimary #04212C
  textPrimary #EAF7F7 | textSecondary #93ADBA | textMuted #68848F
  border 0x1F8EF0C4 | divider 0x148EF0C4
  success #5EE3A6 | warning #F6BE7A | error #FF5D6C | info #5DB8F5
  hover / glow / focus use cyan alphas

── FIXED TRANSACTION-TYPE HUES (same in every theme) ──
Used by TransactionTypeBadge — recognized by color before reading the label:
  receipt #2E9E5B | payment #D64545 | buy #2F7FE0 | sell #E07B1F
  opening* #159A9C | adjustment* #8559D6 | expense #B8860B | reversal #7F8A8C

── ABOUT / BRAND HERO (special, not AppColors) ──
  navy #0B2A3F | navyDeep #06182A | mint #8EF0C4 | cyan #27D3DD | peach #F6C9A0
  These intentionally break the Violet Dusk chrome for brand storytelling.

Shadows (light): card rgba(80,45,85,0.08) blur 20 y+4;
  modal rgba(80,45,85,0.15) blur 50 y+20; focus ring spread 3 primary15%.
Shadows (dark): heavier black blurs; activeGlow uses AppColors.activeGlow.

═══════════════════════════════════════════════════════════════
4. SPACING / SIZE / RADIUS / TYPE
═══════════════════════════════════════════════════════════════

AppSpacing (design px @ reference size):
  xxs 4 | xs 8 | sm 12 | md 16 | lg 20 | xl 24 | xxl 32
  pagePadding 24 | sectionGap 20 | cardGap 16
  controlHeight 40  ← single source for fields, dropdowns, search, Gf* buttons
  tableRowHeight 56
  sidebarExpanded 260 | sidebarCollapsed 76 | sidebarInset 10
  dropdownMaxHeight 280 | drawerWidth 420
Use controlHeightOf(context) / tableRowHeightOf(context) when height must track GfScale.

AppRadius: ALL chrome is 8 (sm=md=lg=xl=8). Exceptions that already exist and
should be treated as known issues (not new norms):
  - GlassFlowSidebar outer docked radius 20; brand/avatar pockets 15 / 10
  - AppRadius.pill = 999 for badges/chips only
  - Unauthorized / lock screens use 12–24 (off-system)

AppTypography tokens (always via AppTypography + localize/fontFamilyOf):
  display 28/w700  | pageTitle 32/w700  | sectionTitle 18/w600
  body 14/w400  | bodyMedium 14/w500  | bodySemiBold 14/w600
  subtitle 13/w400 secondary  | caption 12/w400 muted  | label 13/w500 secondary
  kpiValue 26/w600  ← keep w600 (Persian digit glyphs break at w700+)
  button 14/w600  | brand 18/w700 primary
Line heights: titles ~1.2–1.3, body 1.4, caption/label 1.35.
Money amounts: TextDirection.ltr + FontFeature.tabularFigures().

AppDurations: fast 120 | normal 200 | sidebar 280 | slow 400 |
  themeTransition 700 (reduced 180).

═══════════════════════════════════════════════════════════════
5. WIDGET DESIGN SPECS (build / restyle to match these)
═══════════════════════════════════════════════════════════════

── Buttons (lib/core/widgets/gf_button.dart) ──
Use GfPrimaryButton / GfSecondaryButton / GfDangerButton / GfIconButton.
- Height: AppSpacing.controlHeight (40, scaled); compact = 36.
- Radius 8, elevation 0, horizontal padding 16 (compact 10).
- Primary: fill AppColors.primary, fg onPrimary, hover primaryHover.
- Secondary: transparent + secondaryBorder; light fg = primary900, dark = textPrimary.
- Danger: fill dangerZoneBg, border dangerZoneBorder, fg error.
- Icon button: square controlHeight, optional border, icon 20, hover AppColors.hover.
- Loading: 18px CircularProgressIndicator stroke 2.
DO NOT use raw ElevatedButton/FilledButton for product UI unless matching these tokens.
Note: ThemeData elevated/outlined still set minimumSize height 42 — prefer Gf* so
forms stay aligned at 40.

── Text fields (gf_text_field.dart) ──
Always GfTextField for forms/dialogs.
- Single-line height = controlHeight; filled input surface; radius 8.
- Content padding ~12 horizontal; errors BELOW chrome (not inflating height).
- Focus: borderActive / primary 1.5; error borders use error.
- Labels: AppTypography.label; hints: body + textMuted.
- numberMode / formatters for money/qty; borderless only inside nested steppers.

── Dropdowns / search / Shamsi date ──
GfDropdown, GfSearchField, GfShamsiDateField — same controlHeight and border language
as GfTextField. Dropdown panel: AppShadows.dropdown, max height 280.

── Cards ──
GfCard: AppColors.card, border AppColors.border, radius 8, default padding lg (20).
  Light mode soft card shadow by default; dark usually border-only unless showShadow.
SettingsSectionCard: icon 20 primary + sectionTitle header; padding from SettingsMetrics
  (14–24 by width); actions Wrap spacing 10 / run 8.
GfKpiCard: tone normal|warning|error; padding sm (single) or md (multi-currency);
  icon tile 32/36 with accent @12% fill; kpiValue; optional trend chip + sparkline.
  Emphasized currency rows: tinted band + 0.22 border.
GfCountBox / GfCountBadge: compact metrics next to titles (minWidth 140 for boxes).

── Tables (gf_data_table.dart + LedgerColumn) ──
Card chrome + header strip (tableHeader) + pagination bar.
Row height tableRowHeight (56 scaled). Cell horizontal padding kGfCellPadding = 8.
Fixed column widths (keep consistent across pages):
  rowNumber 52 | date 110 | dateTime 160 | reference 130 | code 100 | status 160 | menu 48
Flex: number 1 | text 2 | amount 2 | primary 3 | description 4
LedgerRowMenu: more_vert 18, popup under, color modal.
Amounts end-aligned; text start-aligned; ellipsis 1 line.

── Status / type badges ──
GfStatusBadge: pill radius, caption w600, compact 11px / normal 12px;
  bg from *Bg tokens (light) or tone@14% (dark); border tone@25–35%.
TransactionTypeBadge: fixed type hues above; pill; 7px color dot; undo mark if reversed.
GfFilterChip (dialog_shared): selected = primary fill + onPrimary; else surface + border.

── Dialogs ──
Prefer GfDialogShell / OrderDetailDialogStyle / GfConfirmDialog.
- Shell: modal bg, radius 8, elevation 12, shadow Color(0x26502D55).
- Clamp: dialogMaxWidth(preferred) with 32 inset; dialogMaxHeight with 48 inset.
- OrderDetailDialogStyle: maxW 550, minH 600, maxH 700; padding LTRB 24,20,24,20;
  controlRadius 8; fieldHeight = controlHeight; scrollBody puts scrollbar in side margin.
DialogInfoBanner: tone bg + 18px icon + caption; padding 12×10.
DialogMetricBox: surface + border, icon primary 22, value bodySemiBold 18.
DialogResponsiveRow: stacks below 420, gap 12.

── Sidebar (glassflow_sidebar.dart) ──
Docked floating rail: sidebar color, border, card shadow (light), radius 20 (exception).
Nav items: radius 8; selected uses primarySoft / primary + activeGlow; SVG icons tinted.
Collapsed: hide labels when animated width < 140. Brand header + profile footer.

── Workbench (entry screens: exchange, cash, …) ──
WorkbenchLayout: main + side panel (380 / compact 330), breakpoint 900, gap from metrics.
WorkbenchModeSelector: selectable tiles padding 14, icon well 44, gap 12; selected
  primarySoft + 1.5 primary border.
WorkbenchPartyFields: responsive customer / drawer / date rows (gaps 16).

── Feedback ──
GfToast / GfSnackbar: floating, radius 8; light snackbar uses textPrimary fill + white text;
  dark uses modal fill + textPrimary. Empty: GfEmptyState (circle hover fill, optional CTA).
Loaders: GfLoader — primary spinner, respect compact constraints.

── Motion ──
Use AppDurations + existing MotionEntrance / day_night_transition. Theme toggle sun
accent #E8A317. Respect reduced-motion (themeTransitionReduced).

═══════════════════════════════════════════════════════════════
6. HARD RULES WHEN CHANGING UI
═══════════════════════════════════════════════════════════════
1. New colors → add to AppColors / AppDarkPalette; never scatter Color(0x…) in pages
   (except the documented transaction-type map and About brand hero).
2. New spacing → AppSpacing tokens or GfLayoutMetrics / SettingsMetrics; avoid magic
   EdgeInsets that fight the 4–8–12–16–20–24–32 scale.
3. New controls → extend Gf* widgets; keep height = controlHeight so rows align.
4. Radius default 8; pill only for badges; do not invent 12/16/24 for normal chrome.
5. Typography only through AppTypography (+ localize). Don’t invent random fontSize
   unless documenting a temporary exception and then folding it into a token.
6. Money always LTR + tabular figures; never float money through UI formatting.
7. RTL: use EdgeInsetsDirectional / AlignmentDirectional; test fa locale.
8. Prefer tokens that react to AppColors.applyVariant so light/dark/hadid all work.

═══════════════════════════════════════════════════════════════
7. KNOWN DESIGN / CONSISTENCY ISSUES (fix or avoid repeating)
═══════════════════════════════════════════════════════════════

[HEIGHT DRIFT]
- ThemeData Elevated/OutlinedButton minimumSize height = 42, but AppSpacing.controlHeight
  and all Gf* controls = 40. Mixing Theme buttons next to GfTextField misaligns rows.
  Fix: use Gf* buttons everywhere in forms, or align ThemeData min height to 40.

[RADIUS DRIFT]
- System says “unified at 8”, but sidebar shell uses 20, brand blocks 15/10, lock /
  unauthorized / About cards use 12–24. New work should stick to 8 (+ pill); if changing
  sidebar, either document a “shell radius” token or bring it to 8 for consistency.

[HARDCODED COLORS OUTSIDE TOKENS]
- transactionTypeColor hex map is intentional (keep), but many screens still use raw
  Color(0x…) / Colors.white / Colors.black / Colors.red|green (e.g. motion_widgets
  status colors, lock/unauthorized shadows, About white overlays). Migrate to semantic
  tokens or dedicated brand tokens so dark/hadid don’t look broken.

[FONT SIZE ONE-OFFS]
- Scattered copyWith(fontSize: 10|11|13|13.5|15|17|18|20|21|22|26) in KPI cards,
  statements, order detail, workbench, About. These bypass display/section/kpi tokens
  and make density uneven. Fold repeated sizes into AppTypography or local named styles.

[PADDING ONE-OFFS]
- Magic paddings (14, 18, 28, 32, fromLTRB mixes) in workbench tiles, settings theme
  picker, dialogs, lock screens. Prefer AppSpacing + SettingsMetrics.cardPadding.

[DUAL CARD SYSTEMS]
- GfCard vs SettingsSectionCard vs ad-hoc Container decorations. Same “card” job,
  different padding/header patterns. Prefer one pattern per context; don’t invent a
  third border+fill style.

[DUAL DIALOG SYSTEMS]
- GfDialogShell vs OrderDetailDialogStyle vs custom showDialog chrome. Heights/widths
  differ (440 vs 550, 600–700). When adding dialogs, pick one shell and reuse
  DialogInfoBanner / DialogMetricBox / DialogResponsiveRow.

[STATUS BADGE LEGACY]
- GfStatusVariant still includes retail/inventory statuses (inStock, lowStock, …)
  from the template. Money-exchange UI mostly needs success/warning/error/info +
  TransactionTypeBadge. Don’t expand the retail set; prefer semantic tones or type badges.

[ABOUT / HADID THEME SPLIT]
- About page and Hadid dark palette share navy/cyan, but light app chrome is Violet Dusk
  mauve. Switching light ↔ hadid jumps brand family. Be aware when “matching the logo”
  vs “matching Violet Dusk”; don’t randomly blend peach/mint into form chrome.

[SHADOW / SNACKBAR ASYMMETRY]
- Light snackbars/tooltips: dark (textPrimary) fill + white text.
- Dark snackbars: modal fill + textPrimary text.
- GfCard always soft-shadows in light even when showShadow=false. Dark cards usually
  flat. Keep this intentional; don’t add Material elevation on top.

[SCALE GAPS]
- Sidebar widths intentionally unscaled; some pages still use fixed fontSize that
  ignores TextScaler edge cases. Test at ~900×640 and at reference 1536×864.
- SettingsMetrics breakpoints (1400/1100/720) ≠ GfBreakpoints (1200/768). Nested
  settings/workbench density can disagree with shell breakpoints.

[ICON SIZE DRIFT]
- Icons appear as 14 / 16 / 18 / 20 / 22 across badges, menus, tiles. Theme default
  icon size is 20. Prefer 18 in dense rows, 20 in headers, 22 only in mode tiles.

[COMMENT / TOKEN DRIFT]
- gf_button.dart comment still says “Primary lime filled button” — true only in dark
  lime; light primary is mauve #935073. Keep comments/tokens honest when editing.

═══════════════════════════════════════════════════════════════
8. HOW TO APPLY THIS PROMPT
═══════════════════════════════════════════════════════════════
When asked to redesign or fix UI:
- Audit the touched widgets against sections 3–5.
- Replace off-token colors/spacing/radius/type with tokens.
- Prefer fixing shared Gf* / theme files so every screen benefits.
- Call out any remaining issue from section 7 you could not fix in this pass.
- Do not invent a new visual language (no purple-on-white SaaS defaults, no random
  large radii, no Inter-only if locale is fa).
- Keep RTL, controlHeight alignment, and light/dark/hadid working.

If the user only says “fix the design” without a target:
- Ask which surface (shell, forms, tables, dialogs, badges) OR start with the highest-
  impact consistency fixes: button height 40 everywhere, kill hardcoded Color(0x) in
  product chrome, unify radius to 8 outside sidebar/brand exceptions.
```
