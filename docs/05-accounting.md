# Accounting model

## Principles

1. **Per-currency double entry.** Every journal must have equal debits and credits *in each currency separately*. A 100 USD debit is never "balanced" by a 7,000 AFN credit.
2. **Exchange-position clearing account (3300).** An exchange moves value between currencies through 3300, so each currency balances on its own. The balance of 3300 per currency is the exchange's open currency position.
3. **No invented profit.** The difference between buy and sell rates stays in 3300. Revenue is recognized only for explicit fees (4100). Account 4200 (spread revenue) is reserved until the owner decides on a cost-basis method.
4. **Cash and balances are derived.** Cash per currency and every customer position are sums of journal lines. Nothing is stored twice.
5. **One unified cashbox.** All cash — the exchange's own capital and customer funds — is pooled in a single main cashbox (the first/seeded drawer, «صندوق اصلی»). There are no separate cash drawers: creating one is rejected (`cashbox.single`), postings naming another drawer are rejected (`cashbox.nonMainDrawer`), and schema v9 consolidates any legacy extra drawers into the main fund with dated transfer transactions before deactivating them. The **cashbox balance** of a currency is the total cash in the fund, and it is the absolute withdrawal limit: no withdrawal (برد, expense, cash-settled exchange payout, negative cash adjustment, reversal/correction net effect, or client-debt opening) may exceed it — e.g. AFN 21,000 cannot leave a cashbox holding AFN 20,000. This limit has no settings override.
6. **Corrections by reversal or adjustment.** A reversal mirrors every line of the original. Adjustments require a reason and a permission.

## Chart of accounts

| Code | Name | Type | Normal side | Role |
|---|---|---|---|---|
| 1000 | دارایی‌ها | asset | debit | control |
| 1100 | صندوق‌ها | asset | debit | control |
| 1101 | صندوق اصلی (the single main cashbox account) | asset | debit | cash |
| 2000 | بدهی‌ها | liability | credit | control |
| 2100 | حسابات مشتریان (one sub-account per customer, created with the customer) | liability | credit | control / customer |
| 3000 | سرمایه | equity | credit | control |
| 3100 | سرمایه اولیه صرافی | equity | credit | openingEquity |
| 3200 | اصلاحات مالی مجاز | equity | credit | adjustment |
| 3300 | موقعیت ارزی (حساب تبادله) | clearing | credit | exchangePosition |
| 4000 | عواید | revenue | credit | control |
| 4100 | کمیشن و فیس تبادله | revenue | credit | feeRevenue |
| 4200 | عواید تفاوت نرخ (رزرو) | revenue | credit | spreadRevenue (unused) |
| 5000 | مصارف | expense | debit | control |
| 5100 | مصارف عملیاتی | expense | debit | operatingExpense |
| 5200 | کسر و اضافه صندوق | expense | debit | cashOverShort |

Accounts are multi-currency: a line carries its own currency, and balances are always reported per currency.

## Sign conventions

- **Customer position** = credits − debits on the customer's account. **Positive means the exchange owes the customer** (طلب مشتری); negative means the customer owes the exchange (بدهی مشتری).
- **Cash (cashbox balance)** = debits − credits on the main cashbox account, i.e. the total pooled cash per currency.

## Rate convention

`1 base = R quote`, `quote amount = base amount × R`, rounded to the quote currency's precision with the quote currency's rounding mode. Each pair has a **buy** rate (the exchange buys base) and a **sell** rate (the exchange sells base). Rates are entered by the user and stored as history; nothing is hardcoded.

## Posting rules

Notation: `Dr account  currency  amount`. "Cash" is the single main cashbox account; "Customer" is the selected customer's account.

### Receipt (رسید): the customer hands money to the exchange

| | Account | Currency | Amount |
|---|---|---|---|
| Dr | Cash | C | A |
| Cr | Customer | C | A |

The customer's position rises by A (the exchange owes more). Not allowed for the walk-in customer.

### Payment (برد): the exchange pays the customer

| | Account | Currency | Amount |
|---|---|---|---|
| Dr | Customer | C | A |
| Cr | Cash | C | A |

### Buy (خرید): the exchange buys B units of base at rate R and gives Q = B × R of quote

| | Account | Currency | Amount |
|---|---|---|---|
| Dr | Base settlement (Cash or Customer) | base | B |
| Cr | 3300 Exchange position | base | B |
| Dr | 3300 Exchange position | quote | Q |
| Cr | Quote settlement (Cash or Customer) | quote | Q |

### Sell (فروش): the exchange sells B units of base at rate R and receives Q = B × R of quote

| | Account | Currency | Amount |
|---|---|---|---|
| Dr | 3300 Exchange position | base | B |
| Cr | Base settlement | base | B |
| Dr | Quote settlement | quote | Q |
| Cr | 3300 Exchange position | quote | Q |

