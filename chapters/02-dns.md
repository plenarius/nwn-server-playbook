# Chapter 2. DNS: giving your server a name

**Status:** tiers 1 and 2 are written and tested. Tier 2, further down, puts your website behind Cloudflare's
proxy. Tier 3 (cache, firewall and redirect rules at Cloudflare) is not written yet.

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

---

## Tier 2. Your website behind Cloudflare's proxy

### What you learn

How to put your website, now on the control host (chapter 11's tier 2), behind Cloudflare's proxy, without breaking
its certificate or losing sight of who your visitors are. Your game and its downloads stay as they are.

When you're done, you'll have:

- your website's name proxied: visitors reach Cloudflare, and Cloudflare reaches your control host;
- the zone settings that keep this safe, checked;
- your pages never kept in Cloudflare's cache, and a one-line check that proves it;
- Coolify's proxy trusting Cloudflare's addresses, so your site sees each visitor's real address;
- the certificate on your own machine still issued and renewed by itself.

It needs Cloudflare as your DNS host (step 1), and chapter 3 and chapter 11's tier 2 done.

**Time:** about twenty minutes, most of it reading. On the test, the page came through the proxy, with its
certificate, about a minute after the deploy.

### What Layonara does

- **Only websites are proxied.** Our website, forum and wiki go through Cloudflare. The game, the downloads, the
  sign-in page and our machines' own names are DNS-only.
- **Pages are never cached at Cloudflare.** Pages differ for each signed-in member, so every page goes to our
  machines every time. Only things whose address changes when their content changes, such as pictures with a
  version in their address, are kept at Cloudflare.
- **Our proxies trust Cloudflare's addresses,** so every application sees the visitor's real address, and our
  limits on things like sign-ups work per visitor rather than per Cloudflare machine.
- **SSL mode Full (strict), and no edge redirects in the way of certificates.** Always Use HTTPS stays off, and our
  redirect rules at Cloudflare for names that have certificates leave `/.well-known/acme-challenge/` alone.
- **Rocket Loader, email obfuscation and Early Hints are off.** We tried Early Hints once: it filled our logs with
  tens of thousands of errors a day that never reached our machines, and helped nothing.

### The human playbook

The examples use `www.example.org` for your website and `CONTROL` for the control host's public address.

#### 8. GENERIC. Know what the proxy changes

With the proxy on, your name points at Cloudflare's addresses instead of your machine's. Visitors talk to
Cloudflare, with a certificate Cloudflare provides, and Cloudflare talks to your control host, which keeps its own
Let's Encrypt certificate. Three things follow:

- **Your machine sees Cloudflare, not the visitor,** unless you tell Coolify's proxy to trust Cloudflare (step 10).
- **Cloudflare could keep copies of your pages.** By default it doesn't keep pages, and the rule is never to make
  it (step 12).
- **Your machine's address is less visible,** though anyone who looked it up before the change still knows it.

Only proxy websites. The game speaks UDP, which Cloudflare's proxy doesn't carry, and chapter 7's downloads go
straight to the machine, as ours do.

#### 9. GENERIC. Check four zone settings

In Cloudflare's dashboard, for your domain:

| Where | Setting | Should be |
|---|---|---|
| **SSL/TLS**, **Overview** | Encryption mode | **Full (strict)** |
| **SSL/TLS**, **Edge Certificates** | Always Use HTTPS | **Off** |
| **Speed**, **Optimization** | Rocket Loader, Early Hints | **Off** |
| **Scrape Shield** | Email Address Obfuscation | **Off** |

Why each one:

- **Full (strict)** makes Cloudflare check your machine's real certificate. The looser "Flexible" talks plain HTTP
  to your machine, and Coolify's proxy answers plain HTTP with a redirect to HTTPS, round and round.
- **Always Use HTTPS** redirects at Cloudflare, before the request reaches your machine. Let's Encrypt checks your
  certificate over plain HTTP, so that redirect can stop your renewals. Coolify's proxy already sends visitors to
  HTTPS by itself; I checked on the test.
- **Rocket Loader and email obfuscation** rewrite your pages on the way through. Leave your pages as you wrote
  them.

These settings cover the whole domain. Change them while nothing is proxied yet, or at a quiet time.

#### 10. GENERIC. Make Coolify's proxy trust Cloudflare, first

Do this before you switch the proxy on. Then your site never sees a moment of wrong addresses.

Cloudflare publishes its addresses at <https://www.cloudflare.com/ips-v4> and <https://www.cloudflare.com/ips-v6>.
Make them one comma-separated line:

```sh
{ curl -s https://www.cloudflare.com/ips-v4; echo; curl -s https://www.cloudflare.com/ips-v6; } | grep . | paste -sd,
```

In Coolify: the control host's **Proxy** page, **Configuration**. In the **Traefik configuration** box, find the
line `- '--entrypoints.https.address=:443'` and add two lines after it, with your list in place of `RANGES`:

```yaml
      - '--entrypoints.http.forwardedHeaders.trustedIPs=RANGES'
      - '--entrypoints.https.forwardedHeaders.trustedIPs=RANGES'
```

**Save changes**, then **Restart Proxy**. Your sites are away for a few seconds while it restarts.

**Check these lines after every change to the proxy, and after every Coolify upgrade.** Coolify writes that file
itself, and it can write it again without your two lines. If that happens your site keeps working, but sees only
Cloudflare's addresses. Cloudflare's list changes rarely; look again once in a while.

#### 11. GENERIC. Switch the proxy on

In Cloudflare's **DNS** page, edit your website's record and switch **Proxy status** to **Proxied** (the orange
cloud). The [`cf-record.sh`](../templates/dns/cf-record.sh) script from step 3 can do it too:

```sh
templates/dns/cf-record.sh proxy www.example.org on
```

Then check, from your own computer:

```sh
curl -sI https://www.example.org/ | grep -i -E '^(HTTP|server|cf-cache-status)'
echo | openssl s_client -connect CONTROL:443 -servername www.example.org 2>/dev/null | openssl x509 -noout -issuer
```

You should see `200`, `server: cloudflare` and `cf-cache-status: DYNAMIC`. The second command asks your machine
directly, past Cloudflare, and should still name Let's Encrypt.

On the test I switched the proxy on before the site's first deploy, so the very first certificate was fetched
through Cloudflare. It arrived within a minute. Renewals take the same path.

#### 12. GENERIC. Never cache pages

`DYNAMIC` in step 11 means Cloudflare passed the page through without keeping it. That's what you want for every
page: the day your site has sign-ins, a kept page could show one member's page to another.

So never add a "Cache Everything" rule, or any cache rule that covers your pages. Let your site say what may be
kept, with its own `Cache-Control` headers, and add a Cloudflare cache rule only for a path whose address changes
when its content does, such as `/images/logo-v3.png`. A template page has nothing that needs one.

#### 13. GENERIC. See the visitor's real address

Each request now arrives with an `X-Forwarded-For` header listing the addresses it came through. On the test, the
website's log showed, for one request:

```text
"203.0.113.9,198.51.100.7, 162.159.113.92"
```

The last address is Cloudflare. The one before it is the real visitor. The first is a lie: the visitor sent it
themselves, to see what would happen. So **take the right-most address that isn't Cloudflare's or your own
network's, never the first.** Before step 10, the same header held only the Cloudflare address.

Your template site doesn't need any of this. The day your site limits something per visitor, such as sign-ups, it
must read the address this way.

#### 14. LAYONARA-ONLY. Our cache and firewall rules

We keep a handful of cache rules for pictures and shared page fragments, a redirect from an old name, and firewall
rules against badly behaved crawlers. They're shaped by what our sites have grown into. They're tier 3 subjects.

### The agent playbook

If you work with an AI agent, [`playbooks/02-dns-tier2.md`](../playbooks/02-dns-tier2.md) has these steps in a
fixed shape it can follow. It only reads your zone's settings and never changes them, and it asks before it turns
the proxy on.

### Lessons

- **Trust first, proxy second.** It's one of our written rules, because our limit on join requests and our forum's
  and wiki's records of who did what all depend on real addresses.
- **Edge redirects and certificates don't mix.** Anything Cloudflare redirects never reaches your machine, and
  Let's Encrypt's check is one of those things. Our redirect rules for names with certificates leave
  `/.well-known/acme-challenge/` alone, and Always Use HTTPS stays off.
- **Re-check after proxy changes.** Coolify owns its proxy's configuration, and our trust lines have to survive its
  rewrites. A quick look at a log line after any change tells you.
- **Never cache what depends on the visitor.** It's the rule all our cache settings follow.

### Tested

On 2026-11-18, with Coolify 4.7.5 (Traefik 3.7), on a fresh Hetzner cloud server of the smallest shared type with
chapter 3 and the website from chapter 11's tier 2, and a temporary name in our own domain:

- the zone settings above, read from Cloudflare's API (our own zone has had them for some time; I didn't change
  them for the test);
- the proxy switched on with `cf-record.sh` before the first deploy: the origin's Let's Encrypt certificate issued
  through Cloudflare, Cloudflare's own certificate at the edge;
- `DYNAMIC` for `/` and for `/index.html`;
- plain HTTP sent on to HTTPS by Coolify's proxy, and `/.well-known/acme-challenge/` reaching the machine over
  plain HTTP;
- the website's log before and after the trust lines: Cloudflare's address alone, then the visitor's real address
  before it; a forged first entry kept as sent, as in step 13;
- the trust lines in place after a **Restart Proxy** and after a reboot of the machine;
- then, with the proxy off and the trust lines removed again, the agent playbook as written: the settings read, the
  trust lines added in the dashboard, the proxy on, `DYNAMIC` and the origin's certificate, the visitor's address
  in the log, and the way back to DNS-only.

Not tested: other modes than Full (strict), the trust lines after a Coolify upgrade, cache rules (I didn't add any
to our live zone for a test), and IPv6 visitors.
