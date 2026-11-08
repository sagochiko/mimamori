-- #280: a family member removes a resolved card from the family's list (DELETE /cases/{id}), and it
-- goes from every family device. The row is kept with hidden_at set rather than deleted: the alert
-- stays (the one-an-hour rule, her recent findings, a research session read it), and a judge message
-- still being retried for that alert would see no case and open a new one, telling the family again
-- about something they settled. A kept row stops that, as a resolved one does (#49). The AI's answer
-- and the old relays go with the removal; the 30-day cleanup deletes the row as before.
--
-- hidden_at: when a family member removed the card, or NULL while it is listed. Only resolved cases
-- are hidden; every other reader of cases already leaves resolved ones alone.
ALTER TABLE cases ADD COLUMN hidden_at INTEGER;
