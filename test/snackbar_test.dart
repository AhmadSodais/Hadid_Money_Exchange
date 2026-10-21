import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/core/snackbar/snackbar_model.dart';
import 'package:hadid_exchange/core/snackbar/snackbar_viewmodel.dart';
import 'package:hadid_exchange/core/widgets/gf_snackbar.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('long snackbar wraps, expands on "more", pauses, and dismisses on outside tap',
      (tester) async {
    final vm = SnackbarViewModel();
    addTearDown(vm.dispose);
    const longMessage =
        'مبلغ بدهی مشتری (AFN 31,000) نمی‌تواند از موجودی فعلی صندوق اصلی مشترک (AFN 30,000) بیشتر باشد؛ '
        'صرافی فقط تا مبلغی را می‌تواند پرداخت یا قرض داده باشد که واقعاً در صندوق موجود است. '
        'ابتدا موجودی صندوق را بررسی کنید یا مبلغ را کاهش دهید.';
    vm.show(title: 'خطا در ثبت', message: longMessage, type: SnackbarType.error);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MaterialApp(
          home: GfSnackbarHost(child: Scaffold(body: SizedBox.expand())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    // Collapsed card offers "more" and does not auto-dismiss while open.
    expect(find.textContaining('snackbar.more'), findsOneWidget);
    await tester.tap(find.textContaining('snackbar.more'));
    await tester.pump();
    expect(find.textContaining('snackbar.less'), findsOneWidget);
    expect(find.text(longMessage), findsOneWidget);
    // Well past the normal 4-second auto-dismiss: still visible because
    // expanding paused the timer.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text(longMessage), findsOneWidget);

    // Tapping outside the expanded snackbar dismisses it.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(vm.items, isEmpty);
    expect(find.text(longMessage), findsNothing);
  });

  testWidgets('short snackbar has no "more" toggle and auto-dismisses', (tester) async {
    final vm = SnackbarViewModel();
    addTearDown(vm.dispose);
    vm.show(title: 'ثبت شد', type: SnackbarType.success);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MaterialApp(
          home: GfSnackbarHost(child: Scaffold(body: SizedBox.expand())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('snackbar.more'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    expect(vm.items, isEmpty);
  });
}
