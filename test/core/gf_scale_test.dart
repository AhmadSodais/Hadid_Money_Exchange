import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/core/utils/gf_scale.dart';

void main() {
  group('GfScale.factorForSize', () {
    test('is 1.0 at the main-laptop reference size', () {
      expect(
        GfScale.factorForSize(
          const Size(GfScale.referenceWidth, GfScale.referenceHeight),
        ),
        1.0,
      );
    });

    test('stays 1.0 on larger screens', () {
      expect(GfScale.factorForSize(const Size(1920, 1080)), 1.0);
    });

    test('stays 1.0 within chrome/taskbar tolerance', () {
      // Slightly smaller than reference (e.g. taskbar / title bar).
      expect(
        GfScale.factorForSize(const Size(1536, 830)),
        1.0,
      );
    });

    test('shrinks clearly below the reference', () {
      final scale = GfScale.factorForSize(const Size(1280, 720));
      expect(scale, lessThan(GfScale.fullScaleTolerance));
      expect(scale, greaterThanOrEqualTo(GfScale.minFactor));
      expect(scale, closeTo(720 / GfScale.referenceHeight, 0.01));
    });

    test('clamps to minFactor on very small windows', () {
      expect(
        GfScale.factorForSize(const Size(800, 500)),
        GfScale.minFactor,
      );
    });

    test('uses the tighter of width or height', () {
      final scale = GfScale.factorForSize(const Size(1600, 700));
      expect(scale, closeTo(700 / GfScale.referenceHeight, 0.001));
    });

    test('text factor is layout factor boosted a little', () {
      expect(
        GfScale.textFactorForSize(
          const Size(GfScale.referenceWidth, GfScale.referenceHeight),
        ),
        closeTo(GfScale.textBoost, 0.001),
      );
      expect(GfScale.textBoost, greaterThan(1.0));
    });
  });

  testWidgets('GfScaleHost keeps full layout scale, boosted text, on main laptop',
      (tester) async {
    late TextScaler scaler;
    late double factor;

    tester.view.physicalSize =
        const Size(GfScale.referenceWidth, GfScale.referenceHeight);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: GfScaleHost(
          child: Builder(
            builder: (context) {
              scaler = MediaQuery.textScalerOf(context);
              factor = GfScale.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    // Layout unchanged on the main laptop; text is a few percent bigger.
    expect(factor, 1.0);
    expect(scaler.scale(14) / 14, closeTo(GfScale.textBoost, 0.01));
    expect(scaler.scale(14), closeTo(15.4, 0.15));
  });
}
