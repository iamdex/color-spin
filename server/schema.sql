-- One row per player (a random id kept on the device): their best game and their name.
CREATE TABLE IF NOT EXISTS players (
  id TEXT PRIMARY KEY,           -- 32 hex chars; also the key that lets the device write its row
  name TEXT NOT NULL DEFAULT '',
  score INTEGER NOT NULL,
  level INTEGER NOT NULL,
  scored_at INTEGER NOT NULL,    -- when the best score was set (ms); ties go to whoever got there first
  touched_at INTEGER NOT NULL    -- last write (ms), for the rate limit
);
CREATE INDEX IF NOT EXISTS players_rank ON players (score DESC, scored_at ASC);
