-- #271: the family's summary of a consultation, from fixed choices (src/consult-summary.ts). A
-- Managed Agents session picks a topic and a next step through its own tool; only the keys are kept,
-- and GET /cases turns them into the fixed line. The session reuses investigation_session_id and
-- investigated_at (0007), so the 5-minute tick, the webhook, "delete everything", and the 30-day
-- cleanup handle it as they handle the research. Her words are not kept here.
--
-- summary_topic: a key of SUMMARY_TOPICS ("police", "money", ...), or NULL when there is none.
-- summary_step: a key of SUMMARY_STEPS ("call_now", "call_today"), or NULL. At level 1 the card
-- reads "call_now" whatever is stored.
ALTER TABLE alerts ADD COLUMN summary_topic TEXT;
ALTER TABLE alerts ADD COLUMN summary_step TEXT;
