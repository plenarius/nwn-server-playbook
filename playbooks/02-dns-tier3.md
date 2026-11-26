# Playbook 2, tier 3. Firewall and redirect rules, kept in a file

For an agent. The chapter for people is [`chapters/02-dns.md`](../chapters/02-dns.md), section "Tier 3". Follow the
steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `RULES` | The rules file in the person's repository, shaped like `templates/dns/cf-rules.example.json` | `cloudflare/rules.json` |
| `SAVED` | A folder for the copy of the zone's rules before the change | `cloudflare/before-$(date +%F)` |
| `CHECKS` | The curl lines that show each rule working, from the chapter's step 20 with the person's names | none: write them from `RULES` and show the person |

Secrets, put in the environment by a person, never printed: `CF_ZONE_ID`, and two tokens in files the person
names, `CF_READ_TOKEN_FILE` and `CF_CHANGE_TOKEN_FILE` (chapter step 15). Use the change token only inside step 4's
command. Never retry a token Cloudflare refused: repeated failures lock the person's address out for minutes.

## Preconditions

```sh
export CF_ZONE_ID
CF_API_TOKEN=$(cat "$CF_READ_TOKEN_FILE") templates/dns/cf-rules.py plan "$RULES"
```

Success: one line per rule, each `add`, `change`, `remove` or `keep`. `must start with` or `unknown phase`: the file
is wrong; show the person. `Cloudflare said: ...`: stop and ask.

Every rule's expression names a host the person owns, and every redirect excludes
`/.well-known/acme-challenge/`:

```sh
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [print(r["ref"], "host" if "http.host" in r["expression"] else "NO HOST", "" if r["action"]!="redirect" or "acme-challenge" in r["expression"] else "NO ACME EXCLUSION") for p in d["phases"].values() for r in p]' "$RULES"
```

Success: `host` on every line and no `NO ACME EXCLUSION`. Otherwise stop and ask.

## Steps

### 1. Save the zone's rules

```sh
CF_API_TOKEN=$(cat "$CF_READ_TOKEN_FILE") templates/dns/cf-rules.py export "$SAVED"
```

Success: three lines `...: N rules saved`, and three files in `$SAVED`.

### 2. Show the plan

```sh
CF_API_TOKEN=$(cat "$CF_READ_TOKEN_FILE") templates/dns/cf-rules.py plan "$RULES"
```

Give the person this output, the diff of `$RULES` and `CHECKS`. **Wait for their yes** to this plan. A `remove` line
deserves a sentence of its own: say which rule goes.

### 3. Note what the zone's other rules look like

```sh
python3 -c 'import json,sys,glob; [print(f.rsplit("/",1)[1], [r["id"] for r in json.load(open(f))["rules"] if not r.get("ref","").startswith(sys.argv[2]+"-")]) for f in sorted(glob.glob(sys.argv[1]+"/*.json"))]' "$SAVED" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["owner"])' "$RULES")" > "$SAVED/others.txt"; cat "$SAVED/others.txt"
```

Success: one line per phase listing the ids of rules the file doesn't own. Verify checks they're unchanged.

### 4. Apply

Only after the person's yes in step 2, and only for that plan.

```sh
CF_API_TOKEN=$(cat "$CF_CHANGE_TOKEN_FILE") templates/dns/cf-rules.py apply "$RULES"
```

Success: one line per rule, `added`, `changed`, `removed` or `same`, matching the plan. `Cloudflare said: ...`:
stop, report the message, run step 2 again to show where it got to, and ask.

## Verify

```sh
CF_API_TOKEN=$(cat "$CF_READ_TOKEN_FILE") templates/dns/cf-rules.py plan "$RULES"
CF_API_TOKEN=$(cat "$CF_READ_TOKEN_FILE") templates/dns/cf-rules.py export "$SAVED-after" >/dev/null
python3 -c 'import json,sys,glob; [print(f.rsplit("/",1)[1], [r["id"] for r in json.load(open(f))["rules"] if not r.get("ref","").startswith(sys.argv[2]+"-")]) for f in sorted(glob.glob(sys.argv[1]+"/*.json"))]' "$SAVED-after" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["owner"])' "$RULES")" | diff "$SAVED/others.txt" - && echo "others unchanged"
```

Success: `keep` on every line, then `others unchanged`.

Then run `CHECKS`. Success: each answer as written beside it. A rule can take up to half a minute to work
everywhere: if an answer is wrong, run that line again once after 30 seconds before calling it a failure.

## Roll back

```sh
git -C "$(dirname "$RULES")" log --oneline -2 -- "$(basename "$RULES")"
```

Put the file back to the commit before the change (`git checkout HEAD~1 -- "$RULES"` or as the person prefers),
then steps 2 and 4 with it: the plan should show the reverse of the change. Success: Verify passes with the old
file. To take away everything the file owns:

```sh
CF_API_TOKEN=$(cat "$CF_CHANGE_TOKEN_FILE") templates/dns/cf-rules.py remove "$RULES"
```

Success: `removed ...` for each rule, and a `plan` afterwards shows each as `add`. Rules the file doesn't own are
never touched; to restore one of those, hand the person the file in `$SAVED`.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- every `apply` and every `remove`, each with its plan;
- a rule without a host in its expression, or a redirect without the ACME exclusion;
- a rule that blocks or challenges a path a script or another site of the person's fetches (a shared header, a
  webhook, an API the game calls): ask what fetches it first;
- blocking requests with an empty user agent;
- a `remove` line in the plan the person didn't ask for;
- `others unchanged` not printed;
- any change to DNS records, proxy status or zone settings: those are chapter 2's other playbooks;
- a refused token.
