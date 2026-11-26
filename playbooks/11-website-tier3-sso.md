# Playbook 11, tier 3, second part. One account for the website, a forum and a wiki

For an agent. The chapter for people is [`chapters/11-website.md`](../chapters/11-website.md), section "Tier 3,
second part". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, with `gh` signed in as someone who may
create private repositories and push branches to the site's repository. Run nothing on the control host except
through `ssh $DEPLOY_USER@$CONTROL 'bash -s' < file` or a single quoted command, and stop if `ssh` fails.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on the control host | `nwn` |
| `DOMAIN` | The world's domain, such as `example.org` | none: a person gives it |
| `SITE_REPO` | The website's private GitHub repository, as `owner/name` (tier 2) | none: a person gives it |
| `ID_REPO` | The new identity repository's name | `identity` |

The sites' names are `www.$DOMAIN`, `auth.$DOMAIN`, `forum.$DOMAIN` and `wiki.$DOMAIN`. Secrets go only into a file
of mode 600 that the person moves into their password manager and Coolify; never print one, never put one in a
commit, a pull request or a message.

## Preconditions

```sh
gh repo view $SITE_REPO --json visibility -q .visibility
curl -s -o /dev/null -w '%{http_code}\n' https://www.$DOMAIN/
ssh $DEPLOY_USER@$CONTROL 'docker ps --format "{{.Names}}" | grep -cx coolify; free -g | awk "/Mem:/ {print \$7}"'
for h in auth forum wiki; do templates/dns/cf-record.sh show $h.$DOMAIN | tail -1; done
```

Success: `PRIVATE`; `200`; `1` and a number of free gigabytes of at least `4`; three records pointing at `CONTROL`,
`auth` **dns-only** and the other two **proxied**. Missing records: chapter 2's script makes them, after asking.
Less than 4 GB free: stop and ask (a bigger control host is the person's choice and money).

## Steps

### 1. The identity repository

**Ask first**: this creates the private repository `ID_REPO` and pushes to it. After the yes:

```sh
T=$(mktemp -d); mkdir $T/auth $T/forum $T/wiki
cp -r templates/identity/authentik/* $T/auth/ && cp templates/identity/forum/* $T/forum/ && cp templates/identity/wiki/* $T/wiki/
git -C $T init -q -b main && git -C $T add -A && git -C $T commit -qm "Sign-in, forum and wiki"
(cd $T && gh repo create $ID_REPO --private --source . --push) | tail -1
ls $T/auth/blueprints; rm -rf $T
```

Success: the repository's URL, then `00-brand.yaml 10-sites.yaml 20-join.yaml 30-team-mfa.yaml`.

**Tell the person**: the world's name and colours in `auth/blueprints/00-brand.yaml` are theirs to change, by pull
request; and Coolify needs a deploy key for this repository, as for the website (tier 2, step 9).

### 2. The secrets

```sh
F=~/identity-secrets.env; umask 077; : > $F
for s in PG_PASS AUTHENTIK_SECRET_KEY BOOTSTRAP_PASSWORD WEBSITE_CLIENT_SECRET FORUM_CLIENT_SECRET \
         WIKI_CLIENT_SECRET SESSION_SECRET FORUM_DB_PASSWORD WIKI_DB_PASSWORD WIKI_SECRET_KEY; do
  echo "$s=$(openssl rand -hex 32)" >> $F; done
stat -c '%a %n' $F; cut -d= -f1 $F | tr '\n' ' '; echo
```

Success: `600 /home/.../identity-secrets.env` and the ten names. **Tell the person**: the file holds every secret
of chapter 11's steps 29, 31, 32 and 33; they put each into Coolify and their password manager, then delete the
file. Hand them the chapter's step 29 now: they make the Authentik application in Coolify and deploy it. Wait for
them to say it's deployed.

### 3. Authentik answers

```sh
A=https://auth.$DOMAIN
templates/identity/authentik/check-sign-in.sh $A website https://www.$DOMAIN/auth/callback \
  forum "https://forum.$DOMAIN/auth/oidc?provider=authentik" wiki https://wiki.$DOMAIN/index.php/Special:PluggableAuthLogin
curl -s $A/api/v3/flows/executor/initial-setup/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["component"])'
curl -s $A/api/v3/flows/executor/default-authentication-flow/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["flow_info"]["title"])'
```

Success: `website: ok`, `forum: ok`, `wiki: ok`; `ak-stage-access-denied`; the heading from `00-brand.yaml`. A
`refused` line: the provider's redirect address or grant types (the chapter's step 28); stop and ask with the line.
Anything but `ak-stage-access-denied` for the first-run page: **stop at once** and tell the person that Authentik's
admin password can be set by anyone (`BOOTSTRAP_PASSWORD` was missing at the first start). A first start takes up to
five minutes; ask again before deciding.

**Tell the person**: chapter 11, step 29's points 1 and 2 (change `akadmin`'s password, make their own account in
`team` and `authentik Admins`) are theirs.

### 4. The website's sign-in

**Ask first**: a branch `sign-in` and a pull request on `SITE_REPO`. After the yes:

```sh
T=$(mktemp -d); gh repo clone $SITE_REPO $T -- -q
cp -r templates/site/sso/* $T/
sed -i "s#https://auth.example.org/#https://auth.$DOMAIN/#" $T/account.html
git -C $T switch -q -c sign-in && git -C $T add -A && git -C $T commit -qm "Sign-in with Authentik, and the shared header" && git -C $T push -q -u origin sign-in
(cd $T && gh pr create --head sign-in --title "Sign-in with Authentik, and the shared header" --body "One account for the website, forum and wiki, through Authentik. Needs the AUTH_*, SITE_URL, SESSION_SECRET and SSO_COOKIE_DOMAIN settings in Coolify before the merge.") | tail -1
git -C $T diff --stat HEAD~1 | tail -1; rm -rf $T
```

