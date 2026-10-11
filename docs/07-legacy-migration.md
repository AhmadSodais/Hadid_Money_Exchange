# Legacy migration

The old exchange app kept its data in three SQLite files. The importer turns them into opening balances in the new ledger without modifying the old files and without guessing.

## Where the old files are

The old app used `sqflite_common_ffi` defaults, so its databases are normally in the `.dart_tool\sqflite_common_ffi\databases\` folder next to the old program (or the folder it was started from):

| File | Table | Used for |
|---|---|---|
| `customers.db` (required) | `customers` (id, name, phone, `data` JSON with the entry history) | Customers and their balances |
| `balance.db` (optional) | `balance` (date, `fundInventory` per currency) | Opening cash |
| `removed_data.db` (optional) | `removed_data` | Archived only |

**Copy these files to a safe place first** (for example a USB drive) and import from the copy.

## Steps in the app

Settings → «انتقال اطلاعات برنامه قبلی» (needs the opening-balance and backup-restore permissions):

1. Choose `customers.db`, and optionally `balance.db` and `removed_data.db`.
2. Press **بررسی اطلاعات**. This is read-only. It shows the files used, the number of customers, the balance totals per currency, the opening cash it found, and every issue sorted by severity.
3. Fix the source data or accept the warnings. Errors block the import.
4. Choose whether to import cash from `balance.db`. If not, enter opening cash by hand in Settings.
5. Press **انتقال به دفتر** and type «انتقال» to confirm.

## Guarantees

- **Old files are never changed.** Each file (and its `-wal`/`-shm` companions) is copied to a temporary folder and opened read-only. A SHA-256 fingerprint of the sources identifies the import.
- **Empty ledger only.** The import refuses to run when any transaction already exists (`legacy.ledgerNotEmpty`), so legacy balances cannot double up with new data.
- **Once per source.** A fingerprint that was already imported successfully is refused (`legacy.alreadyImported`).
- **Backup first.** A `pre_migration` backup is created before anything is written.
- **All or nothing.** Customers and opening balances are posted through the normal posting engine with idempotency keys, then each balance is re-read and compared with the analysis. On any failure the pre-migration backup is restored automatically, and the attempt is recorded as `rolled_back`.
- **Nothing hidden.** Every issue, plus the full raw history of every customer and every removed row, is stored in `migration_issues` and linked to the run in `legacy_import_runs`.

## How balances are reproduced

The old app computed each customer's balance per currency as **Σ income − Σ withdrawal**, treated unparseable amounts as zero, and ignored unknown currencies. The importer reproduces exactly that figure so the first statement in the new app matches what the owner last saw. Currency names map as افغانی→AFN, دالر→USD, یورو→EUR, تومان→IRT, کالدار→PKR.

Each non-zero balance becomes an opening customer balance (`Dr/Cr 3100` against the customer). Cash becomes opening cash for the main drawer.

## Issue codes

| Code | Severity | Meaning |
|---|---|---|
| `customer.nameMissing` | error | Customer without a name |
| `customer.invalid` | error | Customer data rejected by validation |
| `customer.dataUndecodable` | error | Entry history JSON cannot be read |
| `entry.malformed` | error | An entry is not a valid record |
| `amount.tooPrecise` | error | More decimals than the currency allows |
| `cash.unparseable`, `cash.tooPrecise`, `cash.negative` | error | Bad cash figure in `balance.db` (blocks only when cash is imported) |
| `customer.phoneInvalid` | warning | Phone moved to notes |
| `customer.duplicateName` | warning | Two customers share a name; both are imported |
| `amount.empty`, `amount.unparseable` | warning | Counted as zero, like the old app |
| `amount.negative` | warning | Negative entry amount |
| `currency.unknown` | warning | Ignored, like the old app |
| `pair.incomplete` | warning | A buy/sell with only one leg |
| `customer.exchangeOnAccount` | warning | Buy/sell legs recorded on the customer; the balance may include both legs. Review after import |
| `walkIn.balance` | warning | Walk-in balance not imported |
| `balance.currencyUnknown`, `balance.dateUnparseable` | warning | Problem in a `balance.db` row |
| `entry.edited` | info | Entry was edited in the old app |
| `legacy.customerHistory`, `legacy.removedEntry`, `legacy.balanceRecord` | info | Raw archive rows (hidden in the summary, kept in the database) |

## Verification status

The importer is covered by `test/integration/legacy_migration_test.dart`, which builds files with the exact legacy schemas and checks the analysis, a full import, blocking errors, refusal on a non-empty ledger, and automatic rollback after a mid-import failure. It has **not yet been run against the real production files**. Do the first real import on a copy and compare a few customer statements with the old app before going live.
