// A versus match between two friends: one Durable Object per room, the two
// phones connected by WebSocket (/v1/versus/<room>/ws?player=<id>&name=<name>).
//
// Both players get the same seed and the same start time; each plays on their
// own phone and reports score, lives and combo a few times a second, which the
// room passes on to the other. Combos send attacks to the opponent. When the
// time is up (or both are out of lives, or one leaves) the room decides the
// winner: the higher score.
//
// Messages from a phone:  { t: 'state', score, lives, streak, level }
//                         { t: 'attack', kind }   { t: 'rematch' }
// Messages from the room: { t: 'joined', you, names, phase, …start }  { t: 'opponent', name }
//                         { t: 'start', seed, at, now, duration }      { t: 'state', … }
//                         { t: 'attack', kind }  { t: 'left' }  { t: 'back' }  { t: 'rematch' }
//                         { t: 'result', winner, scores, names, reason }

const DURATION = 120;          // seconds of play
const COUNTDOWN = 3500;        // ms between "start" and the first ball
const LIVES = 3;
const REJOIN = 10000;          // ms a dropped player has to come back
const ATTACK_GAP = 1200;       // ms between two attacks from the same player
const ATTACKS = ['turbo', 'chameleon', 'spin'];
const SEED_CHARS = 'abcdefghijkmnpqrstuvwxyz23456789';

export class Match {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
    this.seats = [];      // { player, name, ws, score, lives, streak, level, rematch, lastAttack }
    this.phase = 'waiting'; // waiting | playing | over
    this.start = null;
  }

  duration() { return Number(this.env.VERSUS_SECONDS) || DURATION; }

  send(seat, msg) {
    if (!seat || !seat.ws) return;
    try { seat.ws.send(JSON.stringify(msg)); } catch {}
  }
  other(seat) { return this.seats.find(s => s !== seat); }

  async fetch(request) {
    if (request.headers.get('Upgrade') !== 'websocket') return new Response('expected a websocket', { status: 426 });
    const url = new URL(request.url);
    const player = url.searchParams.get('player') || '';
    if (!/^[0-9a-f]{32}$/.test(player)) return new Response('bad player', { status: 400 });
    const name = (url.searchParams.get('name') || '').slice(0, 14);
    let seat = this.seats.find(s => s.player === player);
    if (!seat) {
      if (this.seats.length >= 2) return new Response('room is full', { status: 409 });
      seat = { player, name, ws: null, score: 0, lives: LIVES, streak: 0, level: 1, rematch: false, lastAttack: 0 };
      this.seats.push(seat);
    }
    seat.name = name || seat.name;
    const [client, server] = Object.values(new WebSocketPair());
    server.accept();
    if (seat.ws) { try { seat.ws.close(1000, 'replaced'); } catch {} }
    seat.ws = server;
    clearTimeout(seat.dropTimer);
    server.addEventListener('message', e => this.message(seat, e.data));
    server.addEventListener('close', () => this.closed(seat, server));
    server.addEventListener('error', () => this.closed(seat, server));

    const opp = this.other(seat);
    this.send(seat, { t: 'joined', you: this.seats.indexOf(seat), names: this.seats.map(s => s.name), phase: this.phase,
      ...(this.phase === 'playing' ? { ...this.start, now: Date.now() } : {}),
      ...(opp ? { opp: { score: opp.score, lives: opp.lives, streak: opp.streak, level: opp.level, connected: !!opp.ws } } : {}) });
    if (opp) this.send(opp, { t: this.phase === 'playing' ? 'back' : 'opponent', name: seat.name });
    if (this.phase === 'waiting' && this.seats.length === 2 && this.seats.every(s => s.ws)) await this.begin();
    return new Response(null, { status: 101, webSocket: client });
  }

  async begin() {
    this.phase = 'playing';
    const seed = Array.from(crypto.getRandomValues(new Uint8Array(10)), b => SEED_CHARS[b % SEED_CHARS.length]).join('');
    this.start = { t: 'start', seed, at: Date.now() + COUNTDOWN, duration: this.duration() };
    for (const s of this.seats) Object.assign(s, { score: 0, lives: LIVES, streak: 0, level: 1, rematch: false, lastAttack: 0 });
    for (const s of this.seats) this.send(s, { ...this.start, now: Date.now() });
    // The end, with a little slack for the last messages to arrive.
    await this.ctx.storage.setAlarm(this.start.at + this.start.duration * 1000 + 1500);
  }

  async alarm() {
    if (this.phase === 'playing') this.finish('time');
  }

  message(seat, data) {
    let msg;
    try { msg = JSON.parse(data); } catch { return; }
    const opp = this.other(seat);
    if (msg.t === 'state' && this.phase === 'playing') {
      const int = (v, max) => Number.isInteger(v) && v >= 0 && v <= max ? v : null;
      seat.score = int(msg.score, 100000) ?? seat.score;
      seat.lives = int(msg.lives, LIVES) ?? seat.lives;
      seat.streak = int(msg.streak, 100000) ?? seat.streak;
      seat.level = int(msg.level, 1000) ?? seat.level;
      this.send(opp, { t: 'state', score: seat.score, lives: seat.lives, streak: seat.streak, level: seat.level });
      if (this.seats.length === 2 && this.seats.every(s => s.lives === 0)) this.finish('out');
    } else if (msg.t === 'attack' && this.phase === 'playing' && ATTACKS.includes(msg.kind)) {
      const now = Date.now();
      if (now - seat.lastAttack < ATTACK_GAP || seat.lives === 0) return;
      seat.lastAttack = now;
      this.send(opp, { t: 'attack', kind: msg.kind });
    } else if (msg.t === 'rematch' && this.phase === 'over') {
      seat.rematch = true;
      this.send(opp, { t: 'rematch' });
      if (this.seats.length === 2 && this.seats.every(s => s.rematch && s.ws)) this.begin();
    }
  }

  closed(seat, ws) {
    if (seat.ws !== ws) return;
    seat.ws = null;
    const opp = this.other(seat);
    if (this.phase === 'waiting') {
      // Not started yet: the seat is free again.
      this.seats = this.seats.filter(s => s !== seat);
      return;
    }
    this.send(opp, { t: 'left' });
    if (this.phase === 'playing') {
      seat.dropTimer = setTimeout(() => {
        if (!seat.ws && this.phase === 'playing') this.finish('left', seat);
      }, REJOIN);
    }
  }

  finish(reason, quitter = null) {
    if (this.phase !== 'playing') return;
    this.phase = 'over';
    const [a, b] = this.seats;
    const scores = this.seats.map(s => s.score);
    let winner = -1; // -1: a draw
    if (quitter) winner = this.seats.indexOf(this.other(quitter));
    else if (b && a.score !== b.score) winner = a.score > b.score ? 0 : 1;
    const msg = { t: 'result', winner, scores, names: this.seats.map(s => s.name), reason };
    for (const s of this.seats) this.send(s, msg);
    this.ctx.storage.deleteAlarm();
  }
}
