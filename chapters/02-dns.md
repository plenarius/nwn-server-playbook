# Chapter 2. DNS: giving your server a name

**Status:** tier 1 is written and tested. Tier 2 (putting websites behind Cloudflare's proxy, cache rules) and tier
3 (firewall and redirect rules at Cloudflare) are not written yet.

## What you learn

How to give the machine from chapter 1 a name, such as `game.example.org`, so that players type a name and not a
row of numbers. It's a small chapter: one record, and a few checks.

When you're done, you'll have:

- one address record that points a name at your machine;
- a way to check the name that doesn't fool you (the obvious way does, and it fooled me while testing this);
- a pattern for names that lets you move to another machine later without telling every player.

**You can skip this chapter.** A game server works fine without a name. Players can connect to the address, and a
public server can also be found in the game's own server list (chapter 4). What a name buys you is the freedom to
move: the day you change machines, you change one record and nobody has to hear about it. If you don't own a domain
yet and would like to get playing first, come back to this later. Nothing in tier 1 breaks without it.

**Time:** creating the record takes a minute or two. The name answered around the world within about 40 seconds on
the test. Please read step 5 before you check it, though, because checking too early can cost you half an hour of
confusion.

## What Layonara does

- **Where our DNS lives.** Our domain's DNS is at Cloudflare. Any DNS host does the same job for this chapter,
  including the one that comes with your domain.
- **Every machine has a name of its own.** Each of our four machines has an address record under its own name,
  holding its IPv4 address.
- **Services point at a machine's name.** A dozen of our service names (the forum, the wiki, the sign-in page,
  NWSync and others) are CNAME records, and a CNAME simply says "this name lives wherever that name lives". When a
  machine's address changes, those names follow along without being touched.
- **The game's name is not proxied.** Cloudflare can sit in front of a website and pass the traffic along, which it
  calls proxying. That works for web traffic only. The game speaks UDP on its own port, so the game's name goes
  straight to the machine. Cloudflare's dashboard calls this "DNS only".
- **The game's name has an IPv4 address and no IPv6 one.** The game server listens on IPv4 only. On the test
  machine it opened one socket, `0.0.0.0:5121`, and nothing on IPv6.
- **How long answers are remembered.** Most of our records use Cloudflare's automatic setting, which hands out
  answers that may be remembered for 300 seconds. Four names, all of services we have moved between machines, are
  set to 60 seconds.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The examples use `example.org` for your domain and `203.0.113.10` for your machine's IPv4 address. Put your own in
their place.

### 1. ADAPT. Decide where your DNS lives

Change: the DNS host.

You need a domain, and somewhere to keep its records. The company you bought the domain from almost always gives
you a page for records, and that is plenty for this chapter.

If you'd like to follow the later tiers closely, Cloudflare is what we use, and its DNS is on its free plan. Moving
a domain's DNS there means changing the domain's name servers at the company you bought it from. That switch can
take a day to settle, so it's a nice thing to start and then leave alone.

### 2. GENERIC. Pick the name

Give the machine one name. `game.example.org` is a good one, and it's what the rest of this guide uses.

Later chapters add more names, for NWSync and for a small website. In tier 1 they all live on this one machine, so
each of them will be a CNAME that points at `game.example.org`. You don't need to make them yet; the chapters that
need them will ask.

### 3. GENERIC. Create the record

In your DNS host's page for records, add one record:

| Field | Value |
|---|---|
| Type | `A` |
| Name | `game` |
| Address | your machine's IPv4 address |
| TTL | 300 seconds (or "Auto") |
| Proxy | off. At Cloudflare: "DNS only", the grey cloud |

Three small notes:

- **No `AAAA` record for this name.** `AAAA` is the IPv6 kind. The game server doesn't listen on IPv6, so an IPv6
  address for the game's name would only send some players to a closed door.
- **TTL** is how long others may remember the answer. 300 seconds means that after you change the record, everyone
  has the new answer within five minutes. There's no need to go lower.
- **If you use Cloudflare, keep the proxy off for this name.** Its proxy carries web traffic, and the game isn't
  web traffic.

If you use Cloudflare and would rather type than click,
[`templates/dns/cf-record.sh`](../templates/dns/cf-record.sh) makes the same record. It needs an API token that may
edit DNS for your one domain (in Cloudflare's dashboard: My Profile, API Tokens, the "Edit zone DNS" template,
limited to your domain) and the domain's zone id (on the domain's Overview page).

```sh
read -rs CF_API_TOKEN && export CF_API_TOKEN     # paste the token; it isn't shown or saved
export CF_ZONE_ID=your-zone-id
templates/dns/cf-record.sh create game.example.org 203.0.113.10
```

