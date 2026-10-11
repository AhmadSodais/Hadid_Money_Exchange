import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_general/core/widgets/gf_scroll_behavior.dart';

Widget _app(int itemCount, {TextDirection dir = TextDirection.ltr}) {
  return MaterialApp(
    scrollBehavior: const GfScrollBehavior(),
    home: Directionality(
      textDirection: dir,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: itemCount,
            itemBuilder: (_, i) => SizedBox(height: 50, key: ValueKey(i)),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets('short list keeps full width', (tester) async {
    await tester.pumpWidget(_app(3));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, 400);
  }, variant: windows);

  testWidgets('overflowing list reserves the scrollbar gutter', (
    tester,
  ) async {
    await tester.pumpWidget(_app(40));
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey(0)));
    expect(rect.width, 400 - kGfScrollbarGutter);
    expect(rect.left, 200); // LTR: gutter on the right
  }, variant: windows);

  testWidgets('RTL puts the gutter on the left', (tester) async {
    await tester.pumpWidget(_app(40, dir: TextDirection.rtl));
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey(0)));
    expect(rect.left, 200 + kGfScrollbarGutter);
  }, variant: windows);

  testWidgets('gutter stays after content shrinks in the same viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_app(40));
    await tester.pump();
    await tester.pumpWidget(_app(2));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const ValueKey(0))).width,
      400 - kGfScrollbarGutter,
    );
  }, variant: windows);
}
