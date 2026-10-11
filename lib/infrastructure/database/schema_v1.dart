/// Schema version 1 of the integrated Hadid Money Exchange database.
///
/// Conventions:
/// * Money columns are `*_minor INTEGER` (minor units of the row's currency).
/// * Rates are canonical decimal TEXT (exact, never REAL).
/// * Business dates are ISO `YYYY-MM-DD`; timestamps are UTC ISO-8601.
/// * Posted ledger rows are protected by triggers (no UPDATE / DELETE).
library;

const List<String> schemaV1 = [
  // ---------------------------------------------------------------- reference
  '''
  CREATE TABLE currencies (
    code TEXT PRIMARY KEY CHECK (length(code) BETWEEN 3 AND 8 AND code = upper(code)),
    name_fa TEXT NOT NULL,
    symbol TEXT NOT NULL,
    precision INTEGER NOT NULL CHECK (precision BETWEEN 0 AND 6),
    rate_scale INTEGER NOT NULL CHECK (rate_scale BETWEEN 0 AND 12),
    rounding TEXT NOT NULL DEFAULT 'halfUp'
      CHECK (rounding IN ('halfUp','halfEven','down','up')),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE application_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE sequences (
    name TEXT PRIMARY KEY,
    value INTEGER NOT NULL DEFAULT 0 CHECK (value >= 0)
  )
  ''',

  // ------------------------------------------------------------ security
  '''
  CREATE TABLE roles (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    name_fa TEXT NOT NULL,
    is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0,1))
  )
  ''',
  '''
  CREATE TABLE permissions (
    code TEXT PRIMARY KEY,
    description_fa TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE role_permissions (
    role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_code TEXT NOT NULL REFERENCES permissions(code) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_code)
  )
  ''',
  '''
  CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE COLLATE NOCASE,
    display_name TEXT NOT NULL,
    role_id INTEGER NOT NULL REFERENCES roles(id),
    password_hash TEXT,
    password_salt TEXT,
    password_iterations INTEGER,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    failed_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',

  // ------------------------------------------------------------ parties
  '''
  CREATE TABLE customers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    phone TEXT,
    id_document TEXT,
    address TEXT,
    notes TEXT,
    status TEXT NOT NULL DEFAULT 'active'
      CHECK (status IN ('active','inactive','anonymized')),
    is_walk_in INTEGER NOT NULL DEFAULT 0 CHECK (is_walk_in IN (0,1)),
    legacy_id TEXT UNIQUE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX ux_customers_walk_in ON customers(is_walk_in) WHERE is_walk_in = 1',
  'CREATE INDEX ix_customers_name ON customers(name COLLATE NOCASE)',
  'CREATE INDEX ix_customers_phone ON customers(phone)',

  '''
  CREATE TABLE cash_drawers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    name_fa TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at TEXT NOT NULL
  )
  ''',

  // ------------------------------------------------------- chart of accounts
  '''
  CREATE TABLE accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT NOT NULL UNIQUE,
    name_fa TEXT NOT NULL,
    type TEXT NOT NULL
      CHECK (type IN ('asset','liability','equity','revenue','expense','clearing')),
    normal_side TEXT NOT NULL CHECK (normal_side IN ('debit','credit')),
    role TEXT NOT NULL CHECK (role IN ('control','cash','customer','openingEquity',
      'exchangePosition','feeRevenue','spreadRevenue','operatingExpense',
      'cashOverShort','adjustment')),
    currency_code TEXT REFERENCES currencies(code),
    parent_id INTEGER REFERENCES accounts(id),
    customer_id INTEGER UNIQUE REFERENCES customers(id),
    drawer_id INTEGER UNIQUE REFERENCES cash_drawers(id),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0,1)),
    created_at TEXT NOT NULL,
    CHECK ((role = 'customer') = (customer_id IS NOT NULL)),
    CHECK ((role = 'cash') = (drawer_id IS NOT NULL))
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_accounts_singleton_role ON accounts(role)
    WHERE role NOT IN ('control','cash','customer')
  ''',

  // --------------------------------------------------------------- rates
  '''
  CREATE TABLE exchange_rates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    base_currency TEXT NOT NULL REFERENCES currencies(code),
    quote_currency TEXT NOT NULL REFERENCES currencies(code),
    buy_rate TEXT NOT NULL,
    sell_rate TEXT NOT NULL,
    convention TEXT NOT NULL DEFAULT 'BASE_TO_QUOTE',
    effective_at TEXT NOT NULL,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL,
    CHECK (base_currency <> quote_currency)
  )
  ''',
  'CREATE INDEX ix_rates_pair ON exchange_rates(base_currency, quote_currency, effective_at DESC, id DESC)',

  // --------------------------------------------------------- transactions
  '''
  CREATE TABLE transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT NOT NULL UNIQUE,
    reference_no TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL CHECK (type IN ('receipt','payment','buy','sell',
      'openingCash','openingCustomer','cashAdjustment','customerAdjustment',
      'expense','reversal')),
    status TEXT NOT NULL CHECK (status IN ('posted','reversed')),
    customer_id INTEGER REFERENCES customers(id),
    drawer_id INTEGER REFERENCES cash_drawers(id),
    effective_date TEXT NOT NULL
      CHECK (effective_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'),
    created_at TEXT NOT NULL,
    posted_at TEXT NOT NULL,
    created_by INTEGER NOT NULL REFERENCES users(id),
    description TEXT,
    source_currency TEXT REFERENCES currencies(code),
    source_amount_minor INTEGER CHECK (source_amount_minor IS NULL OR source_amount_minor > 0),
    dest_currency TEXT REFERENCES currencies(code),
    dest_amount_minor INTEGER CHECK (dest_amount_minor IS NULL OR dest_amount_minor > 0),
    rate TEXT,
    rate_convention TEXT,
    source_settlement TEXT CHECK (source_settlement IS NULL OR source_settlement IN ('cash','customer')),
    dest_settlement TEXT CHECK (dest_settlement IS NULL OR dest_settlement IN ('cash','customer')),
    fee_currency TEXT REFERENCES currencies(code),
    fee_amount_minor INTEGER CHECK (fee_amount_minor IS NULL OR fee_amount_minor > 0),
    fee_settlement TEXT CHECK (fee_settlement IS NULL OR fee_settlement IN ('cash','customer')),
    signed_amount_minor INTEGER,
    reverses_transaction_id INTEGER UNIQUE REFERENCES transactions(id),
    reversed_by_transaction_id INTEGER UNIQUE REFERENCES transactions(id),
    reason TEXT,
    idempotency_key TEXT NOT NULL UNIQUE,
    CHECK ((type = 'reversal') = (reverses_transaction_id IS NOT NULL)),
    CHECK (type NOT IN ('buy','sell') OR (rate IS NOT NULL AND source_currency IS NOT NULL
      AND dest_currency IS NOT NULL AND source_currency <> dest_currency))
  )
  ''',
  'CREATE INDEX ix_tx_effective ON transactions(effective_date, id)',
  'CREATE INDEX ix_tx_customer ON transactions(customer_id, effective_date)',
  'CREATE INDEX ix_tx_type ON transactions(type, effective_date)',
  'CREATE INDEX ix_tx_status ON transactions(status)',

  '''
  CREATE TABLE journal_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id),
    effective_date TEXT NOT NULL,
    posted_at TEXT NOT NULL,
    description TEXT
  )
  ''',
  '''
  CREATE TABLE journal_lines (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    journal_entry_id INTEGER NOT NULL REFERENCES journal_entries(id),
    line_no INTEGER NOT NULL,
    account_id INTEGER NOT NULL REFERENCES accounts(id),
    currency_code TEXT NOT NULL REFERENCES currencies(code),
    debit_minor INTEGER NOT NULL DEFAULT 0 CHECK (debit_minor >= 0),
    credit_minor INTEGER NOT NULL DEFAULT 0 CHECK (credit_minor >= 0),
    effective_date TEXT NOT NULL,
    memo TEXT,
    CHECK ((debit_minor > 0 AND credit_minor = 0) OR (credit_minor > 0 AND debit_minor = 0)),
    UNIQUE (journal_entry_id, line_no)
  )
  ''',
  'CREATE INDEX ix_lines_account ON journal_lines(account_id, currency_code, effective_date)',
  'CREATE INDEX ix_lines_currency ON journal_lines(currency_code, effective_date)',
  'CREATE INDEX ix_lines_entry ON journal_lines(journal_entry_id)',

  // ------------------------------------------------------ opening balances
  '''
  CREATE TABLE opening_balances (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL CHECK (kind IN ('cash','customer')),
    drawer_id INTEGER REFERENCES cash_drawers(id),
    customer_id INTEGER REFERENCES customers(id),
    currency_code TEXT NOT NULL REFERENCES currencies(code),
    signed_amount_minor INTEGER NOT NULL CHECK (signed_amount_minor <> 0),
    transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id),
    is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
    created_at TEXT NOT NULL,
    CHECK ((kind = 'cash') = (drawer_id IS NOT NULL)),
    CHECK ((kind = 'customer') = (customer_id IS NOT NULL))
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_opening_cash ON opening_balances(drawer_id, currency_code)
    WHERE kind = 'cash' AND is_active = 1
  ''',
  '''
  CREATE UNIQUE INDEX ux_opening_customer ON opening_balances(customer_id, currency_code)
    WHERE kind = 'customer' AND is_active = 1
  ''',

  // -------------------------------------------------------- reconciliation
  '''
  CREATE TABLE reconciliation_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    drawer_id INTEGER NOT NULL REFERENCES cash_drawers(id),
    currency_code TEXT NOT NULL REFERENCES currencies(code),
    business_date TEXT NOT NULL,
    opening_minor INTEGER NOT NULL,
    inflow_minor INTEGER NOT NULL CHECK (inflow_minor >= 0),
    outflow_minor INTEGER NOT NULL CHECK (outflow_minor >= 0),
    expected_minor INTEGER NOT NULL,
    counted_minor INTEGER NOT NULL,
    difference_minor INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('open','closed','void')),
    adjustment_transaction_id INTEGER REFERENCES transactions(id),
    notes TEXT,
    created_by INTEGER NOT NULL REFERENCES users(id),
    created_at TEXT NOT NULL,
    closed_by INTEGER REFERENCES users(id),
    closed_at TEXT,
    CHECK (expected_minor = opening_minor + inflow_minor - outflow_minor),
    CHECK (difference_minor = counted_minor - expected_minor)
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_reconciliation_scope
    ON reconciliation_records(drawer_id, currency_code, business_date)
    WHERE status <> 'void'
  ''',

  // ----------------------------------------------------------------- audit
  '''
  CREATE TABLE audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    occurred_at TEXT NOT NULL,
    actor_user_id INTEGER REFERENCES users(id),
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    transaction_id INTEGER REFERENCES transactions(id),
    outcome TEXT NOT NULL CHECK (outcome IN ('success','failure')),
    reason TEXT,
    before_json TEXT,
    after_json TEXT,
    message TEXT
  )
  ''',
  'CREATE INDEX ix_audit_time ON audit_logs(occurred_at)',
  'CREATE INDEX ix_audit_entity ON audit_logs(entity_type, entity_id)',

  // ---------------------------------------------------------------- backups
  '''
  CREATE TABLE backup_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL CHECK (kind IN ('manual','auto','pre_restore','pre_migration')),
    file_path TEXT NOT NULL,
    created_at TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    size_bytes INTEGER NOT NULL,
    sha256 TEXT NOT NULL
  )
  ''',

  // ------------------------------------------------------- legacy migration
  '''
  CREATE TABLE legacy_import_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_fingerprint TEXT NOT NULL,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    status TEXT NOT NULL CHECK (status IN ('running','verified','failed','rolled_back')),
    summary_json TEXT
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_legacy_verified_run ON legacy_import_runs(source_fingerprint)
    WHERE status = 'verified'
  ''',
  '''
  CREATE TABLE migration_issues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES legacy_import_runs(id),
    severity TEXT NOT NULL CHECK (severity IN ('info','warning','error')),
    code TEXT NOT NULL,
    source TEXT NOT NULL,
    source_ref TEXT,
    message TEXT NOT NULL,
    raw_json TEXT,
    created_at TEXT NOT NULL
  )
  ''',

  // ------------------------------------------------------ integrity triggers
  '''
  CREATE TRIGGER trg_journal_lines_no_update BEFORE UPDATE ON journal_lines
  BEGIN SELECT RAISE(ABORT, 'journal lines are immutable'); END
  ''',
  '''
  CREATE TRIGGER trg_journal_lines_no_delete BEFORE DELETE ON journal_lines
  BEGIN SELECT RAISE(ABORT, 'journal lines cannot be deleted'); END
  ''',
  '''
  CREATE TRIGGER trg_journal_entries_no_update BEFORE UPDATE ON journal_entries
  BEGIN SELECT RAISE(ABORT, 'journal entries are immutable'); END
  ''',
  '''
  CREATE TRIGGER trg_journal_entries_no_delete BEFORE DELETE ON journal_entries
  BEGIN SELECT RAISE(ABORT, 'journal entries cannot be deleted'); END
  ''',
  '''
  CREATE TRIGGER trg_transactions_no_delete BEFORE DELETE ON transactions
  BEGIN SELECT RAISE(ABORT, 'posted transactions cannot be deleted'); END
  ''',
  '''
  CREATE TRIGGER trg_transactions_only_reverse BEFORE UPDATE ON transactions
  WHEN NOT (
    OLD.status = 'posted' AND NEW.status = 'reversed'
    AND OLD.reversed_by_transaction_id IS NULL
    AND NEW.reversed_by_transaction_id IS NOT NULL
    AND NEW.id = OLD.id AND NEW.uuid = OLD.uuid
    AND NEW.reference_no = OLD.reference_no AND NEW.type = OLD.type
    AND NEW.customer_id IS OLD.customer_id AND NEW.drawer_id IS OLD.drawer_id
    AND NEW.effective_date = OLD.effective_date
    AND NEW.created_at = OLD.created_at AND NEW.posted_at = OLD.posted_at
    AND NEW.created_by = OLD.created_by AND NEW.description IS OLD.description
    AND NEW.source_currency IS OLD.source_currency
    AND NEW.source_amount_minor IS OLD.source_amount_minor
    AND NEW.dest_currency IS OLD.dest_currency
    AND NEW.dest_amount_minor IS OLD.dest_amount_minor
    AND NEW.rate IS OLD.rate
    AND NEW.fee_currency IS OLD.fee_currency
    AND NEW.fee_amount_minor IS OLD.fee_amount_minor
    AND NEW.signed_amount_minor IS OLD.signed_amount_minor
    AND NEW.reverses_transaction_id IS OLD.reverses_transaction_id
    AND NEW.idempotency_key = OLD.idempotency_key
  )
  BEGIN SELECT RAISE(ABORT, 'posted transactions are immutable'); END
  ''',
  '''
  CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON audit_logs
  BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END
  ''',
  '''
  CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON audit_logs
  BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END
  ''',
  '''
  CREATE TRIGGER trg_customers_no_delete BEFORE DELETE ON customers
  BEGIN SELECT RAISE(ABORT, 'customers cannot be deleted; deactivate instead'); END
  ''',
  '''
  CREATE TRIGGER trg_accounts_no_delete BEFORE DELETE ON accounts
  BEGIN SELECT RAISE(ABORT, 'accounts cannot be deleted; deactivate instead'); END
  ''',
  '''
  CREATE TRIGGER trg_accounts_identity BEFORE UPDATE ON accounts
  WHEN NEW.code <> OLD.code OR NEW.role <> OLD.role
    OR NEW.customer_id IS NOT OLD.customer_id OR NEW.drawer_id IS NOT OLD.drawer_id
    OR NEW.type <> OLD.type OR NEW.normal_side <> OLD.normal_side
  BEGIN SELECT RAISE(ABORT, 'account identity cannot change'); END
  ''',
  '''
  CREATE TRIGGER trg_currency_precision BEFORE UPDATE OF precision ON currencies
  WHEN NEW.precision <> OLD.precision
    AND EXISTS (SELECT 1 FROM journal_lines WHERE currency_code = OLD.code)
  BEGIN SELECT RAISE(ABORT, 'precision cannot change after postings exist'); END
  ''',
  '''
  CREATE TRIGGER trg_reconciliation_closed BEFORE UPDATE ON reconciliation_records
  WHEN OLD.status = 'closed' AND NOT (NEW.status = 'open'
    AND NEW.counted_minor = OLD.counted_minor
    AND NEW.expected_minor = OLD.expected_minor)
  BEGIN SELECT RAISE(ABORT, 'closed reconciliation can only be reopened'); END
  ''',
];
