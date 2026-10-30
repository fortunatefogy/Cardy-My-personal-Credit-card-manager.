-- Private, on-device SQLite schema. No account or server is required.
CREATE TABLE cards (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  bank TEXT NOT NULL,
  name TEXT NOT NULL,
  network TEXT NOT NULL,
  nickname TEXT NOT NULL DEFAULT '',
  annual_fee REAL NOT NULL DEFAULT 0,
  cashback REAL NOT NULL DEFAULT 0,
  reward_rate REAL NOT NULL DEFAULT 0,
  point_value REAL NOT NULL DEFAULT 0,
  categories TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  rewards_stack INTEGER NOT NULL DEFAULT 0 CHECK (rewards_stack IN (0, 1))
);

CREATE TABLE offers (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  title TEXT NOT NULL,
  merchant TEXT NOT NULL,
  bank TEXT NOT NULL,
  payment_method TEXT NOT NULL,
  discount_type TEXT NOT NULL,
  description TEXT NOT NULL,
  source_name TEXT NOT NULL,
  source_url TEXT NOT NULL,
  details_url TEXT NOT NULL,
  checked_at INTEGER NOT NULL,
  discount_percent REAL,
  max_discount REAL,
  min_spend REAL,
  expires_at INTEGER,
  coupon_code TEXT,
  exclusions TEXT,
  category TEXT,
  eligible_variants TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'active'
);

CREATE INDEX offers_status_expiry ON offers(status, expires_at);
CREATE INDEX offers_merchant ON offers(merchant);

CREATE TABLE offer_source_status (
  source_id TEXT PRIMARY KEY,
  source_name TEXT NOT NULL,
  last_checked INTEGER,
  last_success INTEGER,
  last_error TEXT,
  offer_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE card_catalogue (
  slug TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  bank TEXT NOT NULL DEFAULT '',
  detail_url TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '',
  summary TEXT NOT NULL DEFAULT '',
  details_json TEXT NOT NULL DEFAULT '{}',
  checked_at INTEGER NOT NULL,
  details_checked_at INTEGER
);
