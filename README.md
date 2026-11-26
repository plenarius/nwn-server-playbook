# NWN server playbook

A guide to running your own Neverwinter Nights: Enhanced Edition persistent world with NWNX, written for people
and for the AI agents that help them. Layonara, a persistent world online since 2002, is the worked example: the
guide shows what it runs and why, with hostnames, addresses and anything about players replaced.

**Status:** in progress and private. Nothing here is ready to follow yet.

## Three tiers

The tiers are cumulative. Stop at the one that fits; you lose nothing by stopping.

| Tier | Who it is for | What you end up with | Servers |
|---|---|---|---|
| 1. One evening | One person starting a server | A game server with NWNX and a database on one machine, the module and haks in git, a compile check on every pull request, NWSync for players, a nightly database dump, a one-page site | 1 |
| 2. A server with a team | A small team with regular releases | Tier 1, plus a second machine for building and control, a private network, Coolify, staged releases, a headless test suite, an operations API with a Discord dashboard, Cloudflare, off-site encrypted backups, outside uptime checks, dashboards | 2 |
| 3. Layonara-grade | A long-lived world with many contributors and AI agents | Tier 2, plus self-hosted runners and test lanes, picture previews on pull requests, a dev server, single sign-on across website, forum and wiki, agent machines with generated guides, an issue watcher, burst servers | 3 or more |

## Chapters

