import 'package:flutter_test/flutter_test.dart';
import 'package:hadid_exchange/domain/errors/domain_errors.dart';
import 'package:hadid_exchange/domain/security/permissions.dart';

import '../support/harness.dart';

void main() {
  late Harness h;

  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test('the user can set their app name and phone number', () async {
    final id = h.owner.userId;
    await h.app.security.updateProfile(id, displayName: '  احمد  ', phone: '۰۷۰۰ ۱۲۳ ۴۵۶', actor: h.owner);
    final profile = await h.app.security.profile(id);
    expect(profile.displayName, 'احمد');
    expect(profile.phone, '0700 123 456');
    expect((await h.app.security.actorFor(id)).displayName, 'احمد');

    await h.app.security.updateProfile(id, displayName: 'احمد', phone: ' ', actor: h.owner);
    expect((await h.app.security.profile(id)).phone, isNull);

    final audit = await h.app.db.query('audit_logs', where: "action = 'user.profileUpdate'");
    expect(audit, hasLength(2));
  });

  test('invalid names and phone numbers are rejected', () async {
    final id = h.owner.userId;
    await expectLater(
      h.app.security.updateProfile(id, displayName: ' ', actor: h.owner),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      h.app.security.updateProfile(id, displayName: 'x' * 61, actor: h.owner),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      h.app.security.updateProfile(id, displayName: 'احمد', phone: 'abc123', actor: h.owner),
      throwsA(isA<ValidationError>()),
    );
  });

  test('only the user or a settings manager can change a profile', () async {
    final other = Actor(userId: 999, displayName: 'c', permissions: Permissions.roleDefaults['cashier']!.toSet());
    await expectLater(
      h.app.security.updateProfile(h.owner.userId, displayName: 'x', actor: other),
      throwsA(isA<AuthorizationError>()),
    );
  });

  test('profile and exchange location survive clearing all data', () async {
    await h.app.security.updateProfile(h.owner.userId, displayName: 'احمد', phone: '0700123456', actor: h.owner);
    await h.app.catalog.putSetting('business.city', 'کابل', h.owner);
    await h.app.catalog.putSetting('business.address', 'سرای شهزاده', h.owner);

    await h.app.transfer.clearAll(h.owner);

    final profile = await h.app.security.profile(h.owner.userId);
    expect(profile.displayName, 'احمد');
    expect(profile.phone, '0700123456');
    expect(await h.app.catalog.setting('business.city'), 'کابل');
    expect(await h.app.catalog.setting('business.address'), 'سرای شهزاده');
  });
}