Success: a pull request URL and the files changed. **Tell the person**: the names and links in
`embed/header.html` are theirs; the three lines of step 31 go into each of their own pages; the six settings of
step 31 go into Coolify **before** they merge. After the merge and deploy:

```sh
curl -s https://www.$DOMAIN/auth/me; echo
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "https://www.$DOMAIN/auth/login?returnTo=/"
curl -s https://www.$DOMAIN/embed/header.html | grep -c 'class="shell"'
```

Success: `{"signedIn":false}`; `302 https://auth.$DOMAIN/application/o/authorize/?...`; `1`. A `502` from the login:
the site's log in Coolify has a line starting `auth:`; stop and ask with it.

### 5. The forum and the wiki

Hand the person the chapter's steps 32 and 33: they make the two applications in Coolify and deploy them. Then:

```sh
for s in forum wiki; do echo "$s: $(curl -s -o /dev/null -w '%{http_code}' -L https://$s.$DOMAIN/)"; done
curl -s -o /dev/null -w 'forum sign-in: %{redirect_url}\n' "https://forum.$DOMAIN/auth/oidc?provider=authentik"
J=$(mktemp); tok=$(curl -s -c $J https://forum.$DOMAIN/ | grep -o '"csrfToken":"[^"]*"' | cut -d'"' -f4)
for r in login register; do curl -s -b $J -o /dev/null -w "forum password $r: %{http_code}\n" -X POST -H "X-CSRF-Token: $tok" -H 'Content-Type: application/json' -d '{"identification":"x","username":"x","email":"x@example.org","password":"xxxxxxxxxx"}' https://forum.$DOMAIN/$r; done; rm -f $J
curl -s -o /dev/null -w 'wiki sign-in: %{redirect_url}\n' "https://wiki.$DOMAIN/index.php?title=Special:UserLogin"
for s in forum wiki; do echo "$s header: $(curl -s -L https://$s.$DOMAIN/ | grep -c 'class="shell"')"; done
```

Success: `forum: 200`, `wiki: 200`; the forum's sign-in going to `https://auth.$DOMAIN/application/o/authorize/?...`;
`forum password login: 403` and `forum password register: 403`; the wiki's sign-in going to `.../Special:PluggableAuthLogin`; `1` for each header (the
header appears up to ten minutes after the website has it). The first start of each takes a few minutes; ask again
before deciding.

**Tell the person**: chapter 11, step 34 is theirs to do in a private browser window, once as a member and once as
themselves.

### 6. The nightly dumps

Only on a control host that has chapter 12's tier 2 backups (`/etc/nwn-borg/hooks.d` exists). **Ask first**: this
installs a hook on the control host. After the yes:

```sh
scp templates/backup/hooks/20-site-dbs.sh $DEPLOY_USER@$CONTROL:
ssh $DEPLOY_USER@$CONTROL 'sudo install -m 700 20-site-dbs.sh /etc/nwn-borg/hooks.d/ && rm 20-site-dbs.sh && sudo /etc/nwn-borg/hooks.d/20-site-dbs.sh && sudo ls /var/backups/nwn-borg/ | grep ^site-'
```

Success: `site-authentik.sql`, `site-forum.sql`, `site-wiki.sql`. A line `the dump of ... failed`: stop and ask with
it.

## Verify

```sh
templates/identity/authentik/check-sign-in.sh https://auth.$DOMAIN website https://www.$DOMAIN/auth/callback \
  forum "https://forum.$DOMAIN/auth/oidc?provider=authentik" wiki https://wiki.$DOMAIN/index.php/Special:PluggableAuthLogin; echo "exit $?"
curl -s https://auth.$DOMAIN/api/v3/flows/executor/initial-setup/ | python3 -c 'import json,sys; print(json.load(sys.stdin)["component"])'
for p in /auth/me /embed/header.html /embed/shell.css; do echo "$p $(curl -s -o /dev/null -w '%{http_code}' https://www.$DOMAIN$p)"; done
gh api repos/$SITE_REPO/contents/auth.js -q .name; gh repo view $ID_REPO --json visibility -q .visibility
```

Success: three `ok` lines and `exit 0`; `ak-stage-access-denied`; `200` three times; `auth.js`; `PRIVATE`.

## Roll back

Ask the person to revert the website's pull request (step 4) and merge the revert: the site goes back to its pages
without sign-in. They stop and delete the forum, wiki and Authentik applications in Coolify (their volumes go with
them: take step 6's dumps first if anything in them matters), and you delete the three DNS records with chapter 2's
script after asking. Remove `/etc/nwn-borg/hooks.d/20-site-dbs.sh` from the control host after asking. The identity
repository stays; deleting it is the person's choice.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- creating or pushing to any repository, every branch and pull request (steps 1 and 4), and the hook on the control
  host (step 6);
- making accounts, invitations or groups in Authentik, or changing anything in its admin pages: accounts are a
  person's job, and everything else goes in a blueprint by pull request;
- making, changing or deleting Coolify applications, their settings or volumes; DNS records;
- a first-run page that doesn't say `ak-stage-access-denied` (step 3): stop at once;
- any secret that shows up in output, a log, a page or a file in a repository: stop at once and say where;
- making an OAuth2 provider any way but the blueprint, or a `refused` line from `check-sign-in.sh`;
- a control host with less than 4 GB of memory free;
- restoring a database (chapter 11, step 36): a person decides when to wind Authentik back.
