-- What the AI last told the protected person in this case, shown on the family's card
-- ("AI が母に何と答えたか" in docs/design.md). Written only while the case is still 'notified',
-- in the same statement that checks the state, so an answer that arrives after a family member
-- accepted is never recorded or shown (src/cases.ts, deliverAiReply).
ALTER TABLE cases ADD COLUMN ai_reply TEXT;
