# Playbook 16, tier 3. The expiry calendar and the release train

For an agent. The chapter for people is [`chapters/16-releasing.md`](../chapters/16-releasing.md), section "Tier
3". Follow the steps in order. Do not go on from a step whose check fails.

You install and check the expiry calendar, set up the release train, and read the notes before a release. **A
person says yes before step 5 (the rule set), before every `freeze.sh start` and every `freeze.sh end`.** An
earlier or general go-ahead does not count. You never renew anything: a token, a card, a domain or a certificate is
the person's to renew. You may change a date in the calendar only after they say it was renewed.

`GUIDE` is the root of this repository on the person's computer.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `GUIDE` | Where this repository is | none: a person gives it |
| `REPO_DIR` | The module's repository | `~/mymodule` |
| `GH_REPO` | Its GitHub repository, `owner/name` | none: a person gives it |
| `CONTROL` | The control host's public address | none: a person gives it |
| `DEPLOY_USER` | The deploy user on the control host | `nwn` |
| `VERSION` | The coming release's tag, `vX.Y.Z` | none: a person gives it |

Secrets: none pass through you. The checker reads the watchdog's webhook file itself. Step 30's token commands
are the person's to run; never run them with a token you were handed, and never print a token file.

## Preconditions

```sh
ssh $DEPLOY_USER@$CONTROL 'systemctl is-active nwn-watchdog.timer; sudo test -r /etc/nwn-watchdog/watchdog.conf && echo "watchdog conf ok"'
test -f "$REPO_DIR/expiry.list" && echo "calendar ok"
gh repo view $GH_REPO --json visibility -q .visibility
```

Success: `active`, `watchdog conf ok`, `calendar ok`. If there is no calendar, copy
`$GUIDE/templates/expiry/expiry.list.example` to `$REPO_DIR/expiry.list` and give it to the person to fill in
(chapter step 29); you may fill in lines the checker reads by itself (`cert`, `domain`, `eol`) from names they give
you. If the visibility is `PRIVATE`, rule sets need a paid plan: say so before step 5.

## Steps

### 1. Read the calendar locally

```sh
python3 "$GUIDE/templates/expiry/nwn-expiry.py" check "$REPO_DIR/expiry.list"
```

Success: one line per calendar line, soonest first, no `FAIL`. A `FAIL` on a `domain` line whose registry has no
RDAP: tell the person to write it as a `date` line. A stop with a line number is a mistake in the file: show the
line and ask.

### 2. Install it beside the watchdog

```sh
cd "$GUIDE" && scp -r templates/expiry $DEPLOY_USER@$CONTROL:expiry && scp "$REPO_DIR/expiry.list" $DEPLOY_USER@$CONTROL:expiry/
ssh $DEPLOY_USER@$CONTROL 'sudo install -m 755 expiry/nwn-expiry.py /usr/local/bin/nwn-expiry && sudo install -d -m 755 /etc/nwn-expiry && sudo install -m 644 expiry/expiry.list /etc/nwn-expiry/ && sudo install -m 644 expiry/nwn-expiry.service expiry/nwn-expiry.timer /etc/systemd/system/ && sudo systemctl daemon-reload && echo installed'
ssh $DEPLOY_USER@$CONTROL 'sudo -u nwn-watchdog nwn-expiry check /etc/nwn-expiry/expiry.list; sudo -u nwn-watchdog nwn-expiry test'
```

Success: `installed`, the same list as step 1, `sent`. Ask the person whether "expiry warnings arrive here"
reached the channel; do not go on until they say yes.

### 3. Start the timer

```sh
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl start nwn-expiry.service && sudo journalctl -u nwn-expiry.service -n 8 -o cat --no-pager'
ssh $DEPLOY_USER@$CONTROL 'sudo systemctl enable --now nwn-expiry.timer && systemctl list-timers nwn-expiry.timer --no-pager'
```

Success: `Finished`, and the timer listed with a next run.

### 4. The labels and the notes' groups

```sh
cd "$REPO_DIR" && test -f .github/release.yml || cp "$GUIDE/templates/module/.github/release.yml" .github/
"$GUIDE/templates/module/tools/release-labels.sh" $GH_REPO
```

Success: one `label ...` line per label. Copy `release-train.yml`, `tools/freeze.sh`, `tools/release-labels.sh` and
`tools/release-train-ruleset.json` from `$GUIDE/templates/module/`, and chapter 6's changed "Make the release"
step, into a branch, and open a pull request. The person merges it.

### 5. The rule set (ask first)

After the pull request from step 4 is merged and the person says yes:

```sh
cd "$REPO_DIR" && gh api -X POST repos/$GH_REPO/rulesets --input tools/release-train-ruleset.json -q '.name + " " + .enforcement'
```

Success: `release train active`. Then open any small pull request without a label: its `label` check must be red.

### 6. A freeze (ask first, each time)

```sh
cd "$REPO_DIR" && tools/freeze.sh start 48 && tools/freeze.sh status
```

Success: `main is frozen until ...`, and every open pull request without `release-fix` shows a red `freeze`
check. Label a pull request `release-fix` only when the person says it is a fix for this release.

### 7. Read the notes

```sh
cd "$REPO_DIR" && tools/freeze.sh notes $VERSION
```

Show the person the output. Point out titles a player wouldn't understand, and any change that looks like an
exploit fix or a quest spoiler without `no-changelog`. You change titles and labels only when they say so.

### 8. Lift the freeze (ask first)

After the release is live (tier 2's playbook):

```sh
cd "$REPO_DIR" && tools/freeze.sh end && tools/freeze.sh status
```

Success: `the freeze is lifted`, `not frozen`, and the waiting pull requests' checks re-run green.

## When the checker warns

Report the warning's line and note to the person. When they say it is renewed: for a `cert`, `domain` or `eol`
line, run step 1 and confirm the new date; for a `date` or `every` line, change the date in a pull request, and
after it merges copy the file across:

```sh
scp "$REPO_DIR/expiry.list" $DEPLOY_USER@$CONTROL:expiry/ && ssh $DEPLOY_USER@$CONTROL 'sudo install -m 644 expiry/expiry.list /etc/nwn-expiry/'
```
