-- #174: the Gmail watch remembers, across ticks, the mails it already handled in a history record it
-- stopped in the middle of (a failed queue send, the per-tick cap, the budget). last_history_id moves
-- only past whole records, so without this the next tick queued those mails a second time.
-- partial_record_id: the history record id the last tick stopped in, or NULL.
-- partial_message_ids: a JSON array of the message ids in that record already handled, or NULL.
ALTER TABLE gmail_auth ADD COLUMN partial_record_id TEXT;
ALTER TABLE gmail_auth ADD COLUMN partial_message_ids TEXT;
