-- Task 17 (#19): the watch checks itself ("見守りの自己点検" in docs/design.md).
-- The protected member's iPhone calls POST /heartbeat at least once a day (src/heartbeat.ts). The body
-- says only whether notifications and background refresh are on; free disk space is never sent.
--
-- heartbeat_at: when the server last got one (the server's clock, not the device's). NULL until the
-- first one, and a member with NULL is never "lapsed", so builds from before this change stay quiet.
-- heartbeat_lapse_notified_at: when the family was told "見守りが止まっています" for the current gap.
-- A new heartbeat sets it back to NULL, so the next gap is told once again.
-- notifications_off, background_refresh_off: 1 after the device said the setting is off and the family
-- was told, 0 after it said it is on again, NULL before it said anything. The family is told only
-- when one goes to 1.
ALTER TABLE members ADD COLUMN heartbeat_at INTEGER;
ALTER TABLE members ADD COLUMN heartbeat_lapse_notified_at INTEGER;
ALTER TABLE members ADD COLUMN notifications_off INTEGER;
ALTER TABLE members ADD COLUMN background_refresh_off INTEGER;
