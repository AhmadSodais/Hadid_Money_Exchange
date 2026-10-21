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
| B7 | Cashbox withdrawal limit | Rejected, absolutely: any posting whose net effect would make the **pooled main-cashbox balance** of a currency negative on any date fails (`cash.insufficient`) — a withdrawal can never exceed the current cashbox balance. Evaluated on the cashbox as a whole, across all dates (backdated outflows included) | No override (the old `posting.allow_negative_cash` setting no longer disables it) |
| B8 | Backdating | Up to 31 days back; future dates rejected | Settings: `posting.max_backdate_days` |
| B9 | Closed reconciliation | A closed day blocks postings and reversals dated on or before it for that drawer and currency | Settings: `posting.lock_reconciled_days` |
| B10 | Reconciliation difference | Stored only. Corrected by an explicit cash adjustment to 5200 with a reason | – |
| B11 | Reversal | Whole transaction, once, with a reason, dated today by default; the original keeps its date and is marked `reversed` | – |
| B12 | Opening balances | One active opening per currency (in the main cashbox) and per customer+currency. To change it, edit or delete it from the journal (both post a reversal; history is kept) | – |
| B15 | Opening customer balance, initial capital, and the unified cashbox | **Initial capital (3100, renamed «سرمایه اولیه صرافی») is the exchange's own funds only** and is posted exclusively by opening cash (incl. later injections); customer opening balances never credit or debit it — the previous configuration credited client debt (and debited client funds) to 3100, so "initial capital" wrongly included client money (reported by the owner). Own and customer funds are pooled in the **one main cashbox**; an opening customer balance records that customer's share of it against cash: liability `Dr Cash / Cr Customer` (cashbox total and the customer share rise together; own capital unchanged by it), debt `Dr Customer / Cr Cash` (cashbox total falls). **Client-debt cashbox check (owner requirement):** a debt opening asserts funds were paid out or lent from the cashbox, so it is rejected (`opening.debtExceedsAvailableFunds`) when the amount exceeds the **current cashbox balance** in that currency on the effective date — the pooled total (own capital + customer funds), with *no* deduction for other customers' shares (this replaces the earlier physical − reserved rule); e.g. a 21,000 debt against a 20,000 cashbox is blocked, and the error names both amounts and states the amount cannot exceed the cashbox balance. The same total caps every withdrawal (برد/expense/exchange payout) through the pooled `cash.insufficient` check. "Settled/covered" (e.g. reversing the opening) and "paid out" (برد, cashbox total and liability fall together) are separate flows. Legacy migration: only the residual (`physical − net customer balances`) is initial capital; debtor openings in currencies whose legacy cash was not imported keep the historical 3100 funding so their migration balances stay reachable | – |
| B14 | Single main cashbox (صندوق اصلی مشترک) | **One cashbox only** (supersedes the former multi-drawer model): the seeded main drawer is the sole fund; all pages offer only it (the picker is fixed), creating another drawer is rejected (`cashbox.single`), postings naming another drawer are rejected (`cashbox.nonMainDrawer`), the main cashbox can be renamed but never deactivated, and schema v9 moves every legacy extra drawer's balance into the main fund with dated consolidation transactions (`CBX-…`) and deactivates the extras. Daily reconciliation is kept for the main cashbox per currency | Settings → «ارز و صندوق» shows the one cashbox |
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
| D2 | Calendar | Solar Hijri (شمسی) only: every date is shown and entered in Solar Hijri, and the Excel file and backup file names use it too. There is no calendar setting. Inside SQLite, dates stay ISO so that sorting, ranges, and closed-day checks remain exact |
| D3 | Numbers | Western digits with thousands separators; Excel cells hold exact integer minor units or canonical decimal text, never floats |
| D4 | Excel input/output | Only in Settings → «مدیریت داده‌ها»; pages have no Excel button. Output writes every table to one workbook (credentials excluded). Input never merges: it builds a separate database from the workbook, requires the ledger invariants and the exported fingerprint to match, takes a safety backup, swaps it in, and rolls back on any failure |
| D6 | Clear all data | Settings → «پاک کردن همه داده‌ها», typed confirmation, `backup.restore` permission. Swaps in a fresh database that keeps exchange information, posting policies, and currency definitions; a safety backup is taken first and can be restored |
| D7 | Hidden settings | «انتقال از برنامه قبلی», «سوابق ممیزی و صحت دفاتر», and «پشتیبان‌گیری و بازیابی» (automatic backup, backup history, and the Excel file log) are hidden from the settings navigation (code kept). Automatic backup still runs at startup. The audit log is still written |
| D8 | Automatic Excel export | Settings → «مدیریت داده‌ها» → «خروجی خودکار اکسل». Off by default. When on, the app checks at startup and every 15 minutes while open, and writes a full workbook (`hadid_auto_<Solar date>_<time>.xlsx`) when the last attempt is older than the interval (default 24 hours). Folder is selectable (default `%APPDATA%\Hadid\Hadid Money Exchange\excel_exports\`). Keeps the newest 30 successful files; only files listed in the history are ever deleted. Every attempt, including failures, is listed with its full path in «سوابق خروجی خودکار اکسل» |
| D9 | Exchange information | Settings → «اطلاعات صرافی» holds only the exchange's name, province/city, and address, plus the current user's display name (shown in the sidebar) and phone number. The internal login username is not changed. Posting rules (back-dating limit, negative cash, closed-day lock) live in their own section «قوانین ثبت اسناد». All of these survive clear-all |
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
| Q6 | Is more than one cash drawer needed? | Answered: drawers are managed in Settings → «ارز و صندوق» (see B14) |
