# Audit

Two code bases were reviewed:

1. **The legacy exchange app** (`money_exchange_app`), which holds the real business data in `customers.db`, `balance.db`, and `removed_data.db`. It was read only for reference and has not been modified.
2. **The retail POS template** that this repository started from (products, warehouses, orders, purchases, employees, Firebase sync, device allow-list, trial lock).

## 1. Legacy exchange app

### Data model

| File | Table | Shape |
|---|---|---|
| `customers.db` | `customers(id TEXT PK, name, phone, customersdata TEXT, date, time)` | Every financial entry of a customer is an element of a JSON array stored in `customersdata`. |
| `balance.db` | `balance(date, time, currency, systemInventory, fundInventory, calculatedBalance, balanceDifference, withdrawal, previousBalanceUpdated, description)` | One manual daily cash check per currency. All numbers are text. |
| `removed_data.db` | `removed_data(...)` | Copies of entries deleted from a customer's JSON array. |

A `customersdata` entry looks like:

```json
{"idData": "1728…", "dealType": "رسید", "dealType2": "خرید", "dealModel": "دالر به افغانی",
 "details": "…", "date": "1404/6/1", "time": "10:22:05", "feePrice": "70",
 "currence_income": "دالر", "income": "1,000"}
```

A buy or sell (خرید / فروش) is stored as **two separate entries** with the same `idData`: one رسید (income) and one برد (withdrawal).

### How the legacy app computed balances

- **Customer balance per currency** = Σ `income` − Σ `withdrawa`, after stripping commas and converting Unicode dashes to minus (`customer_viewmodel.dart`). Amounts that failed `double.tryParse` counted as **0** without any warning. Entries in currencies outside its fixed list were ignored.
- **Cash** came from the manually entered `fundInventory` of the latest `balance.db` record per currency, where "latest" was decided by sorting date **strings**.
- **Exchange amount**: `total = amount / rate` when the source currency was AFN, otherwise `amount * rate` (`deal_viewmodel.dart`).

### Findings

| # | Finding | Evidence | Severity |
|---|---|---|---|
| L1 | Money stored as formatted text and computed with `double` | `income: "1,000"`, `double.tryParse` | Critical |
| L2 | Unparseable amounts silently treated as zero | `double.tryParse(...) ?? 0` | Critical |
| L3 | Rate rule "divide if source is AFN, else multiply" gives wrong totals for non-AFN pairs and is ambiguous for AFN pairs | `deal_viewmodel.dart` lines 317–371 | Critical |
| L4 | A buy/sell writes two entries with two separate read-modify-write updates; a failure between them leaves half a deal | `insertCustomerData` called twice | Critical |
| L5 | Edits overwrite entries in place; deletes remove them from the JSON array. No immutable history | `removeCustomerData`, `submitDealEdit` | Critical |
| L6 | Deleting a customer deletes all of their history | `CustomerDB.deletecustomers` | Critical |
| L7 | "Success" shown even when the customer row was not found and nothing was saved | `insertCustomerData` returns early, caller shows snackbar | High |
| L8 | Exceptions caught and only printed | `catch (e) { print(...) }` throughout | High |
| L9 | Cash is not derived from transactions; it is whatever was typed in the daily check | `balance.db` `fundInventory` | High |
| L10 | Latest daily balance picked by string sort (`"1404/9/30" > "1404/10/2"`) | `balance_viewmodel.dart` `dates.sort` | High |
| L11 | Daily balance insert uses `ConflictAlgorithm.replace` and can overwrite | `BalanceDatabase.insertBalance` | Medium |
| L12 | Customer names used to identify customers in places; ids are millisecond timestamps | `deal_viewmodel.dart` | Medium |
| L13 | Password compared in plain text; hardcoded `"911"` unlock in the idle screen | `password_viewmodel.dart:45`, `IdleDetector.dart:129` | Critical (security) |
| L14 | MAC-address allow-list blocks the whole app, including access to the owner's own data | `mac_address.dart`, `passcodePage.dart` | High |
| L15 | Dead Firebase sync code with a hardcoded URL | `user_viewmodel.dart`, `balance_viewmodel.dart` | Medium |
| L16 | Walk-in customer ("مشتری متفرقه") can accumulate balances | single customers table, no rule | Medium |
| L17 | No double entry: a deal on a customer account moves the customer balance in both currencies, with no counter account | data model | High |

## 2. Retail POS template

| # | Finding | Action |
|---|---|---|
| R1 | Retail modules (products, warehouses, purchases, orders, outbound orders, employees, trading companies, alerts) unrelated to an exchange | Removed with their pages, providers, repositories, and translations in code |
| R2 | Firebase sync and Firebase auth session | Removed; the system is offline-only |
| R3 | Device authorization through a MAC allow-list | Removed; licensing must never block data access (see business decisions) |
| R4 | Trial lock screen that blocks the app | Removed |
| R5 | Multiple ad-hoc databases and string money columns | Replaced by one normalized SQLite schema with integer minor units |
| R6 | Package name `pos_general`, store-oriented routes, sidebar, and settings | Renamed to `hadid_exchange`; new routes and sidebar for the exchange |

Kept from the template: the GlassFlow design system (`lib/core/widgets`, theme, RTL typography), the app lock (passcode/password, recovery code, idle and manual lock), the day/night theme transition, and the Shamsi date picker.

## 3. What replaced it

See [03-architecture.md](03-architecture.md), [04-database.md](04-database.md), and [05-accounting.md](05-accounting.md). Each finding above is mapped to its fix and test in [02-defect-matrix.md](02-defect-matrix.md).
