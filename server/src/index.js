// Color Spin global leaderboard: a Cloudflare Worker on a D1 database.
//
//   GET  /v1/scores?player=<id>  -> { top, me }
//   POST /v1/scores  { player, name, score, level, hits, duration }  -> { top, me }
//   GET  /v1/daily?day=<YYYY-MM-DD>&player=<id>  -> { day, top, me, players }
//   POST /v1/daily   { player, name, day, score, level, hits, duration }  -> { day, top, me, players }
//   GET  /v1/sprint?player=<id>  -> { top, me, players }
//   POST /v1/sprint  { player, name, score, level, hits, duration }  -> { top, me, players }
//   /v1/hardcore: same as /v1/sprint
//
// `top` is the best TOP_SIZE players as [{ name, score, level, you? }] and `me`
// is { rank, name, score, level } for the asking player, or null. Player ids
// are never sent back: a player id is what allows writing to that row.
// A POST keeps the player's best score and always updates their name.
// /v1/daily is the same board for one day of the daily challenge, /v1/sprint
// and /v1/hardcore the ones of those modes. Friends and duels are in social.js.

import { isOffensive } from './names.js';
import { social } from './social.js';

const TOP_SIZE = 10;
const NAME_MAX = 14;           // same as the name field in the game
const POINTS_PER_LEVEL = 10;   // same rule as the game: a level every 10 balls hit
// Since 1.3 a hit is worth up to x4 (combo), and x3 more for a rainbow ball.
const MAX_POINTS_PER_HIT = 4 * 3;
const MAX_SCORE = 100000;
// At most one ball every 0.5 s reaches the shape, so a game can't hit faster
// than this (a little slack for rounding and the first ball).
const MAX_POINTS_PER_SECOND = 2;
const MIN_WRITE_GAP = 2000;    // ms between writes from the same player
const DAY_MS = 86400000;

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
// The game's day is Italian time; accept the UTC day and its neighbours.
const validDay = day => typeof day === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(day) &&
  Math.abs(Date.parse(day) - Date.parse(new Date().toISOString().slice(0, 10))) <= DAY_MS;

// Printable text only, single spaces, at most NAME_MAX characters. An
// offensive name is dropped: the game then shows the player as "Player".
function cleanName(name) {
  if (typeof name !== 'string') return '';
  const s = name.normalize('NFC').replace(/[\p{C}]/gu, '').replace(/\s+/g, ' ').trim();
  const clean = [...s].slice(0, NAME_MAX).join('').trim();
  return isOffensive(clean) ? '' : clean;
}

// The boards: all-time, 60 seconds and hardcore (one row per player), daily (one per day and player).
const BOARDS = {
  scores: { table: 'players', id: 'id', where: '', args: () => [] },
  sprint: { table: 'sprint', id: 'id', where: '', args: () => [] },
  hardcore: { table: 'hardcore', id: 'id', where: '', args: () => [] },
  daily: { table: 'daily', id: 'player', where: 'day = ? AND', args: body => [body.day] },
};

async function board(db, kind, player, body) {
  const { table, id, where, args } = BOARDS[kind];
  const { results } = await db.prepare(
    `SELECT ${id} AS id, name, score, level FROM ${table} WHERE ${where} 1 ORDER BY score DESC, scored_at ASC LIMIT ?`
  ).bind(...args(body), TOP_SIZE).all();
  const top = results.map(r => ({ name: r.name, score: r.score, level: r.level, ...(r.id === player ? { you: true } : {}) }));
  let me = null;
  if (player) {
    const row = await db.prepare(`SELECT name, score, level, scored_at FROM ${table} WHERE ${where} ${id} = ?`)
      .bind(...args(body), player).first();
    if (row) {
      const { above } = await db.prepare(
        `SELECT COUNT(*) AS above FROM ${table} WHERE ${where} (score > ? OR (score = ? AND scored_at < ?))`
      ).bind(...args(body), row.score, row.score, row.scored_at).first();
      me = { rank: above + 1, name: row.name, score: row.score, level: row.level };
    }
  }
  if (kind === 'scores') return { top, me };
  const { players } = await db.prepare(`SELECT COUNT(*) AS players FROM ${table} WHERE ${where} 1`).bind(...args(body)).first();
  return kind === 'daily' ? { day: body.day, top, me, players } : { top, me, players };
}

