# Playbook 11, tier 3, first part. Character pages

For an agent. The chapter for people is [`chapters/11-website.md`](../chapters/11-website.md), section "Tier 3,
first part". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, with `gh` signed in as someone who
may push branches to the site's repository.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on the control host | `nwn` |
| `SITE_REPO` | The site's private GitHub repository, as `owner/name`, with the status page of tier 2 | none: a person gives it |
| `SITE_HOST` | The site's name, such as `www.example.org` | none: a person gives it |
| `LINE` | One line for `characters.txt`, as the person dictates it: page name, vault folder, file, optional `gear` | none: only in step 2 |

No secret is needed beyond tier 2's. The site already holds the read key; never read it out. Never write a vault
folder (a player's CD key) into a pull request's title or description, a commit message or a message to anyone but
the person: it goes only into `characters.txt`, in the private repository.

## Preconditions

```sh
gh repo view $SITE_REPO --json visibility -q .visibility
gh api repos/$SITE_REPO/contents/status.js -q .name
curl -s https://$SITE_HOST/status.json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("state"))'
ssh $DEPLOY_USER@$CONTROL 'curl -s -o /dev/null -w "%{http_code}\n" -H @<(printf "Authorization: Bearer %s\n" "$(cat ~/ops-api/keys/read)") http://10.77.0.1:8100/api/v1/game/tlk/5'
```

Success: `PRIVATE`; `status.js`; a state such as `online`; `200`. A public repository: stop and ask, the list must
never be in one. No status page: playbook 11, tier 2, second part, first. Anything but `200` from the API:
playbook 9, tier 3 first.

## Steps

### 1. The pull request

**Ask first**: this pushes a branch `character-pages` to `SITE_REPO` and opens a pull request. After the yes:

```sh
T=$(mktemp -d); gh repo clone $SITE_REPO $T -- -q
cp templates/site/characters/* $T/
git -C $T switch -q -c character-pages && git -C $T add -A && git -C $T commit -qm "Character pages" && git -C $T push -q -u origin character-pages
(cd $T && gh pr create --head character-pages --title "Character pages" --body "Pages for the characters listed in characters.txt, read through the site's own server with the operations API's read key. The list starts empty.") | tail -1
git -C $T diff --stat HEAD~1 | tail -1; rm -rf $T
```

Success: a pull request URL, and `6 files changed` (`Dockerfile`, `nginx.conf`, `characters.js`, `characters.txt`,
`character.html`, `characters.html`).

**Tell the person**: the names and colour in the two pages are theirs to change in the pull request, and a link to
`/characters.html` on the front page is theirs to place. If their `Dockerfile` had more `COPY` lines than the status
page's, they show as removed and go back in. Ask them to merge, and to tell you when Coolify has deployed it. Then:

```sh
curl -s https://$SITE_HOST/characters.json; echo
for p in /characters.txt /characters.js /characters/nobody-at-all.json; do echo "$p $(curl -s -o /dev/null -w '%{http_code}' https://$SITE_HOST$p)"; done
```

Success: `{"characters":[]}`, then `404` three times.

### 2. A character, when its player asked

Only with a `LINE` the person gives you, for a player who asked them. Check it before anything goes anywhere:

```sh
read -r SLUG FOLDER FILE EXTRA <<< "$LINE"; [[ $SLUG =~ ^[a-z0-9-]{1,40}$ ]] && echo "name ok" || echo "bad page name"
ssh $DEPLOY_USER@$CONTROL "curl -s -o /dev/null -w '%{http_code}\n' -H @<(printf 'Authorization: Bearer %s\n' \"\$(cat ~/ops-api/keys/read)\") http://10.77.0.1:8100/api/v1/game/vault/$FOLDER/$FILE"
```

Success: `name ok`, `200`. `404`: no such folder or file in the vault; give the person the answer and stop. Then
**ask first** (a branch and a pull request on `SITE_REPO`) and, after the yes:

```sh
T=$(mktemp -d); gh repo clone $SITE_REPO $T -- -q
grep -q "^$SLUG " $T/characters.txt && echo "already listed" || { echo "$LINE" >> $T/characters.txt
  git -C $T switch -q -c "page-$SLUG" && git -C $T commit -qam "A character page: $SLUG" && git -C $T push -q -u origin "page-$SLUG"
  (cd $T && gh pr create --head "page-$SLUG" --title "A character page: $SLUG" --body "Asked for by the character's player.") | tail -1; }
rm -rf $T
```

Success: a pull request URL. Ask the person to merge it and tell you when it's deployed. Then:

```sh
curl -s https://$SITE_HOST/characters/$SLUG.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sorted(d))'
curl -sI https://$SITE_HOST/characters/$SLUG.json | grep -iE '^HTTP|cache-control'
```

Success: `['classes', 'deity', 'description', 'gender', 'level', 'name', 'race', 'slug']`, with `'gear'` among them
when the line had `gear`; `HTTP/2 200` and `cache-control: public, max-age=300`. A `404`: the site's log in Coolify
has a line starting `characters:`; stop and ask with it.

### 3. Taking a page down

Whenever the person says a player asked, without asking for anything more. **Ask first** only about the branch and
pull request; then, with `SLUG` set:

```sh
T=$(mktemp -d); gh repo clone $SITE_REPO $T -- -q
grep -q "^$SLUG " $T/characters.txt && { sed -i "/^$SLUG /d" $T/characters.txt
  git -C $T switch -q -c "remove-$SLUG" && git -C $T commit -qam "Take down a character page: $SLUG" && git -C $T push -q -u origin "remove-$SLUG"
  (cd $T && gh pr create --head "remove-$SLUG" --title "Take down a character page: $SLUG" --body "The player asked.") | tail -1; } || echo "not listed"
rm -rf $T
```

Success: a pull request URL. After the merge and the deploy:
`curl -s -o /dev/null -w '%{http_code}\n' https://$SITE_HOST/characters/$SLUG.json` says `404`.

## Verify

Nothing private may reach a browser. Run on the control host, comparing without printing:

```sh
APP_C=$(ssh $DEPLOY_USER@$CONTROL "docker ps --format '{{.Names}}' | while read n; do docker exec \$n test -f /etc/nginx/characters.js 2>/dev/null && echo \$n; done | head -1"); echo "site container: ${APP_C:-none}"
ssh $DEPLOY_USER@$CONTROL "K=\$(docker exec $APP_C printenv OPS_API_READ_KEY); F=\$(docker exec $APP_C sed 's/#.*//' /etc/nginx/characters.txt | awk 'NF>=3 {print \$2}' | sort -u); for p in / /status.html /characters.html /character.html /characters.json /characters.txt /characters.js \$(docker exec $APP_C sed 's/#.*//' /etc/nginx/characters.txt | awk 'NF>=3 {print \"/characters/\"\$1, \"/characters/\"\$1\".json\"}'); do b=\$(curl -s https://$SITE_HOST\$p); n=\$(grep -c -e \"\$K\" <<< \"\$b\"); for f in \$F; do n=\$((n + \$(grep -c -e \"\$f\" <<< \"\$b\"))); done; echo \"\$p: \$n\"; done; echo \"image history: \$(docker history --no-trunc \$(docker inspect -f '{{.Image}}' $APP_C) | grep -c \"\$K\")\""
```

Success: a container name, then `0` after every path and after `image history`. Anything else: stop at once and
tell the person what showed where.

## Roll back

Ask the person to revert the pull requests of steps 1 and 2 on GitHub and merge the reverts: the site goes back to
its status page, and every character page is gone. The site's settings in Coolify stay as tier 2 left them.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- every branch and pull request on `SITE_REPO` (steps 1, 2 and 3);
- adding any character the person didn't name, or showing more than the table in the chapter (step 21) allows;
- a public site repository, or a list line that shows on any page (Verify not `0`);
- giving the site any key but the read key, or giving the read key to anything else that shows character sheets.
