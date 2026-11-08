-- #282: the family's settings screen. Each family member chooses whether to get the two smile notices:
-- smile_notify, a smile or a set word came from someone else in the family (src/smiles.ts, tellOthers);
-- smile_missed_notify, the protected member's smile has not come by the family's hour
-- (src/smiles.ts, notifyMissedSmiles). 1 is on, 0 is off. DEFAULT 1 keeps every member who joined
-- before this change getting both, as before. The hour itself stays one per family
-- (families.smile_deadline_hour). Notices of danger (SMS, Gmail, consultations), the watch's
-- self-check, and "(name) joined" never read these columns, so they cannot be turned off here.
ALTER TABLE members ADD COLUMN smile_notify INTEGER NOT NULL DEFAULT 1 CHECK (smile_notify IN (0, 1));
ALTER TABLE members ADD COLUMN smile_missed_notify INTEGER NOT NULL DEFAULT 1 CHECK (smile_missed_notify IN (0, 1));
