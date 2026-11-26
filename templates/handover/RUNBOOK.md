# Runbook: My server

One page for whoever runs a release, or keeps the world running, when I can't. It holds no passwords and no keys:
it says where they are. Keep it in the module's repository, and change it in the same pull request as anything it
describes.

**Last checked:** YYYY-MM-DD, by NAME, by doing a release with only this page. If this date is more than three
months old, trust it a little less, and check it again.

## Who

| Who | How to reach them | What they can do |
|---|---|---|
| NAME | Discord @..., phone in the password manager | everything; owns the accounts |
| NAME | ... | releases, restarts, restores |

If you can't reach anyone and the game is down: the "Bad day" part below is safe to follow on your own.

## The machines

| Name | What it does | Provider and plan | How to log in |
|---|---|---|---|
| game host | the game, its database, staging | PROVIDER, PLAN | `ssh nwn@GAME`, with your own key |
| control host | Coolify, content builds, downloads | PROVIDER, PLAN | `ssh nwn@CONTROL`, with your own key |
| storage | the off-site backups | PROVIDER, PLAN | nobody logs in; see chapter 12 |

Private network: game host `10.77.0.2`, control host `10.77.0.1`. Coolify's dashboard: `ssh -L 8000:localhost:8000
nwn@CONTROL`, then `http://localhost:8000`.

## Accounts (each person has their own; nobody shares a login)

| Where | What it's for | Who has an account |
|---|---|---|
| Provider console (PROVIDER) | the machines, their firewalls, rescue mode | NAME, NAME |
| Coolify | the game's settings, restarts | NAME, NAME |
| GitHub (OWNER) | the module and content repositories, release tags | NAME (owner), NAME (maintainer) |
| DNS (PROVIDER) | the game's names | NAME, NAME |
| Domain registrar | renewing the domain, due YYYY-MM-DD | NAME |
| Password manager, vault "VAULT" | everything secret, below | NAME, NAME |

## Where the secrets are (all in the vault "VAULT")

| Entry | What it opens |
|---|---|
| Game host: borg passphrase and key | the off-site backups of the game host. Without it they can't be read |
| Control host: borg passphrase, key and Coolify's APP_KEY | the off-site backups of the control host and Coolify |
| Game settings (copy of ~/game/.env) | the game's passwords, if Coolify is gone |
| Staging key | nothing to keep: GitHub holds it, and a new one is a minute's work |

## A release

The whole routine is chapter 16, tier 2. In short:

1. Content changed? On the control host: `~/content/publish.sh ~/mymodule.mod`.
2. Tag the module: `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`. Wait for `staging is healthy`.
3. Join staging (GAME, port 5122) and try what the release is for.
4. Tell the players when.
5. On the game host: `sudo cp ~/staging/home/modules/mymodule.mod ~/incoming/`, plus `migrations/` if any, then
   `cd ~/game && sudo ./preflight.sh`. Every line `ok`?
6. Go live: content changed, `~/content/promote.sh` on the control host; otherwise `sudo ./release.sh` on the game
   host. The last line says `healthy`.
7. Join live. Tell the players what's new.

## A bad day

| What you see | What to do |
|---|---|
| The release says `not healthy` | `sudo ./release.sh --undo` (or `~/content/promote.sh --back` after a promote). Then read the log |
| The game won't start, even the old version | `docker logs` of the game: a missing hak, a database that's down, or the download address not answering |
| Coolify's dashboard is down | Releases still work: they don't use Coolify. Settings can't change until it's back, or use plain Compose in `~/game` |
| GitHub is down | Build at home (`nasher pack`), stage by hand, release as usual. Tag it once GitHub is back |
| Something stored in the database is wrong | `sudo ./restore-db.sh backups/...`. Everything since that backup is lost: ask first if you can |
| A machine is gone | Chapter 12's restore drill, from the off-site backups and the vault |

## Things that expire

| What | When | Who renews it |
|---|---|---|
| The domain | YYYY-MM-DD | NAME |
| API tokens (DNS, Coolify, ...) | YYYY-MM-DD | NAME |
| The provider's payment card | MM/YY | NAME |
