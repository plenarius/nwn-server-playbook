// Sign-in for your website (chapter 11, tier 3), run by nginx on the server. Authentik is the only place that
// knows passwords: the site sends the visitor there and gets back a one-use code, which it swaps for the person's
// name and groups over a direct connection to Authentik. Then the site keeps a small signed cookie and nothing
// else: no session store, no database.
//
// One more cookie, the marker, is shared by the website, the forum and the wiki on your parent domain. It says
// "someone signed in on one of the sites" and grants nothing: a site that sees it tries one quiet sign-in, and a
// site whose visitor has lost it signs them out. That's how signing in or out on one site carries to the others.
//
// Settings, from the application's environment in Coolify:
//   AUTH_ISSUER          https://auth.example.org/application/o/website/
//   AUTH_CLIENT_ID       website
//   AUTH_CLIENT_SECRET   the client secret Authentik's blueprint has for the website
//   SITE_URL             https://www.example.org
//   SESSION_SECRET       a long random string; changing it signs everyone out of the website
//   SSO_COOKIE_DOMAIN    .example.org (the marker's domain: your parent domain, with the dot)
//
// nginx's JavaScript isn't quite a browser's: no for...of, no await inside a call's arguments. Keep to that.

import hashes from 'crypto';

const ISSUER = process.env.AUTH_ISSUER || '';
const CLIENT_ID = process.env.AUTH_CLIENT_ID || '';
const CLIENT_SECRET = process.env.AUTH_CLIENT_SECRET || '';
const SITE = (process.env.SITE_URL || '').replace(/\/+$/, '');
const SECRET = process.env.SESSION_SECRET || '';
const MARKER_DOMAIN = process.env.SSO_COOKIE_DOMAIN || '';
const MARKER = 'sso';
const DAYS = 14;
const CALLBACK = SITE + '/auth/callback';

function cookies(r) {
  const out = {};
  String(r.headersIn.Cookie || '').split(';').forEach(function (part) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  });
  return out;
}

function cookie(name, value, opts) {
  let c = name + '=' + value + '; Path=' + (opts.path || '/') + '; Secure; HttpOnly; SameSite=Lax';
  if (opts.domain) c += '; Domain=' + opts.domain;
  if (opts.maxAge !== undefined) c += '; Max-Age=' + opts.maxAge;
  return c;
}

const b64u = (s) => Buffer.from(s).toString('base64url');
const unb64u = (s) => Buffer.from(s, 'base64url').toString();
const random = (n) => Buffer.from(crypto.getRandomValues(new Uint8Array(n))).toString('hex');
const mac = (s) => hashes.createHmac('sha256', SECRET).update(s).digest('base64url');

// A value only this site can have made: base64url(JSON) + "." + its signature.
function seal(obj) { const body = b64u(JSON.stringify(obj)); return body + '.' + mac(body); }
function open(sealed) {
  if (!sealed || !SECRET) return null;
  const i = sealed.lastIndexOf('.');
  if (i < 1 || mac(sealed.slice(0, i)) !== sealed.slice(i + 1)) return null;
  try {
    const obj = JSON.parse(unb64u(sealed.slice(0, i)));
    return obj.exp && obj.exp > Date.now() / 1000 ? obj : null;
  } catch (e) { return null; }
}

function session(r) { return open(cookies(r).session); }

// Only paths on this site: "/something", never "//elsewhere".
function safeReturn(p) { return typeof p === 'string' && /^\/(?![\/\\])/.test(p) ? p : '/'; }

async function discovery() {
  const reply = await ngx.fetch(ISSUER.replace(/\/?$/, '/') + '.well-known/openid-configuration');
  if (reply.status !== 200) throw new Error('discovery answered ' + reply.status);
  return reply.json();
}

function fail(r, what, e) {
  r.error('auth: ' + what + ': ' + (e && e.message ? e.message : e));
  r.headersOut['Content-Type'] = 'text/plain; charset=utf-8';
  r.return(502, 'Signing in is not working right now. Please try again in a minute.\n');
}

// /auth/login?returnTo=/page    Sends the browser to Authentik. With &quiet=1 (from the marker check below),
// Authentik is asked not to show a page: it answers at once, signed in or "login_required".
async function login(r) {
  try {
    const d = await discovery();
    const quiet = r.args.quiet === '1';
    const flow = { s: random(16), n: random(16), v: random(32), r: safeReturn(r.args.returnTo), q: quiet,
                   exp: Math.floor(Date.now() / 1000) + 600 };
    const challenge = hashes.createHash('sha256').update(flow.v).digest('base64url');
    const q = ['response_type=code', 'client_id=' + encodeURIComponent(CLIENT_ID),
               'redirect_uri=' + encodeURIComponent(CALLBACK), 'scope=' + encodeURIComponent('openid profile email'),
               'state=' + flow.s, 'nonce=' + flow.n, 'code_challenge=' + challenge, 'code_challenge_method=S256'];
    if (quiet) q.push('prompt=none');
    const set = [cookie('auth_flow', seal(flow), { path: '/auth/', maxAge: 600 })];
    // Remember that this marker was tried, so a visitor who isn't signed in at Authentik is asked once, not on
    // every page.
    const m = cookies(r)[MARKER];
    if (quiet && m) set.push(cookie('sso_tried', m, {}));
    r.headersOut['Set-Cookie'] = set;
    r.headersOut['Cache-Control'] = 'no-store';
    r.return(302, d.authorization_endpoint + '?' + q.join('&'));
  } catch (e) { fail(r, 'login', e); }
}

