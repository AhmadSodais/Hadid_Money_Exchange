import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/core/theme/app_colors.dart';
import 'package:hadid_exchange/core/theme/app_durations.dart';
import 'package:hadid_exchange/core/theme/day_night_transition.dart';

const _light = Color(0xFFFFFFFF);
const _dark = Color(0xFF000000);
const _surfaceKey = Key('theme-surface');
final _homeKey = GlobalKey();

class _Harness extends StatefulWidget {
  const _Harness({
    this.reduceMotion = false,
    this.solid = false,
    this.staticPalette = false,
  });

  final bool reduceMotion;
  final bool solid;
  final bool staticPalette;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  ThemeMode mode = ThemeMode.light;
  int builds = 0;

  void setMode(ThemeMode value) => setState(() => mode = value);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _surfaceKey,
      child: DayNightThemeTransition(
        variant: mode == ThemeMode.dark ? AppThemeVariant.dark : AppThemeVariant.light,
        reduceMotion: widget.reduceMotion,
        builder: (context, variant) {
          builds++;
          final themeMode = variant.themeMode;
          final dark = themeMode == ThemeMode.dark;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            themeMode: themeMode,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) {
              AppColors.applyBrightness(Theme.of(context).brightness);
              return child!;
            },
            home: widget.staticPalette
                ? const _StaticPaletteBox()
                : widget.solid
                ? ColoredBox(
                    key: _homeKey,
                    color: dark ? _dark : _light,
                    child: const SizedBox.expand(),
                  )
                : Scaffold(body: Text(dark ? 'dark' : 'light')),
          );
        },
      ),
    );
  }
}

Finder get _overlay => find.descendant(
  of: find.byType(IgnorePointer),
  matching: find.byType(CustomPaint),
);

Future<void> _pumpUntilOverlay(WidgetTester tester) async {
  for (var i = 0; i < 12 && _overlay.evaluate().isEmpty; i++) {
    await tester.pump();
  }
  expect(_overlay, findsOneWidget);
  // The reveal starts on the frame after the full rebuild.
  await tester.pump();
}

/// Reads only the static palette, like most GlassFlow widgets, and is
/// `const`, so nothing but a forced rebuild can refresh it.
class _StaticPaletteBox extends StatelessWidget {
  const _StaticPaletteBox();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppColors.background, child: const SizedBox.expand());
}

Future<Color> _pixel(WidgetTester tester, Offset position) async {
  final color = await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_surfaceKey),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = image.width;
    final height = image.height;
    image.dispose();
    final x = position.dx.round().clamp(0, width - 1);
    final y = position.dy.round().clamp(0, height - 1);
    final i = (y * width + x) * 4;
    final bytes = data!.buffer.asUint8List();
    return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  });
  return color!;
}

