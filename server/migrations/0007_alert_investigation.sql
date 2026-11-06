-- Task 11 (#12): the research in the background ("怪しいものを見つけたら、Managed Agents に裏で調べさせる",
-- docs/design.md). The received text is not kept in D1, so the session gets it when it starts, from the
-- judge queue (src/judge.ts); only what the session found comes back here.
--
-- investigation_session_id: the Managed Agents session that researches this alert. NULL before one was
-- started, and again once the session was deleted after its result was read (src/agents.ts). Sessions
-- left behind are deleted with "delete everything" and the 30-day cleanup, like cases.agent_session_id.
-- investigated_at: when the result was read (or given up on). NULL while the session is still out, so
-- the 5-minute tick and the webhook both look only at those, and the second of them writes nothing.
-- evidence: a JSON array of { text, url }, the official pages the session found, shown on the family's
-- card. NULL until the result is read.
ALTER TABLE alerts ADD COLUMN investigation_session_id TEXT;
ALTER TABLE alerts ADD COLUMN investigated_at INTEGER;
ALTER TABLE alerts ADD COLUMN evidence TEXT;
CREATE INDEX alerts_investigation ON alerts (investigation_session_id);

-- The agent and the environment are made once by the Worker the first time they are needed, and their
-- ids are kept here under a name that carries the configuration's version ("research-agent-v1"). A new
-- version of the prompt or the host list is a new name, so a new resource; nothing is updated in place.
CREATE TABLE agent_resources (
  name TEXT PRIMARY KEY,
  id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
