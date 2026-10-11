# Installation, backup, and recovery

## Build

Requirements on the build machine: Flutter 3.44 (Dart 3.12) with Windows desktop support and Visual Studio with the "Desktop development with C++" workload.

```powershell
cd Hadid_Money_Exchange
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

The output is `build\windows\x64\runner\Release\`.

## Install on the shop computer

1. Copy the **whole** `Release` folder (`hadid_exchange.exe`, `flutter_windows.dll`, `sqlite3.dll`, `dartjni.dll`, and the `data` folder) to, for example, `C:\Program Files\Hadid Money Exchange\`. The exe does not run without the files next to it.
2. If Windows reports a missing `VCRUNTIME140.dll` or `MSVCP140.dll`, install the Microsoft Visual C++ Redistributable (x64).
3. Create a desktop shortcut to `hadid_exchange.exe`.
4. First start: the database is created and seeded. Then, in Settings:
   - set the business name;
   - enter opening cash per currency **or** run the legacy import (see [07-legacy-migration.md](07-legacy-migration.md)), not both;
   - set the app lock passcode and write down the recovery code;
   - enter today's buy and sell rates on the Rates page.

Upgrading: close the app, take a manual backup, replace the program folder. The data folder is separate and is not touched.

## Where the data lives

| What | Path |
|---|---|
| Database | `%APPDATA%\Hadid\Hadid Money Exchange\data\hadid_exchange.db` (plus `-wal` / `-shm` while open) |
| Backups | `%APPDATA%\Hadid\Hadid Money Exchange\backups\` |

Settings → «درباره و مجوز» shows the exact paths on the current machine.

## Backups

Each backup is a pair of files:

- `hadid_backup_<timestamp>_<kind>.db`: a consistent copy made with SQLite `VACUUM INTO` while the app runs;
- `hadid_backup_<timestamp>_<kind>.manifest.json`: app id, format and schema version, creation time, size, SHA-256 of the `.db`, and a ledger fingerprint (transaction and line counts and per-currency totals).

Kinds: `manual` (the backup screen, kept in code), `auto` (at startup when the last automatic backup is older than the interval, default 24 hours), `pre_restore` (made automatically before every restore, including an Excel input or a full data clear), `pre_migration` (made before a legacy import). Only `auto` backups are pruned, keeping the newest 30 by default.

«پشتیبان‌گیری و بازیابی» is hidden from the settings navigation. The screen still holds manual backup, verify, restore, the automatic-backup interval, the backup history, and the Excel file log (output, input, and clear). Automatic backup keeps running at startup. Excel input and output, the automatic Excel export settings, and the automatic export history are under Settings → «مدیریت داده‌ها».

**A backup on the same disk is not enough.** Copy the `backups` folder (both files of each pair) to a USB drive or another computer at least once a week, and keep several generations.

## Verify a backup

The in-app check (on the hidden «پشتیبان‌گیری و بازیابی» screen, «بررسی فایل پشتیبان»):

1. confirms the file is an SQLite database;
2. compares its SHA-256 with the manifest;
3. runs `PRAGMA integrity_check`;
4. checks the schema version is not newer than the app;
5. runs the ledger integrity checks (every journal balanced per currency, every transaction has one entry, no orphan lines);
6. compares the ledger fingerprint with the manifest.

Nothing is modified by a verification.

## Restore from inside the app

From the hidden «پشتیبان‌گیری و بازیابی» screen, «بازیابی از پشتیبان»: choose the `.db` and type «بازیابی» to confirm. While that screen is hidden, use the file procedure below. When the screen is available, the app:

1. verifies the backup and refuses an invalid one;
2. makes a `pre_restore` backup of the current database;
3. swaps the files, reopens, and re-runs the integrity checks;
4. on any failure puts the previous database back and reports the error.

All screens reload after a restore. The restore is written to the audit log.

## Recovery when the app does not start

If the database cannot be opened, the app shows «پایگاه داده صرافی باز نشد» with the technical error. Nothing has been changed at that point.

1. Close the app.
2. **Copy the entire `%APPDATA%\Hadid\Hadid Money Exchange\` folder somewhere safe.** Never work on the only copy.
3. Pick the newest backup pair in `backups\` and check its hash in PowerShell:
   ```powershell
   Get-FileHash .\hadid_backup_<timestamp>_auto.db -Algorithm SHA256
   ```
   It must equal the `sha256` value in the matching `.manifest.json`.
4. In `data\`, rename `hadid_exchange.db` to `hadid_exchange.broken.db`, and move away `hadid_exchange.db-wal` and `hadid_exchange.db-shm` if they exist.
5. Copy the backup `.db` into `data\` and rename it to `hadid_exchange.db`.
6. Start the app, open Settings → «سوابق ممیزی و صحت دفاتر» → «بررسی صحت دفاتر», and compare the dashboard with the last known figures.
7. Transactions entered after that backup must be entered again from the paper receipts.

Keep `hadid_exchange.broken.db`; it may still be recoverable with SQLite tools.

## Daily routine

1. Start the app. An automatic backup is taken if one is due.
2. Update the buy and sell rates.
3. Record transactions.
4. At closing, perform the daily reconciliation (بیلانس روزانه) for each currency and close the day.
5. Once a week, copy the backups folder off the computer.
