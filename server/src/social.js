// Friends and duels.
//
//   POST /v1/profile         { player, name }         -> { code, name }
//   GET  /v1/friends?player=<id>&day=<YYYY-MM-DD>     -> { me, friends }
//   POST /v1/friends         { player, code }         -> { me, friends, added }
//   POST /v1/friends/remove  { player, code }         -> { me, friends }
//   POST /v1/duels           { player, seed, score, level, hits, duration, ghost } -> { id }
//   GET  /v1/duels?player=<id>                        -> { duels }   (mine and the ones I played)
//   GET  /v1/duels/<id>?player=<id>                   -> a duel
//   POST /v1/duels/<id>      { player, score, level, hits, duration, ghost } -> the duel
//   POST /v1/versus          { player, code }         -> { room }    (invites that friend)
//
// Every player has a public friend code (8 characters); the player id stays
// secret, since it is what allows writing. Friends see each other's name, best
// scores and today's daily challenge score. A duel is a classic game with its
// seed and its "ghost" (the score at every second of play): friends play the
// same sequence of balls against it.

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O, 1/I
const MAX_FRIENDS = 200;
const MAX_GHOST = 1800;        // samples, one per second of play
const DUELS_PER_MINUTE = 10;
const INVITE_LIFE = 3 * 60 * 1000; // a versus invite shows for 3 minutes

// The name only changes when one is sent.
const nameOf = (h, body) => typeof body.name === 'string' ? h.cleanName(body.name) : null;
const validCode = c => typeof c === 'string' && /^[A-Z2-9]{8}$/.test(c);
const validSeed = s => typeof s === 'string' && /^[a-z0-9]{6,16}$/.test(s);
function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  return Array.from(bytes, b => ALPHABET[b % ALPHABET.length]).join('');
}

// The score at every second: whole numbers that never go down or past the final score.
function validGhost(ghost, score, duration) {
  if (!Array.isArray(ghost) || ghost.length > MAX_GHOST || Math.abs(ghost.length - duration) > 3) return false;
  let prev = 0;
  for (const v of ghost) {
    if (!Number.isInteger(v) || v < prev || v > score) return false;
    prev = v;
  }
  return true;
}

// The player's profile, created with a fresh code when missing.
async function ensureProfile(db, player, name, now) {
  const row = await db.prepare('SELECT code, name FROM profiles WHERE player = ?').bind(player).first();
  if (row) {
    if (name !== null && name !== row.name) {
      await db.prepare('UPDATE profiles SET name = ?, touched_at = ? WHERE player = ?').bind(name, now, player).run();
      row.name = name;
    }
    return row;
  }
  for (let tries = 0; tries < 5; tries++) {
    const code = randomCode();
    const res = await db.prepare(
      'INSERT OR IGNORE INTO profiles (player, code, name, created_at, touched_at) VALUES (?, ?, ?, ?, ?)'
    ).bind(player, code, name || '', now, now).run();
    if (res.meta.changes) return { code, name: name || '' };
  }
  throw new Error('no free code');
}

// A player and their friends, with their best scores and today's challenge.
async function friendsOf(db, player, day) {
  const sql = `SELECT p.code, p.name, pl.score AS classic, s.score AS sprint, h.score AS hardcore, d.score AS today
    FROM profiles p
    LEFT JOIN players pl ON pl.id = p.player LEFT JOIN sprint s ON s.id = p.player
    LEFT JOIN hardcore h ON h.id = p.player LEFT JOIN daily d ON d.player = p.player AND d.day = ?`;
  const me = await db.prepare(`${sql} WHERE p.player = ?`).bind(day, player).first();
  const { results } = await db.prepare(
    `${sql} JOIN friends f ON f.friend = p.player WHERE f.player = ? ORDER BY f.created_at`
  ).bind(day, player).all();
  // Versus invites from friends, still fresh.
  const invites = (await db.prepare(
    `SELECT v.room, p.name, p.code FROM versus_invites v JOIN profiles p ON p.player = v.host
     WHERE v.guest = ? AND v.created_at > ? ORDER BY v.created_at DESC LIMIT 3`
  ).bind(player, Date.now() - INVITE_LIFE).all()).results;
  return { me, friends: results, invites };
}

