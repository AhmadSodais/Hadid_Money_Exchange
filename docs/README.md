# Hadid Money Exchange (صرافی حدید)

Offline, Windows-first currency exchange and accounting system with a Persian (Dari) right-to-left interface.

- One SQLite database with a double-entry ledger that balances **per currency**.
- Five configurable currencies out of the box: AFN, USD, EUR, IRT (toman), PKR.
- Exchanges (خرید / فروش), receipts (رسید), payments (برد), expenses, opening balances, reconciliation, reversals.
- Posted history is immutable. Corrections are made by reversal or by an authorized adjustment, never by editing or deleting.
- Verified backups with manifest and checksum, safe restore, and a verified import from the previous application.

## Quick start

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release   # → build\windows\x64\runner\Release\hadid_exchange.exe
```

Requirements: Flutter 3.44+ / Dart 3.12+, Visual Studio with the "Desktop development with C++" workload.

## Where data lives

| What | Location |
|---|---|
| Live database | `%APPDATA%\Hadid\Hadid Money Exchange\data\hadid_exchange.db` |
| Backups | `%APPDATA%\Hadid\Hadid Money Exchange\backups\hadid_backup_<stamp>_<kind>.db` + `.manifest.json` |
| UI preferences | Windows shared preferences (theme, calendar, selected drawer, app lock) |

Tests never touch these paths; every test creates its own temporary database.

## Documents

| Document | Contents |
|---|---|
| [01-audit.md](01-audit.md) | Audit of the legacy exchange app and of the retail template this project started from |
| [02-defect-matrix.md](02-defect-matrix.md) | Every defect found, how it is fixed, and the test that proves it |
| [03-architecture.md](03-architecture.md) | Layers, folders, data flow, events, screens |
| [04-database.md](04-database.md) | ERD, tables, constraints, immutability triggers, migrations |
| [05-accounting.md](05-accounting.md) | Chart of accounts, sign conventions, posting rules for every transaction type |
| [06-business-decisions.md](06-business-decisions.md) | Decisions taken where the specification left a choice, and open questions for the owner |
| [07-legacy-migration.md](07-legacy-migration.md) | Moving data from `customers.db` / `balance.db` / `removed_data.db` |
| [08-operations.md](08-operations.md) | Installation, packaging, backup, restore, recovery, troubleshooting |
| [09-testing.md](09-testing.md) | Test strategy, test list, and latest results |