// /auth/callback    Authentik sends the browser back here with a code, which the site swaps for the ID token
// over its own connection to Authentik. That connection's certificate is checked, which is what OpenID Connect
// asks of a site that gets its token this way; the token's issuer, audience, nonce and age are checked too.
async function callback(r) {
  const flow = open(cookies(r).auth_flow);
  if (!flow || r.args.state !== flow.s) {
    r.headersOut['Set-Cookie'] = [cookie('auth_flow', '', { path: '/auth/', maxAge: 0 })];
    r.return(302, '/');
    return;
  }
  if (r.args.error) {   // login_required after a quiet try: stay a guest, on the page they asked for.
    if (!flow.q) r.warn('auth: Authentik answered ' + r.args.error);
    r.headersOut['Set-Cookie'] = [cookie('auth_flow', '', { path: '/auth/', maxAge: 0 })];
    r.return(302, flow.r);
    return;
  }
  try {
    const d = await discovery();
    const body = 'grant_type=authorization_code&code=' + encodeURIComponent(r.args.code || '') +
      '&redirect_uri=' + encodeURIComponent(CALLBACK) + '&code_verifier=' + flow.v;
    const basic = 'Basic ' + Buffer.from(encodeURIComponent(CLIENT_ID) + ':' + encodeURIComponent(CLIENT_SECRET)).toString('base64');
    const reply = await ngx.fetch(d.token_endpoint, { method: 'POST', body: body,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: basic } });
    const text = await reply.text();
    if (reply.status !== 200) throw new Error('token endpoint answered ' + reply.status + ' ' + text.slice(0, 200));
    const idt = JSON.parse(text).id_token;
    const claims = JSON.parse(unb64u(idt.split('.')[1]));
    const now = Date.now() / 1000;
    const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
    if (claims.iss !== d.issuer || aud.indexOf(CLIENT_ID) < 0 || claims.nonce !== flow.n || !(claims.exp > now)) {
      throw new Error('the ID token is not for this site');
    }
    // Keep the session small: a browser silently drops a cookie over 4 KB, and someone in many groups gets one.
    // The site only needs to know whether they're on your team.
    const groups = claims.groups || [];
    const s = { sub: claims.sub, name: claims.name || claims.preferred_username, user: claims.preferred_username,
                team: groups.indexOf('team') >= 0, exp: Math.floor(now) + DAYS * 86400 };
    const set = [
      cookie('auth_flow', '', { path: '/auth/', maxAge: 0 }),
      cookie('session', seal(s), { maxAge: DAYS * 86400 }),
      // Authentik's ID token, sent back to it at sign-out; only /auth/logout ever sees it.
      cookie('auth_idt', idt, { path: '/auth/logout', maxAge: DAYS * 86400 }),
      cookie('sso_tried', '', { maxAge: 0 }),
    ];
    const m = cookies(r)[MARKER];
    if (!m || m.split('.')[0] !== s.sub) {
      set.push(cookie(MARKER, s.sub + '.' + random(8), { domain: MARKER_DOMAIN, maxAge: DAYS * 86400 }));
    }
    r.headersOut['Set-Cookie'] = set;
    r.headersOut['Cache-Control'] = 'no-store';
    r.return(302, flow.r);
  } catch (e) { fail(r, 'callback', e); }
}

// /auth/logout    Signs out here, takes the marker away (so the forum and wiki sign out too, at their next page),
// and sends the browser to Authentik to end its session there as well.
async function logout(r) {
  const idt = cookies(r).auth_idt;
  r.headersOut['Set-Cookie'] = [
    cookie('session', '', { maxAge: 0 }),
    cookie('auth_idt', '', { path: '/auth/logout', maxAge: 0 }),
    cookie('sso_tried', '', { maxAge: 0 }),
    cookie(MARKER, '', { domain: MARKER_DOMAIN, maxAge: 0 }),
  ];
  r.headersOut['Cache-Control'] = 'no-store';
  try {
    const d = await discovery();
    // Authentik's sign-out flow (blueprint 10-sites.yaml) ends on the front page.
    let to = d.end_session_endpoint;
    if (idt) to += '?id_token_hint=' + encodeURIComponent(idt);
    r.return(302, to);
  } catch (e) { r.error('auth: logout: ' + e.message); r.return(302, '/'); }
}

// /auth/drop?returnTo=/page    The marker is gone or names someone else: sign out here only, quietly.
function drop(r) {
  r.headersOut['Set-Cookie'] = [cookie('session', '', { maxAge: 0 }), cookie('auth_idt', '', { path: '/auth/logout', maxAge: 0 })];
  r.headersOut['Cache-Control'] = 'no-store';
  r.return(302, safeReturn(r.args.returnTo));
}

// /auth/me    What the page shows: signed in or not, the name, and whether they're on the team. Never the token.
function me(r) {
  const s = session(r);
  r.headersOut['Content-Type'] = 'application/json';
  r.headersOut['Cache-Control'] = 'private, no-store';
  r.return(200, JSON.stringify(s ? { signedIn: true, name: s.name, user: s.user, team: s.team } : { signedIn: false }));
}

// For every page a browser opens (js_set $sso_redirect in nginx.conf): an address to send the browser to first,
// or nothing. Only full page loads count (browsers send Sec-Fetch-Dest: document; search engines send nothing),
// so pictures, scripts and robots are never sent anywhere.
function check(r) {
  if (r.method !== 'GET' || r.headersIn['Sec-Fetch-Dest'] !== 'document') return '';
  const c = cookies(r);
  const s = session(r);
  const m = c[MARKER];
  const here = encodeURIComponent(r.uri + (r.variables.is_args || '') + (r.variables.args || ''));
  if (s && (!m || m.split('.')[0] !== s.sub)) return '/auth/drop?returnTo=' + here;
  if (!s && m && c.sso_tried !== m) return '/auth/login?quiet=1&returnTo=' + here;
  return '';
}

export default { login, callback, logout, drop, me, check };
