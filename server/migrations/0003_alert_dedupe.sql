-- Task 6 (#7): "同じ送り主やドメインの知らせは1時間に1回にまとめる" (docs/design.md, データの扱い),
-- and a notice that did not get through is sent again when the queue retries the message.
--
-- To hold back a notification, the judge needs to know who sent the recent alerts and which of them
-- were notified. The sender's number or address is kept only as SHA-256 hex of the family id and the
-- normalized value, never in plain text. The domain is hashed the same way in domain_key, but it is
-- also in summary as it stands, since the family's card shows where the message points to.
-- They go away with the alert row (30-day cleanup and "delete everything").

ALTER TABLE alerts ADD COLUMN sender_key TEXT;
ALTER TABLE alerts ADD COLUMN domain_key TEXT;
-- 1 when this alert is one the mother and the family are told about: level 1 or 2, and not held
-- back by the one-an-hour rule. Set when the row is written, before anything is sent.
ALTER TABLE alerts ADD COLUMN notified INTEGER NOT NULL DEFAULT 0 CHECK (notified IN (0, 1));
-- When the mother's push reached at least one of her devices (or she has none to send to). NULL
-- while it has not: a retry of the same queue message sends it again, and only then.
ALTER TABLE alerts ADD COLUMN protected_notified_at INTEGER;
