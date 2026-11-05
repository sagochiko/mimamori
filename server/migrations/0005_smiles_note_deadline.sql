-- Task 13 "毎朝の笑顔" (#14).
-- smiles.note: a family member's one-line reply. A reply can come without a photo; such a row has
-- r2_key = '' (the column is NOT NULL, and rebuilding the table would mean a DROP on the production
-- D1). "Delete everything" and the 30-day cleanup skip the empty key when they delete from R2
-- (src/families.ts, src/retention.ts) and delete the row like any other.
ALTER TABLE smiles ADD COLUMN note TEXT;

-- The hour (JST, 5 to 12) by which the protected member's smile is expected. After it, with no smile
-- from her that JST day, the family gets one quiet notice (src/smiles.ts, notifyMissedSmiles).
ALTER TABLE families ADD COLUMN smile_deadline_hour INTEGER NOT NULL DEFAULT 9
  CHECK (smile_deadline_hour BETWEEN 5 AND 12);

-- The JST date (YYYY-MM-DD) the notice was last claimed for, so it goes at most once a day.
ALTER TABLE families ADD COLUMN smile_missed_notified_on TEXT;