void main() {
  testWidgets('animates light to dark and cleans up the overlay', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    expect(find.text('light'), findsOneWidget);
    expect(_overlay, findsNothing);

    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.setMode(ThemeMode.dark);
    await _pumpUntilOverlay(tester);

    expect(find.text('dark'), findsOneWidget);

    final buildsMidway = state.builds;
    await tester.pump(AppDurations.themeTransition ~/ 2);
    expect(
      state.builds,
      buildsMidway,
      reason: 'app must not rebuild per frame',
    );

    await tester.pumpAndSettle();
    expect(_overlay, findsNothing);
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('reduced motion uses the short cross-fade', (tester) async {
    await tester.pumpWidget(const _Harness(reduceMotion: true));
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.setMode(ThemeMode.dark);
    await _pumpUntilOverlay(tester);

    await tester.pump(
      AppDurations.themeTransitionReduced + const Duration(milliseconds: 20),
    );
    await tester.pump();
    expect(_overlay, findsNothing);
    expect(find.text('dark'), findsOneWidget);
  });

  testWidgets('switching again mid-transition lands on the latest mode', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.setMode(ThemeMode.dark);
    await _pumpUntilOverlay(tester);
    await tester.pump(const Duration(milliseconds: 200));

    state.setMode(ThemeMode.light);
    await tester.pumpAndSettle();

    expect(_overlay, findsNothing);
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('moon closes daylight inward, sun grows it outward (center)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _Harness(solid: true));
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    final size = tester.getSize(find.byKey(_surfaceKey));
    final center = size.center(Offset.zero);
    const corner = Offset(4, 4);
    final edge = Offset(size.width - 4, center.dy);

    // To dark: the old light frame survives only inside a shrinking circle.
    state.setMode(ThemeMode.dark);
    await _pumpUntilOverlay(tester);
    await tester.pump(AppDurations.themeTransition ~/ 2);
    expect(await _pixel(tester, center), _light);
    expect(await _pixel(tester, corner), _dark);
    expect(await _pixel(tester, edge), _dark);

    await tester.pump(AppDurations.themeTransition * 9 ~/ 20);
    expect(await _pixel(tester, corner), _dark);
    expect(_overlay, findsOneWidget);

    await tester.pumpAndSettle();
    expect(_overlay, findsNothing);
    expect(await _pixel(tester, center), _dark);
    expect(await _pixel(tester, corner), _dark);

    // To light: the new light theme fills a growing circle.
    state.setMode(ThemeMode.light);
    await _pumpUntilOverlay(tester);
    await tester.pump(AppDurations.themeTransition ~/ 2);
    expect(await _pixel(tester, center), _light);
    expect(await _pixel(tester, corner), _dark);
    expect(await _pixel(tester, edge), _dark);

    await tester.pumpAndSettle();
    expect(await _pixel(tester, center), _light);
    expect(await _pixel(tester, corner), _light);
  });

  testWidgets('revealFrom anchors both directions on the tapped point', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _Harness(solid: true));
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    const icon = Offset(60, 60);
    const farCorner = Offset(796, 596);

    // Moon: daylight shrinks onto the icon.
    DayNightThemeTransition.revealFrom(
      _homeKey.currentContext!,
      globalCenter: icon,
      radius: 16,
    );
    state.setMode(ThemeMode.dark);
    await _pumpUntilOverlay(tester);
    await tester.pump(AppDurations.themeTransition ~/ 2);
    expect(await _pixel(tester, icon), _light);
    expect(await _pixel(tester, farCorner), _dark);
    await tester.pumpAndSettle();
    expect(await _pixel(tester, icon), _dark);
    expect(await _pixel(tester, farCorner), _dark);

    // Sun: daylight starts as the icon-sized circle and grows from it.
    DayNightThemeTransition.revealFrom(
      _homeKey.currentContext!,
      globalCenter: icon,
      radius: 16,
    );
    state.setMode(ThemeMode.light);
    await _pumpUntilOverlay(tester);
    expect(await _pixel(tester, icon), _light);
    expect(await _pixel(tester, icon + const Offset(40, 0)), _dark);

    await tester.pump(AppDurations.themeTransition ~/ 2);
    expect(await _pixel(tester, icon), _light);
    expect(await _pixel(tester, farCorner), _dark);

    await tester.pumpAndSettle();
    expect(_overlay, findsNothing);
    expect(await _pixel(tester, farCorner), _light);
  });

  testWidgets('widgets reading only AppColors switch with the theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _Harness(staticPalette: true));
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    const probe = Offset(200, 150);
    expect(await _pixel(tester, probe), AppColors.lightBackground);

    state.setMode(ThemeMode.dark);
    await _pumpUntilOverlay(tester);
    await tester.pumpAndSettle();
    expect(_overlay, findsNothing);
    expect(await _pixel(tester, probe), AppColors.darkBackground);

    state.setMode(ThemeMode.light);
    await _pumpUntilOverlay(tester);
    await tester.pumpAndSettle();
    expect(await _pixel(tester, probe), AppColors.lightBackground);
  });
}
