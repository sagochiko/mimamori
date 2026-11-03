-- The tables from "D1 の表" in docs/plan.md.
-- Times are Unix epoch milliseconds (INTEGER). IDs are UUID text.
-- No foreign keys: "delete everything" and the 30-day cleanup delete rows table by table in a
-- fixed order (src/families.ts, src/retention.ts), so a missing parent never blocks a delete.

CREATE TABLE families (
  id TEXT PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,          -- familyToken, the path segment of /sms/ and /dns-query/
  created_at INTEGER NOT NULL
);

CREATE TABLE members (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('protected', 'family')),
  display_name TEXT NOT NULL,
  device_key_hash TEXT NOT NULL UNIQUE, -- SHA-256 hex of deviceKey; the key itself is never stored
  apns_token TEXT,
  apns_env TEXT CHECK (apns_env IN ('sandbox', 'production')),
  created_at INTEGER NOT NULL
);
CREATE INDEX members_family ON members (family_id);

CREATE TABLE invites (
  code TEXT PRIMARY KEY CHECK (length(code) = 6),
  family_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);
CREATE INDEX invites_family ON invites (family_id);

CREATE TABLE alerts (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  source TEXT NOT NULL CHECK (source IN ('sms', 'gmail', 'dns', 'page', 'call', 'consult')),
  level INTEGER NOT NULL CHECK (level IN (1, 2, 3)),
  reasons TEXT NOT NULL DEFAULT '[]',  -- JSON array of strings
  summary TEXT NOT NULL DEFAULT '',
  rule_level INTEGER CHECK (rule_level IN (1, 2, 3)),
  claude_level INTEGER CHECK (claude_level IN (1, 2, 3)),
  created_at INTEGER NOT NULL
);
CREATE INDEX alerts_family_created ON alerts (family_id, created_at);
CREATE INDEX alerts_created ON alerts (created_at);

CREATE TABLE cases (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  alert_id TEXT,
  state TEXT NOT NULL CHECK (state IN ('notified', 'accepted', 'resolved')),
  assignee_member_id TEXT,
  agent_session_id TEXT,               -- Managed Agents session, deleted with "delete everything"
  notified_at INTEGER NOT NULL,
  accepted_at INTEGER,
  resolved_at INTEGER,
  renotified_at INTEGER
);
CREATE INDEX cases_family ON cases (family_id);
CREATE INDEX cases_notified ON cases (notified_at);

CREATE TABLE relays (
  id TEXT PRIMARY KEY,
  case_id TEXT NOT NULL,
  from_member_id TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX relays_case ON relays (case_id);

CREATE TABLE smiles (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  member_id TEXT NOT NULL,
  r2_key TEXT NOT NULL,                -- starts with "<family_id>/"
  score REAL,
  created_at INTEGER NOT NULL
);
CREATE INDEX smiles_family ON smiles (family_id);
CREATE INDEX smiles_created ON smiles (created_at);

CREATE TABLE gmail_auth (
  family_id TEXT PRIMARY KEY,
  refresh_token_enc TEXT NOT NULL,     -- sealed with src/secretbox.ts (AES-GCM, TOKEN_ENC_KEY)
  granted_at INTEGER NOT NULL,
  last_history_id TEXT,
  expired_notified_at INTEGER
);

CREATE TABLE usage_daily (
  date TEXT PRIMARY KEY,               -- YYYY-MM-DD in JST
  doh_requests INTEGER NOT NULL DEFAULT 0
);
