# Playbook 15, tier 3. Agents on machines of their own

For an agent. The chapter for people is [`chapters/15-agent-machines.md`](../chapters/15-agent-machines.md),
section "Tier 3". Follow the steps in order. Do not go on from a step whose check fails.

Run every command from the root of this repository on the person's computer (the hub). Every server-side command
goes through `ssh ... 'bash -s'` or a quoted ssh command; if an ssh fails, stop. Never run a server step on the hub.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `WORKER` | The worker's address | none: a person gives it |
| `ADMIN` | The person's admin account on the worker, with sudo | `nwn` |
| `NAME` | A short name for the worker, used for its tunnel and guide | `worker1` |
| `PORT` | The hub's local port for this worker's tunnel, free and unique per worker | `37736` |
| `TUNNEL_SSH_OPTS` | Extra ssh options for the tunnel, with full paths (systemd doesn't expand `~`) | empty |
| `SECRETS` | The worker's token file on the hub, mode 600, `NAME=value` lines | `~/.config/agent-secrets/$NAME.env` |
| `BURST` | `yes` if burst servers are wanted (chapter 1, tier 3, done) | `no` |

Secrets: the GitHub tokens in `SECRETS` and the agent tool's own token, made and placed by the person; the provider
token for burst servers, which chapter 1 placed. Never read, print or copy any of them; the scripts only move them
over SSH's standard input and print their names.

A person, not the agent, does these: makes the fine-grained tokens, installs the agent tool on the worker and its
own login (step 4), pairs and links (step 5), and says yes before any burst server is started.

## Preconditions

```sh
ssh -o BatchMode=yes $ADMIN@$WORKER 'sudo -n true && echo sudo; id agent 2>/dev/null || echo "no agent user"; findmnt -no FSTYPE --target /tmp; free -g | awk "/^Mem/{print \$2\" GB\"}"'
stat -c %a "$SECRETS"; ss -ltn | grep -c ":$PORT " || true
```

Success: `sudo`, `no agent user`, a file system type, the memory size; `600`, then `0`. If an `agent` user exists,
stop and ask. If the machine has under 6 GB, stop and ask: the fence values in `worker.env.example` need lowering.

## Steps

### 1. The agent account, its fence and its folders

```sh
scp -rq templates/agents $ADMIN@$WORKER:
ssh $ADMIN@$WORKER 'cd agents/worker && sudo STEPS="user limits secrets cleaner git" ./setup-worker.sh'
```

Success, in order: `agent: uid N, no sudo, linger on`; a line with `MemoryMax=6442450944` and `MemoryLow=2147483648`;
`/run/agent agent 700` and `tmpfs`; `active`; a path ending in `git-credential-agent`. Any `WARNING`: stop and ask.

### 2. The tokens into memory

```sh
templates/agents/hub/push-secrets.sh $ADMIN@$WORKER "$SECRETS"
```

Success: the token names, then `<- now in /run/agent/secrets.env`. Then ask the person to fill in
`~agent/.config/agent/tokens.map` on the worker if they use more than one GitHub owner.

### 3. A stand-in server, to prove the rest

```sh
ssh $ADMIN@$WORKER 'bash -s' <<'EOF'
set -euo pipefail
sudo install -D -m 644 -o agent -g agent agents/worker/agent-ui-standin.service /home/agent/.config/systemd/user/t3code.service
cd agents/worker && sudo STEPS=server ./setup-worker.sh
sudo systemctl --machine=agent@ --user daemon-reload
sudo systemctl --machine=agent@ --user enable --now t3code.service
sleep 2; curl -s http://127.0.0.1:3773/
EOF
```

Success: a path ending in `10-agent.conf`, then `agent server stand-in on ...`. If the person's agent tool uses
another unit name, set `AGENT_SERVICE` in `agents/worker/worker.env` first.

### 4. The fence, proven

```sh
ssh $ADMIN@$WORKER 'bash -s' <<'EOF'
set -euo pipefail
sudo systemd-run -q --machine=agent@ --user --unit=fence-test --collect python3 -c 'b=[bytearray(1<<30) for _ in range(9)]'
sleep 15
sudo journalctl -k --since -1min --no-pager | grep -c 'oom_memcg=/user.slice/user-' || true
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3773/
EOF
```

Success: `1` or more, then `200`. Now the person replaces the stand-in with the real agent server (chapter step 6),
runs `sudo STEPS=server ./setup-worker.sh` again, and tells you when `curl -s http://127.0.0.1:3773/` answers on the
worker.

### 5. The tunnel

```sh
install -D -m 644 templates/agents/hub/agent-tunnel@.service ~/.config/systemd/user/agent-tunnel@.service
mkdir -p ~/.config/agent-tunnels
printf 'SSH_TARGET=%s@%s\nLOCAL_PORT=%s\nREMOTE_PORT=3773\nSSH_OPTS=%s\n' $ADMIN $WORKER $PORT "${TUNNEL_SSH_OPTS:-}" > ~/.config/agent-tunnels/$NAME.env
systemctl --user daemon-reload && systemctl --user enable --now agent-tunnel@$NAME
sleep 5; systemctl --user is-active agent-tunnel@$NAME; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT/
```

Success: `active`, then `200`. Then the person pairs and links (with T3 Code: `t3 pair` on the worker,
`t3 environment link http://127.0.0.1:$PORT --pairing-code ...` on the hub).

### 6. The guard hook

```sh
ssh $ADMIN@$WORKER 'bash -s' <<'EOF'
set -euo pipefail
sudo install -D -m 755 -o agent -g agent agents/hooks/guard-push.sh /home/agent/.config/git/hooks/pre-push
sudo -u agent -i git config --global core.hooksPath /home/agent/.config/git/hooks
printf '{"tool_input":{"command":"git status"},"cwd":"/home/agent"}' | sudo -u agent -i /home/agent/.config/git/hooks/pre-push; echo "exit $?"
EOF
```

Success: `exit 0`. If the person uses Claude Code on the worker, merge `templates/agents/hooks/claude-settings.json`
into `~agent/.claude/settings.json` (keep what is there).

### 7. The guide

The person's settings are in `~/.config/agent-docs/agent-docs.env` (from `templates/agents/hub/agent-docs.env.example`),
with `$NAME` in `MACHINES`, and `~/.config/agent-docs/$NAME.md` holds the machine's notes.

```sh
python3 templates/agents/hub/agent-docs-push.py --dry-run $NAME
```

Success: `NAME: N words -> .../NAME.md`. Show the person that file and wait for their yes. Then:

```sh
python3 templates/agents/hub/agent-docs-push.py $NAME
```

Success: `NAME: pushed N words to ...`. A missing section: stop and ask (the rules file's headings changed).

### 8. The issue watcher (only if the person asked for it, on one worker)

```sh
ssh $ADMIN@$WORKER 'bash -s' <<'EOF'
set -euo pipefail
cd agents/issue-watch; h=/home/agent; i="sudo install -o agent -g agent"
$i -d $h/.config/issue-watch $h/.config/systemd/user $h/.local/bin
[ -e $h/.config/issue-watch/issue-watch.conf ] || $i -m 644 issue-watch.conf.example $h/.config/issue-watch/issue-watch.conf
$i -m 644 triage-prompt.md $h/.config/issue-watch/
$i -m 755 issue-watch.sh $h/.local/bin/issue-watch
$i -m 644 issue-watch.service issue-watch.timer $h/.config/systemd/user/
sudo ls $h/.config/issue-watch
EOF
```

Success: `issue-watch.conf  triage-prompt.md`. Then the person edits the `WATCH` table and `AGENT_CMD`. Then:

```sh
ssh $ADMIN@$WORKER 'sudo -u agent -i .local/bin/issue-watch'
ssh $ADMIN@$WORKER 'sudo -u agent -i XDG_RUNTIME_DIR=/run/user/$(id -u agent) bash -c "systemctl --user daemon-reload && systemctl --user enable --now issue-watch.timer && systemctl --user is-active issue-watch.timer"'
```

Success: one `baseline #N` line per repository, then `active`.

### 9. A burst server (only if `BURST` is `yes`, and only after the person said yes to the cost)

```sh
mkdir -p ~/.config/agent-burst && cp -n templates/agents/burst/burst.env.example ~/.config/agent-burst/burst.env
templates/agents/burst/burst.sh start test-burst cx23 0.25
templates/agents/burst/burst.sh status test-burst
```

Success: `created test-burst ...`, `self-destruct at ...`, an address; then `test-burst ADDRESS N min left`.

## Verify

```sh
ssh $ADMIN@$WORKER 'sudo -l -U agent | grep -c "may run" || true; id -nG agent; sudo systemctl show user-$(id -u agent).slice -p MemoryMax --value; systemctl is-active agent-tmp-clean.timer; sudo -u agent head -3 /home/agent/AGENTS.md | tail -1'
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT/
```

Success: `0`; `agent` alone; `6442450944`; `active`; a line starting `> Written on` with today's date; `200`.
If burst: the server is gone at its expiry without anything being done:

```sh
sleep 960; ~/.local/bin/burst-server list 2>/dev/null | grep -c test-burst || templates/provider/hcloud-servers.py list | grep -c test-burst
```

Success: `0`. Before an image is saved from any server, `scan-secrets.sh` must have ended in `SCAN-CLEAN`
(chapter step 13); otherwise stop and ask.

## Roll back

```sh
systemctl --user disable --now agent-tunnel@$NAME && rm ~/.config/agent-tunnels/$NAME.env
ssh $ADMIN@$WORKER 'bash -s' <<'EOF'
set -euo pipefail
sudo systemctl disable --now agent-tmp-clean.timer
uid=$(id -u agent)
sudo loginctl disable-linger agent; sudo loginctl terminate-user agent 2>/dev/null || true
sudo pkill -u agent || true; sleep 3
sudo userdel -r agent
sudo rm -rf /etc/systemd/system/user-$uid.slice.d /etc/systemd/system/user@$uid.service.d \
  /etc/systemd/system/user.slice.d/50-agent-memory-low.conf /etc/systemd/system/agent-tmp-clean.* \
  /usr/local/sbin/agent-tmp-clean /etc/agent /etc/tmpfiles.d/agent-secrets.conf /run/agent
sudo systemctl daemon-reload; rm -rf ~/agents
EOF
```

With T3 Code, the person also removes the link on the hub. A burst server: `templates/agents/burst/burst.sh stop NAME`.

## Stop and ask

- Before starting any server that costs money, burst servers included. Only the hub starts them, and only when the
  person said yes.
- Before saving an image from a server whose scan did not end in `SCAN-CLEAN`.
- Before anything on a worker that also runs other services (CI runners, a game), if the fence values would leave
  it less than a third of its memory.
- If any token would have to be read, printed, typed into a command line or written to a disk.
- Before changing the human rules file, its section names, or the triage prompt: they are the person's.
- Never merge, close an issue, push to a default branch, change DNS, rotate a credential or log in to the game's
  servers, here or in any step.