You should see `created A game.example.org 203.0.113.10 dns-only ttl 300`. The script won't touch a name that
already has a record, and its `delete` only removes records it made itself, so it can't hurt anything else in your
domain.

### 4. GENERIC. Check it at the source

Ask the servers that hold your domain's records. They are always right, straight away:

```sh
dig +short NS example.org
dig +short game.example.org @one-of-the-names-from-the-line-above
```

You should see your machine's address. On the test, the record answered here within 4 seconds of being created.

### 5. GENERIC. Then check it the way a player would, with a little patience

```sh
dig +short game.example.org @1.1.1.1
dig +short game.example.org @8.8.8.8
dig +short game.example.org
```

The first two ask big public resolvers; the third asks whatever your own computer uses. All three should print your
machine's address.

Here is the part worth knowing. **If any resolver is asked for a name before the name exists, it remembers "no such
name", and it can keep saying so for a while after you've created it.** Nothing is broken when that happens. The
record is fine, and step 4 proves it. The resolver is only repeating an old answer.

It happened to me on the test, so here are the real numbers. My own computer asked one second after the record was
created, which turned out to be a few seconds too early. The public resolvers had the right answer within 40
seconds. My home router kept saying "no such name" for about five minutes. Ten minutes in, one answer in three from
one public resolver was still "no such name", because a public resolver is really many machines and they don't all
forget at once. Our domain tells resolvers they may remember a "no such name" answer for up to 1,800 seconds, so
half an hour is the longest this should last.

So the gentle order is: create the record, check it at the source, make a cup of tea, and then check it the way a
player would. If your own computer is the one holding the old answer, `sudo resolvectl flush-caches` clears it on
most Linux desktops. A home router clears itself in time.

### 6. GENERIC. Log in by name

```sh
ssh nwn@game.example.org
```

SSH hasn't seen this name before, so it shows you the machine's key fingerprint and asks whether to go on. Compare
it with the one SSH already holds for the address:

```sh
ssh-keygen -l -F 203.0.113.10
```

If the two fingerprints match, say yes. It's the same machine under a new name. If they don't match, please don't
go on. Check the address in the record first; a typing slip there is the usual cause.

From here on, the guide uses the name wherever chapter 1 used `SERVER`.

### 7. LAYONARA-ONLY. Sixty-second answers on names we move

A few of our names are set to 60 seconds because we moved those services between machines and wanted the change to
arrive quickly. A new server doesn't need that. 300 seconds is kinder to everyone's resolvers and quick enough for
the day you move.

## The agent playbook

If you work with an AI agent, [`playbooks/02-dns.md`](../playbooks/02-dns.md) has these same steps in a fixed shape
it can follow. One thing in it is firmer than in the chapter above: an agent describes the record it wants to make
and waits for your yes before it creates anything, every time. A DNS record is public the moment it exists.

## Lessons

These are the things we learned the slow way, written down so you don't have to. The dates are when they happened.

- **Point services at a machine's name (2026-11-07).** On that day we moved our sign-in page, our git server and
  one more service from one machine to another. Each of them is a CNAME pointing at its machine's name, so the move
  was one small change per record, and none of them repeats an address that could later go out of date.
- **Create first, look up second (2026-11-18).** This is step 5, and it's dated because it caught me while testing
  this very chapter. The record was correct the whole time. Only the remembered "no such name" answers were stale,
  and for a few minutes I was reading the wrong evidence.
- **The source is the only check that can't be stale.** When a name seems wrong, ask the domain's own name servers
  first (step 4). If they're right, the record is right, and everything else is a matter of waiting.
- **Keep the game's name away from web proxies.** A proxy for websites doesn't carry the game's UDP traffic. We
  keep the game's name and our internal names as plain "DNS only" records for that reason.

## Tested

Like chapter 1, every step here was run for real before it was written down. On 2026-11-18, with a temporary name
in our own domain at Cloudflare, pointing at a fresh Hetzner cloud server of the smallest shared type that had just
been through chapter 1:

- the script: creating the record, showing it, refusing to create it a second time, refusing an address that isn't
  IPv4, refusing to delete a record it didn't make, reporting a token that may not edit, and deleting its own
  record at the end;
- how quickly the name appeared: at the source within 4 seconds, at three public resolvers within 40 seconds;
- the stale "no such name" answers in step 5, with the times given there;
- logging in by name, with the same key fingerprint as by address;
- that the game answers by name: the public NWNX image was started on the machine and answered a status query sent
  to the name over UDP;
- that the game server opens an IPv4 socket only.

Not tested: other DNS hosts, moving a domain's name servers to Cloudflare (the "can take a day" in step 1 is the
usual figure, not one I measured), and what a player sees if the game's name is proxied by mistake.
