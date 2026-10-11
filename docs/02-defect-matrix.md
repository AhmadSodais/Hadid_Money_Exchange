# Defect matrix

Each row links a defect from the audit (or a master-prompt rule) to the fix and to the automated test that proves the fix. Test paths are relative to `test/`.

| Id | Defect / rule | Fix | Proof |
|---|---|---|---|
| L1 | Money as text and `double` | `Decimal` (BigInt + scale) in the domain; integer minor units in every money column; `CHECK` constraints on line amounts | `domain/decimal_and_rate_test.dart`: "0.1 + 0.2 is exactly 0.3", "toMinor rejects excess precision" |
| L2 | Unparseable amounts become zero | `Decimal.parse` throws a `ValidationError`; forms refuse to submit. The legacy import reports such entries instead of hiding them | `domain/decimal_and_rate_test.dart`: "rejects non-finite and malformed input"; `integration/legacy_migration_test.dart`: analysis reports `amount.unparseable` |
| L3 | Divide/multiply rate rule | Single convention `1 base = R quote`, `quote = base × R`, rounding by the quote currency's policy | `domain/decimal_and_rate_test.dart`: "every one of the 20 ordered pairs…", "USD→AFN and AFN→USD are both multiply" |
| L4 | Half-saved deals | One command produces one journal with all legs, written in one SQLite transaction | `integration/posting_engine_test.dart`: "failure after the transaction row is inserted leaves nothing behind", "every ordered pair posts a balanced buy and sell atomically" |
| L5 | Edits and deletes rewrite history | Triggers forbid UPDATE/DELETE on journal lines, entries, transactions (except the reversal link), audit log; "delete" posts a reversal on the original date and "edit" atomically posts a reversal plus a replacement linked in `transaction_corrections` | `integration/posting_engine_test.dart`: "posted journal lines and transactions cannot be edited or deleted", "reversing a multi-leg exchange reverses every currency leg" |
| L6 | Customer delete destroys history | Customers cannot be deleted (trigger); they can be deactivated or anonymized only at zero balance | `integration/posting_engine_test.dart`: "inactive customers cannot transact; history is preserved", "anonymize requires zero balance…" |
| L7 | False success | `runAction` reports success only after the service returns; services throw on every failure | `ui_smoke_test.dart` (screens wired to services); service tests assert thrown errors |
| L8 | Swallowed exceptions | Typed `DomainError`s; database errors propagate; the UI shows the message | `integration/posting_engine_test.dart`: "foreign keys are enforced" |
| L9 | Cash not derived | Cash = Σ journal lines on cash accounts; opening capital posted once | `integration/end_to_end_scenario_test.dart`: "balances agree across every view" |
| L10 | String-sorted dates | ISO dates in the database; legacy Shamsi dates parsed to real dates | `domain/posting_rules_test.dart`: "validates calendar dates and sorts lexically"; `integration/legacy_migration_test.dart`: latest balance by real date |
| L11 | Daily balance overwrite | Reconciliation records keep their history; closing locks them; reopening needs a reason | `integration/reconciliation_test.dart`: "reopen needs a reason and permission…" |
| L12 | Names as identifiers | Integer foreign keys everywhere; `customers.code` is a generated unique code | `integration/posting_engine_test.dart`: "foreign keys are enforced" |
| L13 | Plaintext password, "911" bypass | PBKDF2-HMAC-SHA256 with per-user salt, 120,000 iterations, lockout; bypass removed; app-lock secrets hashed | `app_lock_crypto_test.dart`, `app_lock_screen_test.dart` |
| L14 | MAC allow-list blocks data | Removed. Licensing, when decided, must never block viewing, reports, backup, or export | Code removed (`device_authorization_provider`, `unauthorized_device_screen`) |
| L15 | Firebase remnants | Removed; no network code | Code removed |
| L16 | Walk-in balances | Walk-in can only settle in cash; receipts, payments, opening balances, and account settlement are rejected for it | `domain/posting_rules_test.dart`: "receipt/payment with walk-in customer is rejected", "walk-in customer cannot settle through an account" |
| L17 | No double entry | Per-currency balanced journal with the exchange-position clearing account 3300 | `domain/posting_rules_test.dart`: "cross-currency balance by nominal numbers is rejected", "buy 100 USD at 70…" |
| P1 | Never report profit from rate differences without a cost basis | Rate difference stays in 3300 (exchange position); revenue only from explicit fees | `integration/end_to_end_scenario_test.dart`: "no profit is derived from the rate difference" |
| P2 | Mandatory scenario (section 24) | Implemented exactly | `integration/end_to_end_scenario_test.dart`: AFN 97,350 / USD 2,050, after reversing B AFN 93,800 / USD 2,100 |
| P3 | Idempotent posting | Unique idempotency key per transaction | `integration/posting_engine_test.dart`: "re-submitting the same key returns the same transaction" |
| P4 | Opening capital once | Unique active opening per drawer and currency (and per customer and currency) | `integration/posting_engine_test.dart`: "opening capital can be posted only once…", "a reversed opening balance can be re-entered" |
| P5 | Negative cash | Rejected by default, including backdated outflows that would make a later day negative | `integration/posting_engine_test.dart`: "cash may not go negative, including on later dates…" |
| P6 | Dates | No future dates; 31-day backdating window (configurable); closed days locked | `integration/posting_engine_test.dart`: "future dates and dates beyond the backdating window are rejected"; `integration/reconciliation_test.dart`: "closed day locks backdating per currency…" |
| P7 | Reconciliation | expected = opening + net; difference = counted − expected; correction only by an authorized adjustment to 5200 | `integration/reconciliation_test.dart` (8 tests) |
| P8 | Backups | `VACUUM INTO` + manifest + SHA-256 + integrity check; restore verifies, takes a safety backup, and rolls back on failure | `integration/invariants_and_backup_test.dart`: snapshot/restore, tampered backup rejected, non-database rejected, retention |
| P9 | Ledger invariants | Property test against an independent model with random valid sequences | `integration/invariants_and_backup_test.dart`: "random valid sequence (seed …)" |
| P10 | Permissions | Every service checks the actor | `integration/posting_engine_test.dart`: "actors without permission are refused" |
| P11 | Legacy migration must not modify or hide data | Read from copies; fingerprint; issue log with full raw archive; empty ledger only; pre-migration backup; verify; automatic rollback | `integration/legacy_migration_test.dart` (5 tests) |
| P12 | Screens must not crash | Smoke test visits every route and report tab with real data | `ui_smoke_test.dart` |
| U1 | Customers table action buttons overflowed by 6 px | Actions column widened | `ui_smoke_test.dart` |
| U2 | Switch tiles inside cards drew ink behind the card (debug assertion) | `GfCard` provides a transparent `Material` for its content | `ui_smoke_test.dart` |
| U3 | Legacy phones such as "0700" failed new validation midway through an import | Analysis applies the same validator; the old number is kept in the customer's notes and reported as a warning | `integration/legacy_migration_test.dart` |
