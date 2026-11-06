-- #67: tries at POST /invites/{code}/join, counted in D1 so "接続元ごとに60秒に5回まで" (docs/plan.md)
-- holds everywhere. The Rate Limiting binding (JOIN_LIMITER) counts per Cloudflare location and only
-- approximately, and in production it let 23 tries in a row through.
--
-- key: hex HMAC-SHA256 of the client address (an IPv6 address cut to its /48) under a key derived from
-- TOKEN_ENC_KEY with HKDF (src/join-limit.ts). The address itself is never stored.
-- window_start: when the current 60-second window began (ms). count: tries in that window.
-- Rows older than a day are deleted by the daily cleanup (src/retention.ts).
CREATE TABLE join_attempts (
  key TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);

-- join_daily: tries that wrote to join_attempts on one UTC day (day is YYYY-MM-DD), for all addresses
-- together. Past JOIN_WRITES_PER_DAY every join answers 429 until the next UTC day, so tries from many
-- addresses cannot spend the Free plan's daily row writes that the alerts, consultations, and smiles
-- need. Days before yesterday are deleted by the daily cleanup.
CREATE TABLE join_daily (
  day TEXT PRIMARY KEY,
  writes INTEGER NOT NULL
);
