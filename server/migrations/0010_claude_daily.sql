-- The public-release audit of 2026-11-07, point 1: anyone could make a family (POST /families had no
-- limit), join it as the mother, and call Claude through /consult and /page as often as they liked.
--
-- claude_daily: per family and JST day (YYYY-MM-DD, the day the family's clocks are read in), how many
-- times Claude was called (claude_calls: the consultation's two calls, every judgment on the judge
-- queue) and how many Managed Agents researches were started (research_starts). Past the caps in
-- src/claude-limit.ts the family is answered by the rules alone, as when Claude gives no answer.
-- Days before yesterday are deleted by the daily cleanup (src/retention.ts), and "すべて消す" deletes
-- the family's rows.
CREATE TABLE claude_daily (
  family_id TEXT NOT NULL,
  day TEXT NOT NULL,
  claude_calls INTEGER NOT NULL,
  research_starts INTEGER NOT NULL,
  PRIMARY KEY (family_id, day)
);

-- family_attempts: tries at POST /families per client address, the same shape as join_attempts
-- (0009): key is an HMAC of the address group under its own key derived from TOKEN_ENC_KEY
-- (src/family-limit.ts), never the address. window_start begins the current one-hour window, count is
-- the tries in it. Rows older than a day are deleted by the daily cleanup.
CREATE TABLE family_attempts (
  key TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);