Settlement "Cash" moves the drawer. Settlement "Customer" moves the customer's account instead (for example, the customer leaves the bought amount on account). The walk-in customer can only use cash.

### Fee (optional, added to an exchange)

| | Account | Currency | Amount |
|---|---|---|---|
| Dr | Fee settlement (Cash or Customer) | F | fee |
| Cr | 4100 Fee revenue | F | fee |

### Opening cash (the initial capital, then later injections, in the main cashbox)

`Dr Cash / Cr 3100` in that currency.

### Opening customer balance (once per customer and currency)

Cashbox composition is derived per currency, never stored twice: **cashbox balance** = the total cash in the single main fund (own capital + customer funds pooled); **customer funds in the cashbox** = total customer liabilities (positive customer positions), the customers' informational share of the total; **the exchange's own share** = cashbox total − customer funds; **own capital** (net) = own share + customer receivables. The cashbox balance changes only when cash actually moves.

Initial capital (3100 سرمایه اولیه صرافی) is the exchange's **own** funds only and is posted exclusively by opening cash; customer opening balances never touch it (the old `Dr/Cr 3100` customer-opening rule posted client money through the capital account, which misstated initial capital). An opening customer balance records one customer's share of the main cashbox against cash, exactly like a receipt/payment:

Positive (exchange owes the customer — طلب مشتری, a customer liability): the customer's funds held with the exchange in the main cashbox: `Dr Cash / Cr Customer`. The cashbox total and the liability rise together; initial capital is unchanged.

Negative (customer owes the exchange — بدهی مشتری, a client debt): funds that were withdrawn / paid out or lent from the cashbox to the customer: `Dr Customer / Cr Cash`. The cashbox total falls. Because the exchange can only have paid out what the fund actually held, the posting is **verified against the cashbox**: it is rejected (`opening.debtExceedsAvailableFunds`) when the amount exceeds the current cashbox balance in that currency on the effective date — the pooled total, with no deduction for other customers' shares. The error states the requested amount and the cashbox balance and says the amount cannot exceed it. When the customer later pays, a receipt brings the cash back into the cashbox. Every other withdrawal is capped by the same total through the pooled negative-cash check (`cash.insufficient`), evaluated on the cashbox as a whole across all dates.

The two settlement flows are distinct. *Covering/settling a recorded liability without paying out* (e.g. reversing an erroneous opening liability) unwinds its entry: liability falls and the customer's share leaves the cashbox. *Paying out/returning funds to the customer* (برد: `Dr Customer / Cr Cash`) reduces the cashbox total and the liability together.

### Cash adjustment (reconciliation difference)

Surplus: `Dr Cash / Cr 5200`. Shortage: `Dr 5200 / Cr Cash`. Requires a reason and `adjustments.post`.

### Customer adjustment

Increase position: `Dr 3200 / Cr Customer`. Decrease: `Dr Customer / Cr 3200`. Requires a reason.

### Expense

`Dr 5100 / Cr Cash` with a required description.

### Reversal

A new transaction of type `reversal` whose journal swaps debit and credit on every line of the original, dated today by default (the original's date is never rewritten). A reason is required. The original becomes `reversed`. A transaction can be reversed once, and a reversal cannot itself be reversed. Reversing an opening balance frees the slot so it can be entered again.

## Worked example (mandatory scenario)

Opening cash AFN 100,000 and USD 2,000, plus customer K's opening debt of 800 (paid out of the vault, so AFN cash starts at 99,200). The four transactions of section 24 lead to **AFN 96,550 and USD 2,050** in every view (dashboard, cash report, trial balance, journal sums). After reversing transaction B, every view shows **AFN 93,000 and USD 2,100**. See `test/integration/end_to_end_scenario_test.dart`.

## Reconciliation

For a drawer, currency, and business date:

- opening = cash balance at the end of the previous day
- inflow / outflow = debits / credits on the cash account that day
- **expected = opening + inflow − outflow**
- **difference = counted − expected**

A difference is kept on the record and changes nothing by itself. It is corrected only by posting a cash adjustment (5200), which needs `adjustments.post`. Closing is refused if transactions changed after the count. A closed day locks postings and reversals dated on or before it for that drawer and currency, while other currencies stay open. Reopening needs `reconciliation.reopen` and a reason.

## Reports

All reports are per currency; amounts in different currencies are never added together.

| Report | Source |
|---|---|
| Position | Cash, customer liabilities, customer receivables, net, exchange position as of a date |
| Daily | Cash movement per drawer/currency and a count per transaction type |
| Customer balances | Customer × currency matrix |
| Exchange activity | Count, base and quote volumes, and lowest/highest rate per pair and type (no averaged "profit") |
| Trial balance | Debit/credit totals per account and currency with a balanced check |
| Income and expense | 4xxx and 5xxx accounts over a range |
| General ledger | Lines of one account with running balance |
| Reconciliation history | Records with differences and adjustments |
