-- What the AI last told the protected person in this case, shown on the family's card
-- ("AI が母に何と答えたか" in docs/design.md). Written only while the case is still 'notified',
-- in the same statement that checks the state, so an answer that arrives after a family member
-- accepted is never recorded or shown (src/cases.ts, deliverAiReply).
ALTER TABLE cases ADD COLUMN ai_reply TEXT;

-- When the first notice reached at least one family member (or there was nobody to tell). NULL while
-- nobody has been told: openCase tells the family again on a retry, and the 5-minute tick retries it
-- for a day (src/cases.ts, sendFirstNotices). Cases from before this column count as told.
ALTER TABLE cases ADD COLUMN family_notified_at INTEGER;
UPDATE cases SET family_notified_at = notified_at;
