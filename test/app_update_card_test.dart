import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/core/constants/app_constants.dart';
import 'package:hadid_exchange/core/snackbar/snackbar_viewmodel.dart';
import 'package:hadid_exchange/presentation/widgets/app_update_card.dart';
import 'package:provider/provider.dart';

Widget _host() {
  return ChangeNotifierProvider(
    create: (_) => SnackbarViewModel(),
    child: const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: AppUpdateCard(padding: 20)),
      ),
    ),
  );
}

void main() {
  testWidgets('update card shows current version and the manual check button', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.text('به‌روزرسانی برنامه'), findsOneWidget);
    expect(find.text('بررسی به‌روزرسانی'), findsOneWidget);
    expect(
      find.text('${AppConstants.appVersion}+${AppConstants.appBuildNumber}'),
      findsOneWidget,
    );
    // No published update is known yet, so no download card is offered.
    expect(find.text('دانلود به‌روزرسانی'), findsNothing);
  });

  testWidgets('a failed check shows a warning instead of crashing', (tester) async {
    await tester.pumpWidget(_host());

    // In the test environment the manifest request fails (no real network),
    // which must surface as the offline warning, not an exception.
    await tester.runAsync(() async {
      await tester.tap(find.text('بررسی به‌روزرسانی'));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pump();

    expect(find.textContaining('بررسی به‌روزرسانی انجام نشد'), findsWidgets);
  });
}
