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

-- The daily challenge: one row per day and player, their best game of that day.
CREATE TABLE IF NOT EXISTS daily (
  day TEXT NOT NULL,             -- YYYY-MM-DD, Italian time (the game decides it)
  player TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  score INTEGER NOT NULL,
  level INTEGER NOT NULL,
  scored_at INTEGER NOT NULL,
  touched_at INTEGER NOT NULL,
  PRIMARY KEY (day, player)
);
CREATE INDEX IF NOT EXISTS daily_rank ON daily (day, score DESC, scored_at ASC);

-- The 60-second mode: one row per player, like players.
CREATE TABLE IF NOT EXISTS sprint (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  score INTEGER NOT NULL,
  level INTEGER NOT NULL,
  scored_at INTEGER NOT NULL,
  touched_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sprint_rank ON sprint (score DESC, scored_at ASC);

-- The hardcore mode: one row per player, like players.
CREATE TABLE IF NOT EXISTS hardcore (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  score INTEGER NOT NULL,
  level INTEGER NOT NULL,
  scored_at INTEGER NOT NULL,
  touched_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS hardcore_rank ON hardcore (score DESC, scored_at ASC);

-- Friends: every player's public code and current name, and who is friends with whom (both ways).
CREATE TABLE IF NOT EXISTS profiles (
  player TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,     -- 8 characters, shared to be added as a friend
  name TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  touched_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS friends (
  player TEXT NOT NULL,
  friend TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (player, friend)
);

-- Duels: a classic game (its seed and the score at every second) that friends play against.
CREATE TABLE IF NOT EXISTS duels (
  id TEXT PRIMARY KEY,           -- 8 characters, in the invite link
  seed TEXT NOT NULL,
  owner TEXT NOT NULL,
  score INTEGER NOT NULL,
  level INTEGER NOT NULL,
  hits INTEGER NOT NULL,
  duration REAL NOT NULL,
  ghost TEXT NOT NULL,           -- JSON array: the score at each second of play
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS duels_owner ON duels (owner, created_at);
CREATE TABLE IF NOT EXISTS duel_results (
  duel TEXT NOT NULL,
  player TEXT NOT NULL,
  score INTEGER NOT NULL,
  level INTEGER NOT NULL,
  hits INTEGER NOT NULL,
  duration REAL NOT NULL,
  ghost TEXT NOT NULL,
  played_at INTEGER NOT NULL,
  PRIMARY KEY (duel, player)
);
CREATE INDEX IF NOT EXISTS duel_results_player ON duel_results (player);
