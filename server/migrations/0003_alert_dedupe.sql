-- Task 6 (#7): "同じ送り主やドメインの知らせは1時間に1回にまとめる" (docs/design.md, データの扱い).
-- To hold back a notification, the judge needs to know who sent the recent alerts and which of them
-- were notified. The sender and the domain are kept only as SHA-256 hex of the family id and the
-- normalized value, so the alert row does not hold the sender's number or address in plain text.
-- They go away with the alert row (30-day cleanup and "delete everything").

ALTER TABLE alerts ADD COLUMN sender_key TEXT;
ALTER TABLE alerts ADD COLUMN domain_key TEXT;
-- 1 when the mother and the family were sent a push for this alert.
ALTER TABLE alerts ADD COLUMN notified INTEGER NOT NULL DEFAULT 0 CHECK (notified IN (0, 1));
