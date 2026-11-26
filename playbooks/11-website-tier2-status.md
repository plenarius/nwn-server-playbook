# Playbook 11, tier 2, second part. A live status page

For an agent. The chapter for people is [`chapters/11-website.md`](../chapters/11-website.md), section "Tier 2,
second part". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer, with `gh` signed in as someone who
may push branches to the site's repository.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on the control host | `nwn` |
| `SITE_REPO` | The site's private GitHub repository, as `owner/name`, with `index.html` and the `Dockerfile` at its root | none: a person gives it |
| `SITE_HOST` | The site's name, such as `www.example.org` | none: a person gives it |
| `OPS_API_URL` | The operations API's private address, as chapter 9 sets it up | `http://10.77.0.1:8100` |

Secrets: `COOLIFY_TOKEN` (Root), placed by a person as in playbook 3. The team key of the operations API is placed
in Coolify by a person, never by you: you only check that it is there. Never print it, never print an API response
that lists environment values, and never copy it into a file, a commit, a pull request or a message.

## Preconditions

```sh
ssh -f -N -L 8000:localhost:8000 $DEPLOY_USER@$CONTROL 2>/dev/null
cl() { curl -s -X "$1" -H @<(printf 'Authorization: Bearer %s\n' "$COOLIFY_TOKEN") -H 'Content-Type: application/json' ${3:+-d "$3"} "http://localhost:8000/api/v1$2"; }
APP=$(cl GET /applications | python3 -c 'import json,sys; r=[a["uuid"] for a in json.load(sys.stdin) if a["name"]=="website"]; print(r[0] if len(r)==1 else "")'); echo "application: ${APP:-none or several}"
ssh $DEPLOY_USER@$CONTROL "curl -s -m 5 ${OPS_API_URL:-http://10.77.0.1:8100}/health"; echo
gh repo view $SITE_REPO --json visibility -q .visibility
gh api repos/$SITE_REPO/contents/index.html -q .name
```

Success: one id; `{"status":"ok"}`; `PRIVATE`; `index.html`. No application named `website`: playbook 11, tier 2
first. No answer from the API: chapter 9 first. Anything else: stop and ask.

## Steps

### 1. The pull request

**Ask first**: this pushes a branch `status-page` to `SITE_REPO` and opens a pull request. After the yes:

```sh
T=$(mktemp -d); gh repo clone $SITE_REPO $T -- -q
cp templates/site/status/* $T/
git -C $T switch -q -c status-page && git -C $T add -A && git -C $T commit -qm "A live status page" && git -C $T push -q -u origin status-page
(cd $T && gh pr create --head status-page --title "A live status page" --body "Status page reading the operations API through the site's own server. Needs OPS_API_URL and OPS_API_TEAM_KEY in Coolify, run time only.") | tail -1
git -C $T diff --stat HEAD~1 | tail -1; rm -rf $T
```

Success: a pull request URL, and `4 files changed` (`Dockerfile`, `nginx.conf`, `status.html`, `status.js`).

**Tell the person**: the names in `status.html` (`<title>`, `<h1>`) and its colour are theirs to change in the pull
request, and the front page needs a link to `/status.html` where they want it. Don't write those words yourself.
Ask them not to merge until step 2 is done. If their old `Dockerfile` had more `COPY` lines, they show in the diff
as removed: they go back into the new one.

### 2. The settings in Coolify

```sh
cl POST /applications/$APP/envs "{\"key\":\"OPS_API_URL\",\"value\":\"${OPS_API_URL:-http://10.77.0.1:8100}\",\"is_buildtime\":false,\"is_runtime\":true,\"is_preview\":false}" | python3 -c 'import json,sys; print("set" if "uuid" in json.load(sys.stdin) else "FAILED")'
```

Success: `set`.

**Ask the person** to add `OPS_API_TEAM_KEY` in the website application's **Environment Variables** in Coolify,
with chapter 9's team key as its value, "Available at Buildtime" unticked and "Available at Runtime" ticked. Wait
for their yes. Then remove the copies Coolify keeps for pull request previews, and check:

