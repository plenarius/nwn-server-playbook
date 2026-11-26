// The website's one conversation with the operations API (chapter 9), held here on the server so that the key
// never reaches a browser. nginx keeps the answer for 30 seconds (site.conf), so the API is asked at most twice a
// minute however many people have the page open.
//
// Only what the public page shows leaves this file: the API's full answer also names staged modules, NWNX builds
// and changes waiting, which are your team's business.

const API = (process.env.OPS_API_URL || '').replace(/\/+$/, '');
const KEY = process.env.OPS_API_TEAM_KEY || '';

async function ask(path) {
  const reply = await ngx.fetch(API + path, { headers: { Authorization: 'Bearer ' + KEY } });
  if (reply.status !== 200) {
    throw new Error(path + ' answered ' + reply.status);
  }
  return reply.json();
}

// The container's state, as the API reports it, in the four words the page uses.
function stateOf(status) {
  if (!status) return 'offline';                        // no game container at all
  if (status === 'running' || status === 'running:healthy') return 'online';
  if (status === 'running:starting' || status.indexOf('restarting') === 0) return 'starting';
  if (status === 'running:unhealthy') return 'trouble';
  return 'offline';                                     // exited, created, paused, dead
}

// "[Thu Nov 26 10:15:23] Loading Module: mymodule" -> "2026-11-26T10:15:23Z". The game writes its log in the
// container's time, which is UTC in the NWNX image, and leaves out the year: take this year's, or last year's if
// that would be in the future (a server started on 31 December, read on 1 January).
const MONTHS = 'JanFebMarAprMayJunJulAugSepOctNovDec';

function startedAt(line) {
  const m = /^\[\w{3} (\w{3}) +(\d+) (\d\d):(\d\d):(\d\d)\]/.exec(line || '');
  if (!m || MONTHS.indexOf(m[1]) < 0) return null;
  const now = new Date();
  for (let back = 0; back < 2; back++) {
    const t = Date.UTC(now.getUTCFullYear() - back, MONTHS.indexOf(m[1]) / 3, +m[2], +m[3], +m[4], +m[5]);
    if (t <= now.getTime() + 60000) return new Date(t).toISOString();
  }
  return null;
}

function answer(r, code, body) {
  r.headersOut['Content-Type'] = 'application/json';
  r.return(code, JSON.stringify(body));
}

async function status(r) {
  if (!API || !KEY) {
    r.error('status: set OPS_API_URL and OPS_API_TEAM_KEY in the site\'s environment');
    return answer(r, 503, { error: 'not set up' });
  }
  let s;
  try {
    s = await ask('/api/v1/server/status');
  } catch (e) {
    r.error('status: the operations API did not answer: ' + e.message);
    // 503, not 502: Cloudflare replaces a 502 from your server with its own page, and the page wants this JSON.
    return answer(r, 503, { error: 'the operations API did not answer' });
  }
  // When the game last started comes from the start-up line in its log; without it, the page leaves the line out.
  let started = null;
  try {
    const p = await ask('/api/v1/server/progress?lines=1');
    started = startedAt(p.markers && p.markers.module);
  } catch (e) {
    r.warn('status: no start time: ' + e.message);
  }
  const state = stateOf(s.status);
  answer(r, 200, {
    state: state,
    players: state === 'online' && s.players >= 0 ? s.players : null,
    module: s.module && s.module !== '?' ? s.module : null,
    started: state === 'offline' ? null : started,
    restart_at: s.restart_pending ? s.restart_pending.restart_at : null,
    checked: new Date().toISOString(),
  });
}

export default { status };
