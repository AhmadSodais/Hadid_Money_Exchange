# Business decisions

Every rule the system enforces that the master prompt did not fix exactly is listed here, with the default chosen and where it can be changed. Items under "Open questions" need the owner's answer and are **not** guessed in code.

## Accounting

| # | Decision | Default | Changeable |
|---|---|---|---|
| B1 | Sign of a customer balance | Positive = the exchange owes the customer (طلب). Negative = the customer owes (بدهی) | No (system convention) |
| B2 | Walk-in customer (`مشتری متفرقه`) | Cash only. Cannot carry a balance, cannot receive رسید/برد on account, cannot have an opening balance | No |
| B3 | Exchange results | Kept in clearing account 3300 (exchange position) per currency. No automatic profit is calculated or shown | Needs an owner decision (see Q1) |
| B4 | Fees | Optional, charged *in addition* to the exchange, in any currency, credited to 4100 | Per transaction |
| B5 | Rounding | Quote amount rounded to the quote currency's precision with that currency's rounding mode (default half-up) | Settings → currencies |
| B6 | Rate source | Entered manually; separate buy and sell rates per ordered pair; history kept. The exchange screen pre-fills the latest rate and the user can override it per transaction | Rates page |
| B7 | Negative cash | Rejected: a posting that would make any drawer/currency negative fails | Settings: `posting.allow_negative_cash` |
| B8 | Backdating | Up to 31 days back; future dates rejected | Settings: `posting.max_backdate_days` |
| B9 | Closed reconciliation | A closed day blocks postings and reversals dated on or before it for that drawer and currency | Settings: `posting.lock_reconciled_days` |
| B10 | Reconciliation difference | Stored only. Corrected by an explicit cash adjustment to 5200 with a reason | – |
| B11 | Reversal | Whole transaction, once, with a reason, dated today by default; the original keeps its date and is marked `reversed` | – |
| B12 | Opening balances | One active opening per drawer+currency and per customer+currency. To change it, reverse and enter again | – |
| B13 | Deleting | Nothing financial is deleted. Customers are deactivated (or anonymized); currencies are deactivated | – |

## Security and access

| # | Decision | Default |
|---|---|---|
| S1 | Users | One owner user (admin role, no password) because the shop runs one operator. The device is protected by the app lock. Roles admin/cashier/accountant/auditor and all permission checks already exist, so staff logins can be added without touching the financial core |
| S2 | App lock | Optional 4-digit passcode or pattern with a personal recovery code, stored only as salted PBKDF2-HMAC-SHA256 hashes (never plaintext) in the app's local preferences; automatic lock after 10 minutes idle; a cooldown after repeated wrong attempts. Moving the hashes to Windows Credential Manager is a possible hardening step |
| S3 | Staff passwords (when enabled) | PBKDF2-HMAC-SHA256, 120,000 iterations, per-user salt, lockout after repeated failures |
| S4 | Legacy bypasses | The hardcoded password and the "911" unlock are removed. There is no master code |
| S5 | Licensing | The MAC allow-list and the trial lock are removed. No licensing check exists yet, and any future check must never block opening, reading, backing up, or exporting data (see Q4) |
| S6 | Audit | Append-only. Records actor, action, entity, outcome, and before/after values; never passwords or passcodes |

## Data and interface

| # | Decision | Default |
|---|---|---|
| D1 | Language | Dari/Persian, right-to-left. UI strings are written in Persian directly in the widgets (the old multi-language JSON files belonged to the retail app) |
| D2 | Calendar | Solar Hijri (شمسی) display by default; Gregorian selectable in settings. Stored dates are always ISO Gregorian |
| D3 | Numbers | Western digits with thousands separators; amounts in Excel are exported as exact decimal text plus the currency code, never as floats |
| D4 | Spreadsheet import | Disabled. Restoring a verified backup is the only bulk-load path, and the legacy importer is the only migration path |
| D5 | Backups | Automatic backup at startup when the last one is older than 24 hours; keep the newest 30 automatic backups. Manual, pre-restore, and pre-migration backups are never pruned automatically |

## Legacy migration

| # | Decision |
|---|---|
| M1 | Customer balances are imported **exactly as the old app displayed them** (Σ income − Σ withdrawal per currency). The old app recorded both legs of a buy/sell on the customer, so balances of such customers may be inflated; they are flagged with `customer.exchangeOnAccount` for the owner to review instead of being "fixed" by guessing |
| M2 | Walk-in customer balances from the old app are not imported (`walkIn.balance` warning) because the walk-in customer cannot carry a balance |
| M3 | Rows in `removed_data.db` are archived in the issues log only; they never affect balances |
| M4 | Invalid phone numbers are kept in the customer's notes rather than dropped |
| M5 | Opening cash comes from the newest `balance.db` record per currency (by Solar date, then row id). Importing cash is optional; when skipped, cash is entered by hand |
| M6 | Each import imports into an empty ledger only, takes a backup first, and restores it automatically on any failure |

## Open questions for the owner

| # | Question | Effect until answered |
|---|---|---|
| Q1 | Should exchange profit be calculated, and with which method (average cost per currency, or spread at the time of the deal)? | 3300 shows the open position; no profit figures are shown anywhere |
| Q2 | Should fees ever be included in the rate instead of charged separately? | Fees are separate |
| Q3 | Will staff log in with their own accounts? If yes, which role does each person get? | Single owner plus app lock |
| Q4 | Is a licensing scheme required, and how should it work offline? | None; data is never blocked |
| Q5 | For customers flagged `customer.exchangeOnAccount`, should their balances be corrected after migration? | Corrected only by an explicit customer adjustment with a reason |
| Q6 | Is more than one cash drawer needed? | One drawer, `صندوق اصلی`; the schema supports more |