async function duelView(db, id, player) {
  const duel = await db.prepare(
    `SELECT d.id, d.seed, d.owner, d.score, d.level, d.ghost, p.name, p.code
     FROM duels d LEFT JOIN profiles p ON p.player = d.owner WHERE d.id = ?`
  ).bind(id).first();
  if (!duel) return null;
  const { results } = await db.prepare(
    `SELECT r.player, r.score, r.level, r.ghost, p.name, p.code FROM duel_results r LEFT JOIN profiles p ON p.player = r.player
     WHERE r.duel = ? ORDER BY r.score DESC, r.played_at ASC LIMIT 20`
  ).bind(id).all();
  return {
    id: duel.id, seed: duel.seed, mine: duel.owner === player,
    owner: { name: duel.name || '', code: duel.code || '', score: duel.score, level: duel.level, ghost: JSON.parse(duel.ghost) },
    results: results.map(r => ({ name: r.name || '', code: r.code || '', score: r.score, level: r.level,
      ...(r.player === player ? { you: true, ghost: JSON.parse(r.ghost) } : {}) })),
  };
}

export async function social(request, url, env, h) {
  const db = env.DB, now = Date.now();
  const path = url.pathname;
  let body = null;
  if (request.method === 'POST') {
    try { body = await request.json(); } catch { return h.fail(400, 'bad json'); }
    if (!body || typeof body !== 'object') return h.fail(400, 'bad json');
  } else if (request.method !== 'GET') return h.fail(405, 'method not allowed');
  const player = request.method === 'GET' ? url.searchParams.get('player') : body.player;
  if (!h.validPlayer(player)) return h.fail(400, 'bad player');

  if (path === '/v1/profile' && body) {
    return h.json(await ensureProfile(db, player, nameOf(h, body), now));
  }

  if (path === '/v1/friends' || path === '/v1/friends/remove') {
    const day = request.method === 'GET' ? url.searchParams.get('day') : body.day;
    if (!h.validDay(day)) return h.fail(400, 'bad day');
    if (body) {
      const code = typeof body.code === 'string' ? body.code.toUpperCase().replace(/[^A-Z0-9]/g, '') : '';
      if (!validCode(code)) return h.fail(400, 'bad code');
      const friend = await db.prepare('SELECT player, name FROM profiles WHERE code = ?').bind(code).first();
      if (!friend) return h.fail(404, 'unknown code');
      if (friend.player === player) return h.fail(400, 'own code');
      if (path === '/v1/friends/remove') {
        await db.prepare('DELETE FROM friends WHERE (player = ?1 AND friend = ?2) OR (player = ?2 AND friend = ?1)')
          .bind(player, friend.player).run();
        return h.json(await friendsOf(db, player, day));
      }
      await ensureProfile(db, player, null, now);
      const { n } = await db.prepare('SELECT COUNT(*) AS n FROM friends WHERE player = ?').bind(player).first();
      if (n >= MAX_FRIENDS) return h.fail(400, 'too many friends');
      await db.batch([
        db.prepare('INSERT OR IGNORE INTO friends (player, friend, created_at) VALUES (?, ?, ?)').bind(player, friend.player, now),
        db.prepare('INSERT OR IGNORE INTO friends (player, friend, created_at) VALUES (?, ?, ?)').bind(friend.player, player, now),
      ]);
      return h.json({ ...(await friendsOf(db, player, day)), added: friend.name });
    }
    return h.json(await friendsOf(db, player, day));
  }

  if (path === '/v1/duels') {
    if (!body) {
      // My duels and the ones I played, the latest first.
      const { results } = await db.prepare(
        `SELECT d.id, d.owner = ?1 AS mine, d.score, d.created_at, p.name, p.code,
           (SELECT COUNT(*) FROM duel_results r WHERE r.duel = d.id AND r.player != ?1) AS players,
           (SELECT MAX(r.score) FROM duel_results r WHERE r.duel = d.id AND r.player != ?1) AS best,
           (SELECT r.score FROM duel_results r WHERE r.duel = d.id AND r.player = ?1) AS my_score,
           (SELECT MAX(r.played_at) FROM duel_results r WHERE r.duel = d.id) AS played_at
         FROM duels d LEFT JOIN profiles p ON p.player = d.owner
         WHERE d.owner = ?1 OR d.id IN (SELECT duel FROM duel_results WHERE player = ?1)
         ORDER BY COALESCE(played_at, d.created_at) DESC LIMIT 20`
      ).bind(player).all();
      return h.json({ duels: results.map(r => ({ ...r, mine: !!r.mine })) });
    }
    if (!validSeed(body.seed)) return h.fail(400, 'bad seed');
    const error = h.checkGame(body);
    if (error) return h.fail(400, error);
    if (!validGhost(body.ghost, body.score, body.duration)) return h.fail(400, 'bad ghost');
    const { n } = await db.prepare('SELECT COUNT(*) AS n FROM duels WHERE owner = ? AND created_at > ?').bind(player, now - 60000).first();
    if (n >= DUELS_PER_MINUTE) return h.fail(429, 'slow down');
    await ensureProfile(db, player, nameOf(h, body), now);
    for (let tries = 0; tries < 5; tries++) {
      const id = randomCode();
      const res = await db.prepare(
        'INSERT OR IGNORE INTO duels (id, seed, owner, score, level, hits, duration, ghost, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
      ).bind(id, body.seed, player, body.score, body.level, body.hits ?? body.score, body.duration, JSON.stringify(body.ghost), now).run();
      if (res.meta.changes) return h.json({ id });
    }
    throw new Error('no free duel id');
  }

  if (path === '/v1/versus' && body) {
    const code = typeof body.code === 'string' ? body.code.toUpperCase().replace(/[^A-Z0-9]/g, '') : '';
    const friend = validCode(code) && await db.prepare(
      'SELECT p.player FROM profiles p JOIN friends f ON f.friend = p.player WHERE p.code = ? AND f.player = ?'
    ).bind(code, player).first();
    if (!friend) return h.fail(404, 'not a friend');
    const { n } = await db.prepare('SELECT COUNT(*) AS n FROM versus_invites WHERE host = ? AND created_at > ?').bind(player, now - 60000).first();
    if (n >= DUELS_PER_MINUTE) return h.fail(429, 'slow down');
    const room = randomCode();
    await db.batch([
      db.prepare('DELETE FROM versus_invites WHERE created_at < ?').bind(now - INVITE_LIFE),
      db.prepare('INSERT INTO versus_invites (room, host, guest, created_at) VALUES (?, ?, ?, ?)').bind(room, player, friend.player, now),
    ]);
    return h.json({ room });
  }

  const m = path.match(/^\/v1\/duels\/([A-Z2-9]{8})$/);
  if (m) {
    const id = m[1];
    if (body) {
      const duel = await db.prepare('SELECT owner FROM duels WHERE id = ?').bind(id).first();
      if (!duel) return h.fail(404, 'unknown duel');
      const error = h.checkGame(body);
      if (error) return h.fail(400, error);
      if (!validGhost(body.ghost, body.score, body.duration)) return h.fail(400, 'bad ghost');
      if (duel.owner !== player) {
        await ensureProfile(db, player, nameOf(h, body), now);
        // Each player keeps their best try.
        await db.prepare(
          `INSERT INTO duel_results (duel, player, score, level, hits, duration, ghost, played_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT (duel, player) DO UPDATE SET score = excluded.score, level = excluded.level, hits = excluded.hits,
             duration = excluded.duration, ghost = excluded.ghost, played_at = excluded.played_at
           WHERE excluded.score > duel_results.score`
        ).bind(id, player, body.score, body.level, body.hits ?? body.score, body.duration, JSON.stringify(body.ghost), now).run();
      }
    }
    const view = await duelView(db, id, player);
    return view ? h.json(view) : h.fail(404, 'unknown duel');
  }
  return h.fail(404, 'not found');
}
