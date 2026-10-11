import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/app_services.dart';
import '../../application/catalog_service.dart';
import '../../application/ledger_events.dart';
import '../../domain/money/currency.dart';
import '../../domain/security/permissions.dart';

/// UI-facing session: the services, the signed-in actor, and cached
/// reference data. Pages watch [revision] and reload their queries after
/// every committed change (events are emitted only after commit).
class AppSession extends ChangeNotifier {
  AppSession._(this.services, this._actor);

  static Future<AppSession> start(AppServices services, int userId) async {
    final actor = await services.security.actorFor(userId);
    final session = AppSession._(services, actor);
    await session._loadReference();
    session._subscription = services.events.stream.listen(session._onChange);
    return session;
  }

  final AppServices services;
  Actor _actor;
  StreamSubscription<LedgerChange>? _subscription;

  Map<String, Currency> _currencies = const {};
  List<CashDrawer> _drawers = const [];
  int _walkInId = 0;
  int _revision = 0;

  Actor get actor => _actor;
  int get revision => _revision;
  int get walkInCustomerId => _walkInId;
  List<CashDrawer> get drawers => _drawers;
  List<CashDrawer> get activeDrawers => _drawers.where((d) => d.isActive).toList();

  /// Every currency (inactive ones are still needed to display history).
  Map<String, Currency> get currencies => _currencies;

  List<Currency> get activeCurrencies {
    final list = _currencies.values.where((c) => c.isActive).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  Currency? currency(String? code) => code == null ? null : _currencies[code];

  bool can(String permission) => _actor.can(permission);

  Future<void> _onChange(LedgerChange change) async {
    if (change == LedgerChange.reference || change == LedgerChange.restore) {
      await _loadReference();
      if (change == LedgerChange.restore) {
        _actor = await services.security.actorFor(_actor.userId);
      }
    }
    _revision++;
    notifyListeners();
  }

  Future<void> _loadReference() async {
    _currencies = await services.catalog.currencies();
    _drawers = await services.catalog.drawers();
    _walkInId = await services.catalog.walkInCustomerId();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