| # | Chapter | People | Agents | State |
|---|---|---|---|---|
| 1 | Choosing and preparing servers | [chapter](chapters/01-servers.md) | [tier 1](playbooks/01-servers.md), [tier 2](playbooks/01-servers-tier2.md), [tier 3](playbooks/01-servers-tier3.md) | Tiers 1, 2 and 3 written and tested (tier 3: servers from a script with labels, expiry, a budget and a reaper; snapshots without the cloud-init trap; legacy prices; a third site, with a third location standing in for another provider) |
| 2 | DNS: giving your server a name | [chapter](chapters/02-dns.md) | [tier 1](playbooks/02-dns.md), [tier 2](playbooks/02-dns-tier2.md), [tier 3](playbooks/02-dns-tier3.md) | Tiers 1, 2 and 3 written and tested (tier 3: firewall and redirect rules in a file in git, applied by a script that only touches its own rules; rate limit described, not tested) |
| 3 | Coolify | [chapter](chapters/03-coolify.md) | [tier 2](playbooks/03-coolify.md), [tier 3](playbooks/03-coolify-tier3.md) | Not used in tier 1; tiers 2 and 3 written and tested (tier 3: Coolify's own skip of superseded deploys and a helper for when it's missing, the proxy check from Docker's start) |
| 4 | The game server and NWNX | [chapter](chapters/04-game-server.md) | [tier 1](playbooks/04-game-server.md), [tier 2](playbooks/04-game-server-tier2.md), [tier 3](playbooks/04-game-server-tier3.md) | Tiers 1, 2 and 3 written and tested (tier 3: your own NWNX image built in CI with an example plugin, commit tags never re-pushed, the moving tag for chapter 9's update) |
| 5 | The database | [chapter](chapters/05-database.md) | [tier 1](playbooks/05-database.md), [tier 2](playbooks/05-database-tier2.md), [tier 3](playbooks/05-database-tier3.md) | Tiers 1, 2 and 3 written and tested (migrations with a ledger run by `release.sh`; a work queue that runs each job once, revision counters, read-only and queue-only accounts on the private address) |
| 6 | Your module in git | [chapter](chapters/06-module.md) | [tier 1](playbooks/06-module.md), [tier 2](playbooks/06-module-tier2.md), [tier 3](playbooks/06-module-tier3.md) | Tiers 1, 2 and 3 written and tested (tier 3: test selection, lanes, one recorded retry, a quarantine list and a daily flake report) |
| 7 | Custom content: haks, the talk table and NWSync | [chapter](chapters/07-haks-nwsync.md) | [tier 1](playbooks/07-haks-nwsync.md), [tier 2](playbooks/07-haks-nwsync-tier2.md), [tier 3](playbooks/07-haks-nwsync-tier3.md) | Tiers 1, 2 and 3 written and tested (tier 2: builder image, staging, promote and roll back, prune; tier 3: compiled models, origins files, a builders' NWSync) |
| 8 | CI and runners | [chapter](chapters/08-ci.md) | [tier 2](playbooks/08-ci-tier2.md), [tier 3](playbooks/08-ci-tier3.md) | Tier 1 is chapter 6's compile check; tiers 2 and 3 written and tested (tier 3: one-job self-hosted runners in containers that refuse forks, a shared haks cache, nwn-bake pictures on pull requests; nwn-director stills described, tested only to the login) |
| 9 | The operations API | [chapter](chapters/09-ops-api.md) | [tier 2](playbooks/09-ops-api-tier2.md), [tier 3](playbooks/09-ops-api-tier3.md) | Not used in tier 1 (restart by hand); tiers 2 and 3 written and tested (tier 3: game data from the API's own copy of the game files: talk table, 2DAs, items and character sheets on the read key, retiring a character, what's private in a character file) |
| 10 | The Discord bot | [chapter](chapters/10-discord-bot.md) | [tier 2](playbooks/10-discord-bot-tier2.md), [tier 3](playbooks/10-discord-bot-tier3.md) | Not used in tier 1; tiers 2 and 3 written and tested (tier 3: reports from a Discord form into a private repo with answers in the reporter's thread, a chat bridge over the work queue, a roster from the operations API; Discord's live connection stood in) |
| 11 | A website | [chapter](chapters/11-website.md) | [tier 1](playbooks/11-website.md), [tier 2](playbooks/11-website-tier2.md), [status](playbooks/11-website-tier2-status.md), [tier 3 characters](playbooks/11-website-tier3-characters.md) | Tiers 1 and 2 written and tested (the move to the control host with deploy on merge; a live status page from the operations API); tier 3 character pages written and tested (opt-in list, read key server-side, only fields the player agreed to); shared sign-in, forum and wiki to come |
| 12 | Backups and restore | [chapter](chapters/12-backups.md) | [tier 1](playbooks/12-backups.md), [tier 2](playbooks/12-backups-tier2.md), [tier 3](playbooks/12-backups-tier3.md) | Tiers 1, 2 and 3 written and tested (tier 3: character files committed to a private git history every half hour, one-character restore by commit or time, alerts when the history or borg stop moving) |
| 13 | Monitoring and alerting | [chapter](chapters/13-monitoring.md) | [tier 2](playbooks/13-monitoring-tier2.md), [tier 3](playbooks/13-monitoring-tier3.md) | Tier 1 is chapter 4's health check; tiers 2 and 3 written and tested (tier 3: NWNX metrics, central logs, traces and Grafana on the control host, private only, with retention) |
| 14 | A dev server | [chapter](chapters/14-dev-server.md) | [tier 2](playbooks/14-dev-server-tier2.md) | Tier 1 is "skip"; tier 2 written and tested (optional: a dev server on the control host, pull request builds with rollback, a scrubbed copy of the live database); tier 3 to come |
| 15 | Agent machines | [chapter](chapters/15-agent-machines.md) | [tier 3](playbooks/15-agent-machines-tier3.md) | Tiers 1 and 2: skip; tier 3 written and tested (hub and workers, an agent user with limits, tokens in memory, a tunnel to each worker, generated guides, guard-push, an issue watcher, burst servers with a secret scan before any image is saved) |
| 16 | Day to day: releasing | [chapter](chapters/16-releasing.md) | [tier 1](playbooks/16-releasing.md), [tier 2](playbooks/16-releasing-tier2.md), [tier 3](playbooks/16-releasing-tier3.md) | Tiers 1, 2 and 3 written and tested (tier 3: an expiry calendar with a checker warning into the watchdog channel, a release train with labels, freezes and release candidates, the full incident list) |

Every chapter has the same five parts: what you learn, what Layonara does, the playbook for people, the playbook
for agents, and the lessons behind the rules.

## Tested as a whole

Each chapter says what was tested for it. Tier 1 was also run once from start to finish, the way a reader would
do it: on 2026-11-18, on one fresh server, every tier 1 playbook in order (1, 2, 4, 5, 6, 7, 11, 12, 16), each
command block exactly as written, from a clean copy of this repository. It ended with a game server answering by
name, a database, a module built by its own check on GitHub, custom content downloaded over HTTPS, a website,
nightly backups and one release. From the moment the server existed, that took under twelve minutes.

One thing differed from the playbooks: the GitHub repository for the module already existed, so playbook 6 pushed
to it and did not create it.

That run exists because the chapter-by-chapter tests had missed a fault between two chapters. It is the check to
repeat whenever a template changes.

## How code gets in here

Every script, workflow and compose file the guide quotes is a file in this repository that you can copy and run.
Nothing is quoted from a private repository.

By James, known as plenarius.
