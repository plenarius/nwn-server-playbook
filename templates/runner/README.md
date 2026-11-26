# Self-hosted runners, one job each

Chapter 8, tier 3, of the guide walks through these. They run on your control host or a build machine, never on
the game host.

| File | What it is |
|---|---|
| `Dockerfile` | The runner image: GitHub's own, plus the GitHub CLI and Docker Compose, without sudo, with the hook |
| `hooks/job-started.sh` | Runs before every job and refuses jobs from forks, from comments, and from other repositories |
| `runners.sh` | Keeps a few runners waiting; each takes one job with a Docker of its own, and is then thrown away |
| `runners.conf.example` | Its settings: the repository, how many runners, each one's share of the machine, the caches |
| `nwn-runners.service` | Runs `runners.sh` as a service |

Needs Docker and `jq` on the machine, and a fine-grained token for the repository with "Administration: Read and
write" in `/etc/nwn-runners/token`, readable by root only.
