import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/core/security/app_biometric.dart';
import 'package:hadid_exchange/presentation/providers/app_lock_provider.dart';
import 'package:hadid_exchange/presentation/widgets/app_lock_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HelloPending extends AppBiometric {
  @override
  Future<AppBiometricHardware> detect() async => const AppBiometricHardware(
    ready: true,
    fingerprint: true,
    face: false,
  );

  @override
  Future<AppBiometricStatus> prompt(String reason) =>
      Future<AppBiometricStatus>.delayed(
        const Duration(days: 1),
        () => AppBiometricStatus.canceled,
      );
}

Future<AppLockProvider> _lockedProvider() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final lock = AppLockProvider(prefs, biometric: _HelloPending());
  await lock.enable(method: AppLockMethod.passcode, secret: '1234');
  lock.lock();
  return lock;
}

Widget _host(AppLockProvider lock) => ChangeNotifierProvider.value(
  value: lock,
  child: const MaterialApp(home: AppLockScreen()),
);

void main() {
  testWidgets('typing the passcode unlocks the app', (tester) async {
    final lock = await tester.runAsync(_lockedProvider);
    await tester.pumpWidget(_host(lock!));
    await tester.pump();

    expect(lock.isLocked, isTrue);
    await tester.enterText(find.byType(TextField), '1234');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();

    expect(lock.isLocked, isFalse);
  });

  testWidgets('wrong passcode keeps the lock and clears the boxes', (
    tester,
  ) async {
    final lock = await tester.runAsync(_lockedProvider);
    await tester.pumpWidget(_host(lock!));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '9999');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();

    expect(lock.isLocked, isTrue);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('extra digits beyond 4 are ignored', (tester) async {
    final lock = await tester.runAsync(_lockedProvider);
    await tester.pumpWidget(_host(lock!));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123456');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();

    expect(lock.isLocked, isFalse);
  });

  test('a 5-digit passcode cannot be set', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final lock = AppLockProvider(prefs, biometric: _HelloPending());
    final code = await lock.enable(
      method: AppLockMethod.passcode,
      secret: '12345',
    );
    expect(code, isNull);
    expect(lock.isEnabled, isFalse);
  });

  testWidgets('own recovery code lets the user set a new passcode', (
    tester,
  ) async {
    final lock = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final lock = AppLockProvider(prefs, biometric: _HelloPending());
      await lock.enable(
        method: AppLockMethod.passcode,
        secret: '1234',
        recovery: 'my secret 99',
      );
      lock.lock();
      return lock;
    });
    await tester.pumpWidget(_host(lock!));
    await tester.pump();

    await tester.tap(find.text('settings.lock.forgot'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'MY-SECRET99');
    await tester.tap(find.text('settings.lock.next'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '5678');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '5678');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();

    expect(lock.isLocked, isFalse);
    lock.lock();
    expect(await tester.runAsync(() => lock.unlockWithSecret('5678')), isTrue);
  });

  test('own recovery code must be at least 6 characters', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final lock = AppLockProvider(prefs, biometric: _HelloPending());
    final code = await lock.enable(
      method: AppLockMethod.passcode,
      secret: '1234',
      recovery: 'abc',
    );
    expect(code, isNull);
  });

  testWidgets('Persian digits are accepted', (tester) async {
    final lock = await tester.runAsync(_lockedProvider);
    await tester.pumpWidget(_host(lock!));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '۱۲۳۴');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    await tester.pump();

    expect(lock.isLocked, isFalse);
  });
}
