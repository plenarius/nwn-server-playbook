# Agent machines

Templates for chapter 15, tier 3: a hub (your workstation) that directs, and workers that do. Each file says
where it goes and how to install it at its top.

| Folder | What | Runs on |
|---|---|---|
| `worker/` | `setup-worker.sh` and its settings: the agent user, its fence (slice and `MemoryLow`), tokens in memory, the scratch cleaner, the credential helper, the agent server's drop-in; a stand-in server for tests | each worker, as root |
| `hub/` | `agent-tunnel@.service` and one settings file per worker; `push-secrets.sh`; `agent-docs-push.py` with its probe, guide templates and your rules file | the hub, as you |
| `burst/` | `burst.sh` (built on chapter 1's `hcloud-servers`), the server's `self-destruct`, `scan-secrets.sh` for images | the hub; the burst server |
| `hooks/` | `guard-push.sh`: no push to a branch whose pull request is finished, as a git hook and a Claude Code hook | each worker, as the agent user |
| `issue-watch/` | `issue-watch.sh`, its settings, a triage prompt, the user timer | one worker, as the agent user |
| `t3/` | T3 Code's settings on the hub and on a worker, the worked example | hub, workers |

The reaper for forgotten servers is chapter 1's (`templates/provider/`); burst servers use it unchanged.