```sh
for u in $(cl GET /applications/$APP/envs | python3 -c 'import json,sys; [print(e["uuid"]) for e in json.load(sys.stdin) if e["is_preview"] and e["key"].startswith("OPS_API_")]'); do cl DELETE /applications/$APP/envs/$u > /dev/null; done
cl GET /applications/$APP/envs | python3 -c 'import json,sys
for e in json.load(sys.stdin):
    if e["key"].startswith("OPS_API_"): print(e["key"], "preview" if e["is_preview"] else "production", "buildtime" if e["is_buildtime"] else "-", "runtime" if e["is_runtime"] else "-")'
```

Success: exactly `OPS_API_TEAM_KEY production - runtime` and `OPS_API_URL production - runtime`, in either order.
`buildtime` on the key: ask the person to untick it; the key would otherwise be written into the image.

### 3. Merge, deploy, check

Ask the person to merge the pull request, and tell you when. Then:

```sh
for i in $(seq 40); do st=$(cl GET "/deployments/applications/$APP?take=1" | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d.get("deployments",d) if isinstance(d,dict) else d; print(d[0]["status"] if d else "none")'); [ "$st" = finished ] || [ "$st" = failed ] && break; sleep 6; done; echo "deploy: $st"
sleep 5; curl -sI https://$SITE_HOST/status.json | grep -iE '^HTTP|cache-control|x-status-cache'
curl -sI https://$SITE_HOST/status.json | grep -i x-status-cache
curl -s https://$SITE_HOST/status.json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("state"), d.get("players"), d.get("module"))'
```

Success: `deploy: finished`; `HTTP/2 200`, `cache-control: public, max-age=30`, `x-status-cache: MISS` (or `HIT`);
`x-status-cache: HIT`; then the state, the player count and the module, such as `online 0 mymodule`.

If the last line fails or says nothing useful, `curl -s https://$SITE_HOST/status.json` shows the error, and the
site's log in Coolify has a line starting `status:`. `not set up`: step 2 is missing a setting. `the operations API
did not answer`: the API isn't running or `OPS_API_URL` is wrong. Stop and ask with that line.

## Verify

The key must be in the running container and nowhere a browser or the image can show it. The key is read and
compared on the control host and never printed:

```sh
ssh $DEPLOY_USER@$CONTROL "C=\$(docker ps --format '{{.Names}}' | grep -m1 $APP); K=\$(docker exec \$C printenv OPS_API_TEAM_KEY); [ \${#K} -ge 16 ] || { echo 'no key in the container'; exit 1; }; echo \"image history: \$(docker history --no-trunc \$(docker inspect -f '{{.Image}}' \$C) | grep -c \"\$K\")\"; for p in / /status.html /status.json /status.js /nginx.conf; do echo \"\$p: \$(curl -s https://$SITE_HOST\$p | grep -c \"\$K\")\"; done"
```

Success: `image history: 0` and `0` after each path. Then ask the person to open `https://SITE_HOST/status.html` and
confirm they see "Online" (or "Offline" if the game is down), with the player count.

Anything other than 0: stop at once and tell the person the key is exposed. They change the team key in the API
(chapter 9) and in Coolify, and you look for where it leaked before anything else.

## Roll back

Ask the person to revert the pull request on GitHub and merge the revert; the site goes back to the plain
two-line `Dockerfile` and has no status page. Then remove both settings:

```sh
for u in $(cl GET /applications/$APP/envs | python3 -c 'import json,sys; [print(e["uuid"]) for e in json.load(sys.stdin) if e["key"].startswith("OPS_API_")]'); do cl DELETE /applications/$APP/envs/$u > /dev/null; done
```

## Stop and ask

Hand back to a person, with what you found, before any of these:

- step 1, always, and any change to the words on the person's pages;
- placing, changing or reading out the team key;
- a check in Verify that isn't 0;
- a repository that isn't private, or whose `Dockerfile` has `COPY` lines the template doesn't.
