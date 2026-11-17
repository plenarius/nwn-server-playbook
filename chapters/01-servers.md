# Chapter 1. Choosing and preparing servers

**Status:** tier 1 is written and tested. Tiers 2 and 3 (a second machine, the private network between machines,
a provider token for scripts) are not written yet.

## What you learn

How to pick one machine for a tier 1 server, and how to turn a fresh cloud server into a safe host for a game
server that runs in Docker. At the end you have:

- a machine you log in to with an SSH key, as your own user, never as root and never with a password;
- two firewalls, the provider's and the host's, that let in SSH, the game and (if you want a website) the web;
- Docker and Compose, set so that a Docker update does not stop your game and logs cannot fill the disk;
- a machine that comes back from a reboot exactly as it went down.

Every later chapter assumes this one is done.

**Time:** the script took about 3 minutes on the test machine. Allow about 15 minutes in all, with renting the
machine and doing the checks; that second figure is an estimate.

## What Layonara does

Layonara runs four machines. Tier 1 needs one, so only the game host matters here.

- **The game host** is a Hetzner cloud server with 2 dedicated cores, 8 GB of memory and an 80 GB disk. It runs
  the game server, its MariaDB database and Redis, all in Docker, and nothing else.
- **What the game uses.** With nobody online, the game process used 27% of one core and 620 MB of memory.
- **What it costs.** That machine is on an old price of €16.99 a month. The same type is listed at €43.49 today.
- **Its settings** are the ones this chapter gives you: Ubuntu 26.04 LTS, the clock on UTC, SSH with keys only and
  no root login, `ufw` allowing SSH and the game port, Docker with `live-restore` and a log cap of three 10 MB
  files per container, a 2 GB swap file, automatic security updates, and cloud-init switched off.
- **Why Hetzner.** Its API lets scripts create a server, label it and delete it. Layonara's later tiers use that
  for short-lived servers. For tier 1 any provider that gives you a fresh Ubuntu server and a firewall will do.

Layonara's game host also allows TCP on the game port. The game itself uses UDP, and this chapter opens UDP only.

## The human playbook

Each step is marked GENERIC (the same for any server), ADAPT (works with the named changes) or LAYONARA-ONLY
(shown so you do not copy it).

The commands in steps 4 to 7 come from one script, [`templates/host/prepare-host.sh`](../templates/host/prepare-host.sh),
and one settings file, [`templates/host/daemon.json`](../templates/host/daemon.json). Read the script before you
run it. It is short, and each step in it checks before it changes anything, so running it twice is safe.

### 1. GENERIC. Decide what the machine is for

In tier 1 one machine does everything: the game, its database, and later a small website. You do not need a
second machine until tier 2.

### 2. ADAPT. Rent the machine

Change: the provider, the region, the size.

- **Image:** Ubuntu 26.04 LTS. The script reads the release name from the machine, so another current Ubuntu LTS
  should work, but 26.04 is the one tested.
- **SSH key:** add your public key when you create the server, so the provider puts it in root's account. The
  script copies it from there to your own user.
- **Size:** Layonara's game host has 2 dedicated cores and 8 GB. Dedicated cores cost more than shared ones; on
  shared cores your game runs beside other customers' work. The steps in this chapter were tested on the smallest
  shared type (2 cores, 4 GB, about €0.009 an hour). That is enough to follow this chapter. No game with players
  has been run on it for this guide.
- **Region:** near your players.

### 3. ADAPT. Set the provider's firewall

Change: where your provider keeps this setting. At Hetzner it is "Firewalls" in the project.

Allow these inbound, for IPv4 and IPv6, and nothing else:

| Port | Protocol | For |
|---|---|---|
| 22 | TCP | SSH |
| 5121 | UDP | The game |
| 80 and 443 | TCP | A website, only if this machine will serve one |
| | ICMP | Ping |

Do not skip this because the host has a firewall too. Step 6 shows why you need both.

### 4. GENERIC. Copy the templates and make your own user

From your own computer, with the server's address in place of `SERVER`:

```sh
scp -r templates/host root@SERVER:/root/host
ssh root@SERVER 'cd /root/host && STEPS="updates user" ./prepare-host.sh'
```

This installs pending updates and creates the user `nwn` (set `DEPLOY_USER=yourname` to choose another name). The
user gets root's SSH keys and may use `sudo` without a password, because the account has no password to ask for.

**Check, before you go on:** log in as the new user from a second terminal.

```sh
ssh nwn@SERVER 'whoami; sudo -n true && echo "sudo ok"'
```

It must print `nwn` and `sudo ok`. The next step closes root's door, so do not run it until this works.

### 5. GENERIC. Run the rest

```sh
ssh nwn@SERVER 'sudo cp -r /root/host ~/host && sudo chown -R nwn: ~/host'
ssh nwn@SERVER 'cd ~/host && sudo STEPS="ssh firewall docker swap clock cloudinit" ./prepare-host.sh'
```

Add `ALLOW_WEB=1` after `sudo` if this machine will serve a website. What each step does:

| Step | What it does | How to check it |
|---|---|---|
| `ssh` | Keys only; no passwords; no root login | `ssh root@SERVER` is refused with `Permission denied (publickey)` |
| `firewall` | `ufw` denies everything inbound except SSH, the game port and, if asked, 80 and 443 | `sudo ufw status` lists exactly those |
| `docker` | Docker Engine and Compose from Docker's own package repository, with `daemon.json`; adds your user to the `docker` group | `sudo docker info --format '{{.LiveRestoreEnabled}}'` prints `true` |
| `swap` | A 2 GB swap file (`SWAP_GB=0` for none) | `swapon --show` lists `/swapfile` |
| `clock` | Sets the time zone to UTC, so logs and schedules on every machine agree | `timedatectl` shows `Etc/UTC` |
| `cloudinit` | Switches cloud-init off and keeps the network file it wrote | `cloud-init status` prints `disabled` after the next boot |

Log out and in again once, so your user picks up the `docker` group.

### 6. GENERIC. Know the one thing the host firewall does not cover

**A port that Docker publishes is open to the internet even when `ufw` has no rule for it.** Docker writes its own
firewall rules, and they are checked before `ufw`'s.

This was tested on the machine from this chapter. A container started with `-p 8080:80` answered from outside
although `ufw` allowed only 22, 5121, 80 and 443. Two things stopped it:

- **Publishing on the machine's own address only:** the same container started with `-p 127.0.0.1:8081:80` could
  not be reached from outside.
- **The provider's firewall from step 3:** with it on, port 8080 could not be reached from outside either.

So the rule for every later chapter: a database, Redis or any service that only this machine uses is published on
`127.0.0.1`, or not published at all. Only the game port and the web ports are published to everyone. The
provider's firewall is there for the day someone forgets.

### 7. GENERIC. Reboot once and check

```sh
ssh nwn@SERVER 'sudo reboot'
```

Wait a minute, then:

```sh
ssh nwn@SERVER 'cloud-init status; sudo ufw status | head -1; swapon --show; docker info --format "{{.LiveRestoreEnabled}}"'
```

It should print `status: disabled`, `Status: active`, the swap file and `true`. Your SSH client must not warn that
the host key changed. If it does, stop and find out why before you trust the machine.

Because cloud-init is off, the disk no longer grows by itself if you later enlarge it at the provider. You do it
by hand: `sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1`, with your own disk and partition names.

### 8. LAYONARA-ONLY. Never rescale a machine on an old price

Layonara's game host is never resized, because any change of size moves it to today's price for good. This is a
fact about one bill. It is not advice for a new server.

## The agent playbook

[`playbooks/01-servers.md`](../playbooks/01-servers.md) has the same steps in the fixed shape an agent can follow:
inputs, preconditions, steps with the output that counts as success, verification, roll back, and the points
where it must stop and ask a person.

## Lessons

The incidents behind the rules. Dates are when they happened to Layonara.

- **Switch cloud-init off once the machine is set up (2026-11-05).** After an operating system upgrade, the game
  host's first boot could not reach the provider's metadata service. cloud-init took the boot for a brand-new
  machine: it made new SSH host keys, so every saved key for the host had to be replaced, and it rewrote the
  network settings, which dropped the machine's IPv6 address. All four machines have had cloud-init off since.
- **Turn `live-restore` on before anything matters (2026-11-03).** Without it, restarting the Docker service
  stops every container, and a routine package update restarts the service. With it on, a Docker update on
  Layonara's control host left all 21 containers running. It has one side effect on a machine with a reverse
  proxy, which the Coolify chapter covers.
- **Cap the logs from the first day (2026-10-31).** The cap applies only to containers created after it is set.
  Containers made earlier keep writing without a limit until they are recreated. No outage is on record from
  this; the cap was added before one happened.
- **Keep both firewalls.** One of Layonara's machines has no host firewall and relies on the provider's alone:
  two internal services there listen on every address and are closed from outside only by the provider's rules.
  Step 6 is the same lesson from the other side.
- **After an Ubuntu release upgrade, check two files (2026-11-03).** The upgrade deleted `/etc/timezone`, and a
  container that mounted that file then failed to start. It also switched off Docker's package source in
  `/etc/apt/sources.list.d/`, so Docker stopped getting updates until it was put back.

## Tested

On 2026-11-17, on a Hetzner cloud server of the smallest shared type, with Ubuntu 26.04.1, Docker 29.10.0 and
Compose 5.8.0:

- every step of the script, one at a time, then the whole script a second time (no errors, nothing changed);
- that root and password logins are refused and the new user gets in;
- that a container keeps running across a restart of the Docker service, and gets the log cap;
- the two firewall tests in step 6, from a machine elsewhere on the internet;
- a reboot: the same host key, the same IPv4 and IPv6 addresses, the firewall on, swap on, cloud-init off.

Not tested: other providers, other Ubuntu releases, and a game with players on a machine this small.
