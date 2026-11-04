-- Die Ehrentafel (board/board.js). Applied with: npx wrangler d1 migrations apply knoedlinger-board --remote
-- (and knoedlinger-board-preview --remote --env preview for the previews' own board).
CREATE TABLE tickets (
	id TEXT PRIMARY KEY,
	mode TEXT NOT NULL,
	map TEXT NOT NULL,
	ip TEXT NOT NULL,
	created INTEGER NOT NULL,
	used INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX tickets_ip ON tickets (ip, created);
CREATE INDEX tickets_created ON tickets (created);

CREATE TABLE entries (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	mode TEXT NOT NULL,
	map TEXT NOT NULL,
	names TEXT NOT NULL,
	characters TEXT NOT NULL,
	result INTEGER NOT NULL,
	grant_level INTEGER NOT NULL,
	time INTEGER NOT NULL,
	level INTEGER NOT NULL,
	kills INTEGER NOT NULL,
	knodl INTEGER NOT NULL,
	players INTEGER NOT NULL,
	version TEXT NOT NULL,
	created INTEGER NOT NULL
);
CREATE INDEX entries_rank ON entries (mode, map, result DESC, grant_level DESC, time DESC, kills DESC);
CREATE INDEX entries_week ON entries (mode, map, created);
