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
| 1 | Choosing and preparing servers | [chapter](chapters/01-servers.md) | [playbook](playbooks/01-servers.md) | Tier 1 written and tested; tiers 2 and 3 to come |

Every chapter has the same five parts: what you learn, what Layonara does, the playbook for people, the playbook
for agents, and the lessons behind the rules.

## How code gets in here

Every script, workflow and compose file the guide quotes is a file in this repository that you can copy and run.
Nothing is quoted from a private repository.

By James, known as plenarius.