// The same rules the game follows; see the constants above.
function checkGame({ score, level, duration, ...body }) {
  // Up to 1.2 every hit was one point, and those apps don't send hits.
  const hits = body.hits ?? score;
  if (!Number.isInteger(score) || score < 0 || score > MAX_SCORE) return 'bad score';
  if (!Number.isInteger(hits) || hits < 0 || hits > score || score > hits * MAX_POINTS_PER_HIT) return 'bad hits';
  if (level !== 1 + Math.floor(hits / POINTS_PER_LEVEL)) return 'bad level';
  if (typeof duration !== 'number' || !(duration >= 0) || hits > duration * MAX_POINTS_PER_SECOND + 3) return 'too fast';
  return null;
}

async function submit(db, kind, body) {
  const { player, score, level } = body;
  if (!validPlayer(player)) return fail(400, 'bad player');
  if (kind === 'daily' && !validDay(body.day)) return fail(400, 'bad day');
  const error = checkGame(body);
  if (error) return fail(400, error);
  const { table, id, where, args } = BOARDS[kind];
  const name = cleanName(body.name), now = Date.now(), key = [...args(body), player];
  const row = await db.prepare(`SELECT score, touched_at FROM ${table} WHERE ${where} ${id} = ?`).bind(...key).first();
  if (row && now - row.touched_at < MIN_WRITE_GAP) return fail(429, 'slow down');
  if (!row) {
    // A player joins the board with their first game that scores.
    if (score > 0) {
      const cols = kind === 'daily' ? 'day, player' : 'id';
      await db.prepare(
        `INSERT INTO ${table} (${cols}, name, score, level, scored_at, touched_at) VALUES (${key.map(() => '?').join(', ')}, ?, ?, ?, ?, ?)`
      ).bind(...key, name, score, level, now, now).run();
    }
  } else if (score > row.score) {
    await db.prepare(`UPDATE ${table} SET name = ?, score = ?, level = ?, scored_at = ?, touched_at = ? WHERE ${where} ${id} = ?`)
      .bind(name, score, level, now, now, ...key).run();
  } else {
    await db.prepare(`UPDATE ${table} SET name = ?, touched_at = ? WHERE ${where} ${id} = ?`).bind(name, now, ...key).run();
  }
  // One name everywhere: a new name also shows on the mode boards and the recent daily ones.
  if (kind === 'scores') {
    const since = new Date(now - 2 * DAY_MS).toISOString().slice(0, 10);
    await db.batch([
      db.prepare('UPDATE daily SET name = ? WHERE player = ? AND day >= ?').bind(name, player, since),
      db.prepare('UPDATE sprint SET name = ? WHERE id = ?').bind(name, player),
      db.prepare('UPDATE hardcore SET name = ? WHERE id = ?').bind(name, player),
      db.prepare('UPDATE profiles SET name = ? WHERE player = ?').bind(name, player),
    ]);
  }
  return json(await board(db, kind, player, body));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const kind = { '/v1/scores': 'scores', '/v1/daily': 'daily', '/v1/sprint': 'sprint', '/v1/hardcore': 'hardcore' }[url.pathname];
    try {
      if (!kind) {
        if (/^\/v1\/(profile|friends|duels)(\/|$)/.test(url.pathname)) {
          return await social(request, url, env, { json, fail, cleanName, checkGame, validPlayer, validDay });
        }
        return fail(404, 'not found');
      }
      if (request.method === 'GET') {
        const player = url.searchParams.get('player'), day = url.searchParams.get('day');
        if (kind === 'daily' && !validDay(day)) return fail(400, 'bad day');
        return json(await board(env.DB, kind, validPlayer(player) ? player : null, { day }));
      }
      if (request.method === 'POST') {
        let body;
        try { body = await request.json(); } catch { return fail(400, 'bad json'); }
        if (!body || typeof body !== 'object') return fail(400, 'bad json');
        return await submit(env.DB, kind, body);
      }
      return fail(405, 'method not allowed');
    } catch (e) {
      console.error(e);
      return fail(500, 'server error');
    }
  },
};
