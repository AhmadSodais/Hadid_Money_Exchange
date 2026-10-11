# Testing

## How to run

```powershell
cd Hadid_Money_Exchange
flutter analyze
flutter test
```

Every financial test runs against a **temporary database** created by `test/support/harness.dart` and deleted afterwards. No test opens or modifies the production database or the legacy files; the legacy-migration test even checks that the legacy files' hashes are unchanged.

## Latest results

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **96 passed, 0 failed** |
| `flutter build windows --release` | Succeeded: `build\windows\x64\runner\Release\hadid_exchange.exe` |

The test log contains Easy Localization warnings about `settings.lock.*` keys. They come from lock-screen widget tests that render without loading the translation files; the keys exist in `assets/lang/fa.json` and the app is not affected.

## Suites

| File | Tests | What it proves |
|---|---|---|
| `test/domain/decimal_and_rate_test.dart` | 14 | Exact decimal parsing (Persian digits, separators), rounding modes, no binary floating point, minor-unit bounds, all 20 ordered currency pairs with the `1 base = R quote` convention, rate validation |
| `test/domain/posting_rules_test.dart` | 16 | Per-currency balance (a cross-currency "balance" is rejected), journal line rules for every transaction type, walk-in restrictions, fee, opening sign, reversal mirror, reasons required, date validation |
| `test/integration/posting_engine_test.dart` | 17 | Atomicity (a failure after the header leaves nothing), every pair posts atomically, idempotency, one opening per drawer and currency, immutability triggers, single reversal, multi-leg reversal, backdating window, negative cash (including backdated outflows), inactive customers, permissions, foreign keys, statements, search, anonymize, journal filters |
| `test/integration/end_to_end_scenario_test.dart` | 5 | The mandatory section 24 scenario: AFN 97,350 and USD 2,050 in every view; customer consequences; transaction B as one logical record with four legs; after reversing B, AFN 93,800 and USD 2,100 everywhere; no profit derived from the rate difference |
| `test/integration/reconciliation_test.dart` | 8 | Normal close, shortage and surplus kept and corrected only by adjustment, stale count refused, closed day locks backdating per currency, reopen with reason and permission, opening ignores later lines, per-currency previous balance |
| `test/integration/invariants_and_backup_test.dart` | 7 | Random valid sequences (seeds 1, 7, 42) checked against an independent model; backup, change, restore gives identical balances; tampered backups and non-database files rejected with the live database untouched; automatic backup interval and retention |
| `test/integration/legacy_migration_test.dart` | 5 | Analysis reproduces legacy balances and reports discrepancies; import posts verified opening balances without touching the legacy files and refuses a second import; blocking issues write nothing; non-empty ledger refused; mid-import failure restores the pre-migration state |
| `test/ui_smoke_test.dart` | 1 | Boots the real app shell with seeded data and opens every route (dashboard, exchange, cash, customers, statement, journal, reconciliation, every report tab, rates, settings) without exceptions or layout overflows |
| `test/app_lock_crypto_test.dart` | 6 | PBKDF2-HMAC-SHA256 against RFC 6070 vectors, 4-digit passcode rule, pattern input, recovery-code normalization, constant-time comparison |
| `test/app_lock_screen_test.dart` | 7 | Unlock by passcode, wrong passcode, extra digits ignored, Persian digits, recovery code resets the passcode |
| `test/day_night_transition_test.dart` | 6 | Theme switching |
| `test/gf_scroll_behavior_test.dart` | 4 | Desktop scrolling behavior |

## Not covered by automated tests

- The legacy importer has only been run on synthetic files with the legacy schema, not on the shop's real files (see [07-legacy-migration.md](07-legacy-migration.md)).
- Excel export output is not checked cell by cell.
- Printing and multi-monitor layouts are not tested.
- Manual recovery when the app cannot open its database ([08-operations.md](08-operations.md)) is a documented procedure, not an automated test.
