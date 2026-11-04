-- The claim on sending a case's first notice to the family (#64). Set just before sending, so two
-- callers (the queue, a consultation, the 5-minute tick) never both send, and cleared again once the
-- notice reached a family device or none took it. family_notified_at keeps its meaning: when the
-- notice reached at least one family device, NULL until then. It is never set as the claim any more,
-- so nothing reads a notice still being sent as told (src/cases.ts, tellFamily). A claim older than
-- the claim's time limit is taken over by the next sender, so a Worker that stopped mid-send does not
-- keep the case from being told.
ALTER TABLE cases ADD COLUMN family_notice_claimed_at INTEGER;
