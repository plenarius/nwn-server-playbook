// Character pages (chapter 11, tier 3): the site's server asks the operations API (chapter 9) for a character
// sheet on the visitor's behalf, with the read key, which never reaches a browser. Like status.js, it passes on
// only what the page shows, by name.
//
// Only the characters listed in characters.txt have a page. The API's read key can read any character in the
// vault, so this file is the lock: a name that isn't listed gets the same "not found" as one that doesn't exist,
// and the API isn't even asked.

import fs from 'fs';

const API = (process.env.OPS_API_URL || '').replace(/\/+$/, '');
const KEY = process.env.OPS_API_READ_KEY || '';
const LIST = '/etc/nginx/characters.txt';
const SLUG = /^[a-z0-9-]{1,40}$/;
const decoded = (s) => { try { return decodeURIComponent(s); } catch (e) { return s; } };

// characters.txt, one character a line: the page's name, the vault folder, the file name, and "gear" if the
// player also wants what they wear shown, separated by spaces; a space inside a name is written %20. Read on
// every call: nginx caches the answers, so that's seldom.
function allowed() {
  const out = {};
  let text = '';
  try { text = fs.readFileSync(LIST, 'utf8'); } catch (e) { return out; }
  text.split('\n').forEach(function (raw) {
    const line = raw.replace(/#.*/, '').trim();
    if (!line) return;
    const f = line.split(/\s+/).map(decoded);
    if (SLUG.test(f[0]) && f[1] && f[2]) out[f[0]] = { folder: f[1], file: f[2], gear: f.slice(3).indexOf('gear') >= 0 };
  });
  return out;
}

async function sheet(who) {
  const path = '/api/v1/game/vault/' + encodeURIComponent(who.folder) + '/' + encodeURIComponent(who.file);
  const reply = await ngx.fetch(API + path, { headers: { Authorization: 'Bearer ' + KEY } });
  if (reply.status !== 200) throw new Error('answered ' + reply.status);
  return reply.json();
}

// The game keeps colour codes in names (<cRGB>...</c>, three raw bytes after <c). A web page shows plain text.
const plain = (s) => String(s || '').replace(/<c[^>]{0,3}>|<\/c>/g, '').trim();

// What the public page shows: what the player wrote for others to read, and what anyone meeting the character
// in the game could tell. Never the vault folder (it is the player's CD key), the pack, gold, local variables,
// where they are, ability scores, skills, feats, experience or when they last played.
function card(slug, who, s) {
  const out = {
    slug: slug,
    name: plain(s.name && s.name.full),
    description: plain(s.description),
    race: s.subrace ? plain(s.subrace) : (s.race && s.race.name) || null,
    gender: (s.gender && s.gender.name) || null,
    deity: plain(s.deity) || null,
    level: s.level || null,
    classes: (s.classes || []).map((c) => ({ name: c.name, level: c.level })),
  };
  if (who.gear) out.gear = (s.equipped || []).map((e) => ({ slot: e.slot, name: plain(e.name) }));
  return out;
}

function answer(r, code, body) {
  r.headersOut['Content-Type'] = 'application/json';
  r.return(code, JSON.stringify(body));
}

function ready(r) {
  if (API && KEY) return true;
  r.error('characters: set OPS_API_URL and OPS_API_READ_KEY in the site\'s environment');
  answer(r, 503, { error: 'not set up' });
  return false;
}

// /characters/<slug>.json
async function one(r) {
  if (!ready(r)) return;
  const slug = r.variables.slug;
  const who = allowed()[slug];
  if (!who) return answer(r, 404, { error: 'no such character' });
  try {
    const s = await sheet(who);
    answer(r, 200, card(slug, who, s));
  } catch (e) {
    // A listed character whose file is gone (retired, renamed) is "not found" to visitors; the log says which.
    r.error('characters: ' + slug + ': the operations API ' + e.message);
    if (e.message === 'answered 404') return answer(r, 404, { error: 'no such character' });
    return answer(r, 503, { error: 'the operations API did not answer' });
  }
}

// /characters.json: everyone listed, by name, for the list page. A character that can't be read is left out.
async function list(r) {
  if (!ready(r)) return;
  const all = allowed();
  const slugs = Object.keys(all);
  const cards = await Promise.all(slugs.map(async (slug) => {
    try {
      const s = await sheet(all[slug]);
      const c = card(slug, all[slug], s);
      return { slug: c.slug, name: c.name, race: c.race, level: c.level, classes: c.classes };
    } catch (e) {
      r.error('characters: ' + slug + ': the operations API ' + e.message);
      return e.message === 'answered 404' ? null : 'failed';
    }
  }));
  const found = cards.filter((c) => c && c !== 'failed');
  if (cards.includes('failed') && !found.length) return answer(r, 503, { error: 'the operations API did not answer' });
  answer(r, 200, { characters: found.sort((a, b) => a.name.localeCompare(b.name)) });
}

export default { one, list };
