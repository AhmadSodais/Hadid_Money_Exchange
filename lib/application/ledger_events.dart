import 'dart:async';

enum LedgerChange { posting, customer, rates, reconciliation, reference, restore, export }

/// Broadcasts *after* a successful commit so queries can refresh.
///
/// UI refreshes are never part of the financial commit itself.
final class LedgerEvents {
  final StreamController<LedgerChange> _controller =
      StreamController<LedgerChange>.broadcast();

  Stream<LedgerChange> get stream => _controller.stream;

  void notify(LedgerChange change) {
    if (!_controller.isClosed) _controller.add(change);
  }

  Future<void> dispose() => _controller.close();
}
