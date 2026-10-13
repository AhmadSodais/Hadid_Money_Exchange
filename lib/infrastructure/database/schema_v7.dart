/// Schema version 7: a drawer may receive capital in one currency more than
/// once (the initial capital, then later injections).
///
/// Every capital entry is an `openingCash` transaction with its own
/// `opening_balances` row; only customer opening balances stay one per
/// customer and currency.
library;

const List<String> schemaV7 = [
  'DROP INDEX IF EXISTS ux_opening_cash',
  '''
  CREATE INDEX IF NOT EXISTS ix_opening_cash ON opening_balances(drawer_id, currency_code)
    WHERE kind = 'cash' AND is_active = 1
  ''',
];
