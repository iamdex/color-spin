// Color Spin global leaderboard: a Cloudflare Worker on a D1 database.
//
//   GET  /v1/scores?player=<id>  -> { top, me }
//   POST /v1/scores  { player, name, score, level, duration }  -> { top, me }
//
// `top` is the best TOP_SIZE players as [{ name, score, level, you? }] and `me`
// is { rank, name, score, level } for the asking player, or null. Player ids
// are never sent back: a player id is what allows writing to that row.
// A POST keeps the player's best score and always updates their name.

const TOP_SIZE = 10;
const NAME_MAX = 14;           // same as the name field in the game
const POINTS_PER_LEVEL = 10;   // same rule as the game: a level every 10 points
const MAX_SCORE = 100000;
// At most one ball every 0.5 s reaches the shape, so a game can't score faster
// than this (a little slack for rounding and the first ball).
const MAX_POINTS_PER_SECOND = 2;
const MIN_WRITE_GAP = 2000;    // ms between writes from the same player

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...CORS },
});
const fail = (status, error) => json({ error }, status);

const validPlayer = id => typeof id === 'string' && /^[0-9a-f]{32}$/.test(id);

// Printable text only, single spaces, at most NAME_MAX characters.
function cleanName(name) {
  if (typeof name !== 'string') return '';
  const s = name.normalize('NFC').replace(/[\p{C}]/gu, '').replace(/\s+/g, ' ').trim();
  return [...s].slice(0, NAME_MAX).join('').trim();
}

async function board(db, player) {
  const { results } = await db.prepare(
    'SELECT id, name, score, level FROM players ORDER BY score DESC, scored_at ASC LIMIT ?'
  ).bind(TOP_SIZE).all();
  const top = results.map(r => ({ name: r.name, score: r.score, level: r.level, ...(r.id === player ? { you: true } : {}) }));
  let me = null;
  if (player) {
    const row = await db.prepare('SELECT name, score, level, scored_at FROM players WHERE id = ?').bind(player).first();
    if (row) {
      const { above } = await db.prepare(
        'SELECT COUNT(*) AS above FROM players WHERE score > ?1 OR (score = ?1 AND scored_at < ?2)'
      ).bind(row.score, row.scored_at).first();
      me = { rank: above + 1, name: row.name, score: row.score, level: row.level };
    }
  }
  return { top, me };
}

async function submit(db, body) {
  const { player, score, level, duration } = body;
  if (!validPlayer(player)) return fail(400, 'bad player');
  if (!Number.isInteger(score) || score < 0 || score > MAX_SCORE) return fail(400, 'bad score');
  if (level !== 1 + Math.floor(score / POINTS_PER_LEVEL)) return fail(400, 'bad level');
  if (typeof duration !== 'number' || !(duration >= 0) || score > duration * MAX_POINTS_PER_SECOND + 3) {
    return fail(400, 'too fast');
  }
  const name = cleanName(body.name), now = Date.now();
  const row = await db.prepare('SELECT score, touched_at FROM players WHERE id = ?').bind(player).first();
  if (row && now - row.touched_at < MIN_WRITE_GAP) return fail(429, 'slow down');
  if (!row) {
    // A player joins the board with their first game that scores.
    if (score > 0) {
      await db.prepare(
        'INSERT INTO players (id, name, score, level, scored_at, touched_at) VALUES (?1, ?2, ?3, ?4, ?5, ?5)'
      ).bind(player, name, score, level, now).run();
    }
  } else if (score > row.score) {
    await db.prepare('UPDATE players SET name = ?2, score = ?3, level = ?4, scored_at = ?5, touched_at = ?5 WHERE id = ?1')
      .bind(player, name, score, level, now).run();
  } else {
    await db.prepare('UPDATE players SET name = ?2, touched_at = ?3 WHERE id = ?1').bind(player, name, now).run();
  }
  return json(await board(db, player));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    if (url.pathname !== '/v1/scores') return fail(404, 'not found');
    try {
      if (request.method === 'GET') {
        const player = url.searchParams.get('player');
        return json(await board(env.DB, validPlayer(player) ? player : null));
      }
      if (request.method === 'POST') {
        let body;
        try { body = await request.json(); } catch { return fail(400, 'bad json'); }
        if (!body || typeof body !== 'object') return fail(400, 'bad json');
        return await submit(env.DB, body);
      }
      return fail(405, 'method not allowed');
    } catch (e) {
      console.error(e);
      return fail(500, 'server error');
    }
  },
};
