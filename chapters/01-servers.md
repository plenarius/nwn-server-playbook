# Chapter 1. Choosing and preparing servers

**Status:** tier 1 is written and tested. Tiers 2 and 3 (a second machine, the private network between machines, a
provider token for scripts) are not written yet.

## What you learn

By the end of this chapter you'll have one machine that is ready to host a game server in Docker, and you'll know
why each setting is there. Nothing here is about Neverwinter Nights yet. This is the quiet groundwork the later
chapters stand on.

When you're done, you'll have:

- a machine you log in to with an SSH key, as your own user, never as root and never with a password;
- two firewalls, the provider's and the host's, that let in SSH, the game and (if you want a website) the web;
- Docker and Compose, set so that a Docker update doesn't stop your game and logs can't fill the disk;
- a machine that comes back from a reboot exactly as it went down.

If you've never set up a server before, that's fine. Every step says what it does and how to check that it worked.

**Time:** the script took about 3 minutes on the test machine. With renting the machine and doing the checks, about
15 minutes in all seems fair. That second number is an estimate, so don't worry if yours takes longer.

## What Layonara does

Layonara is the persistent world I administer, and it's the worked example all through this guide. It runs on four
machines. Tier 1 only needs one, so the one that matters here is the game host.

- **The game host** is a Hetzner cloud server with 2 dedicated cores, 8 GB of memory and an 80 GB disk. It runs the
  game server, its MariaDB database and Redis, all in Docker, and nothing else.
- **What the game uses.** With nobody online, the game process used 27% of one core and 620 MB of memory.
- **What it costs.** That machine is on an old price of €16.99 a month. The same type is listed at €43.49 today, so
  please don't take our bill as a guide to yours.
- **Its settings** are the ones this chapter walks you through: Ubuntu 26.04 LTS, the clock on UTC, SSH with keys
  only and no root login, `ufw` allowing SSH and the game port, Docker with `live-restore` and a log cap of three
  10 MB files per container, a 2 GB swap file, automatic security updates, and cloud-init switched off.
- **Why Hetzner.** I recommend it mostly for its API: scripts can create a server, label it and delete it, and the
  later tiers lean on that for short-lived servers. For tier 1, any provider that gives you a fresh Ubuntu server
  and a firewall will do just as well.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

The commands in steps 4 to 7 come from one small script,
[`templates/host/prepare-host.sh`](../templates/host/prepare-host.sh), and one settings file,
[`templates/host/daemon.json`](../templates/host/daemon.json). It's worth reading the script before you run it.
It's short, and each step in it checks before it changes anything, so running it twice does no harm.

### 1. GENERIC. Decide what the machine is for

In tier 1, one machine does everything: the game, its database and, later, a small website. You won't need a second
machine until tier 2, so there's nothing to plan yet.

### 2. ADAPT. Rent the machine

Change: the provider, the region, the size.

- **Image:** Ubuntu 26.04 LTS. The script reads the release name from the machine, so another current Ubuntu LTS
  should work, but 26.04 is the one that was tested.
- **SSH key:** add your public key when you create the server, so the provider puts it in root's account. The
  script copies it from there to your own user. If you don't have a key yet, `ssh-keygen -t ed25519` on your own
  computer makes one.
- **Size:** our game host has 2 dedicated cores and 8 GB. Dedicated cores cost more than shared ones; on shared
  cores your game runs beside other customers' work. These steps were tested on the smallest shared type (2 cores,
  4 GB, about €0.009 an hour), which is plenty for following along. I can't tell you how a busy game runs on a
  machine that small, because none was run on it for this guide. If it turns out too small, you can rent a bigger
  one and repeat this chapter in a few minutes.
- **Region:** near your players.

### 3. ADAPT. Set the provider's firewall

Change: where your provider keeps this setting. At Hetzner it is "Firewalls" in the project.

Allow these inbound, for IPv4 and IPv6, and nothing else:

| Port | Protocol | For |
|---|---|---|
| 22 | TCP | SSH |
| 5121 | UDP | The game |
| 80 and 443 | TCP | A website, only if this machine will serve one |
| (none) | ICMP | Ping |

It's tempting to skip this, since the host gets a firewall of its own in step 5. Please keep it anyway: step 6
shows the gap it covers.

### 4. GENERIC. Copy the templates and make your own user

From your own computer, with the server's address in place of `SERVER`:

```sh
scp -r templates/host root@SERVER:/root/host
ssh root@SERVER 'cd /root/host && STEPS="updates user" ./prepare-host.sh'
```

This installs pending updates and creates a user called `nwn` (set `DEPLOY_USER=yourname` if you'd like another
name). The user gets root's SSH keys and can use `sudo` without a password, because the account has no password to
ask for.

**A check before you go on:** log in as the new user from a second terminal.

```sh
ssh nwn@SERVER 'whoami; sudo -n true && echo "sudo ok"'
```

You should see `nwn` and `sudo ok`. Take a moment over this one: the next step closes root's door behind you, and
it is a much calmer evening when you already know your own key works. If it doesn't work yet, nothing is broken.
You can still get in as root and try again.

### 5. GENERIC. Run the rest

```sh
ssh nwn@SERVER 'sudo cp -r /root/host ~/host && sudo chown -R nwn: ~/host'
ssh nwn@SERVER 'cd ~/host && sudo STEPS="ssh firewall docker swap clock cloudinit" ./prepare-host.sh'
```

If this machine will serve a website, add `ALLOW_WEB=1` after `sudo`. Here is what each step does and how you can
see that it worked:

| Step | What it does | How to check it |
|---|---|---|
| `ssh` | Keys only; no passwords; no root login | `ssh root@SERVER` is refused with `Permission denied (publickey)` |
| `firewall` | `ufw` denies everything inbound except SSH, the game port and, if asked, 80 and 443 | `sudo ufw status` lists exactly those |
| `docker` | Docker Engine and Compose from Docker's own package repository, with `daemon.json`; adds your user to the `docker` group | `sudo docker info --format '{{.LiveRestoreEnabled}}'` prints `true` |
| `swap` | A 2 GB swap file (`SWAP_GB=0` for none) | `swapon --show` lists `/swapfile` |
| `clock` | Sets the time zone to UTC, so logs and schedules on every machine agree | `timedatectl` shows `Etc/UTC` |
| `cloudinit` | Switches cloud-init off and keeps the network file it wrote | `cloud-init status` prints `disabled` after the next boot |

Log out and back in once, so your user picks up the `docker` group.

### 6. GENERIC. The one thing the host firewall doesn't cover

Here is the part that isn't obvious. **A port that Docker publishes is open to the internet even when `ufw` has no
rule for it.** Docker manages its own firewall rules, and they are checked before `ufw`'s, so `ufw` never gets a
say.

This was tested on the machine from this chapter. A container started with `-p 8080:80` answered from outside,
although `ufw` allowed only 22, 5121, 80 and 443. Two things stopped it:

- **Publishing on the machine's own address only:** the same container started with `-p 127.0.0.1:8081:80` could
  not be reached from outside.
- **The provider's firewall from step 3:** with it on, port 8080 could not be reached from outside either.

So here is the habit the later chapters keep: a database, Redis or any service that only this machine uses is
published on `127.0.0.1`, or not published at all. Only the game port and the web ports are published to everyone.
The provider's firewall is there for the day one of us forgets.

### 7. GENERIC. Reboot once and check

A reboot is the honest test of whether everything sticks.

```sh
ssh nwn@SERVER 'sudo reboot'
```

Give it a minute, then:

```sh
ssh nwn@SERVER 'cloud-init status; sudo ufw status | head -1; swapon --show; docker info --format "{{.LiveRestoreEnabled}}"'
```

You should see `status: disabled`, `Status: active`, the swap file and `true`. Your SSH client shouldn't warn that
the host key changed. If it does, please pause there and find out why before you trust the machine.

One small cost of switching cloud-init off: the disk no longer grows by itself if you later enlarge it at the
provider. You do it by hand with `sudo growpart /dev/sda 1 && sudo resize2fs /dev/sda1`, using your own disk and
partition names.

### 8. LAYONARA-ONLY. We never resize our game host

Any change of size would move it from its old price to today's for good. That's a quirk of one bill, not advice for
a new server.

## The agent playbook

If you work with an AI agent, [`playbooks/01-servers.md`](../playbooks/01-servers.md) has these same steps in a
fixed shape it can follow: inputs, preconditions, steps with the output that counts as success, verification, roll
back, and the points where it should stop and ask you.

## Lessons

These are the things that went wrong for us, written down so they don't have to go wrong for you. The dates are
when they happened to Layonara.

- **Switch cloud-init off once the machine is set up.** This one caught us on 2026-11-05. After an operating system
  upgrade, our game host's first boot couldn't reach the provider's metadata service, and cloud-init decided it was
  looking at a brand-new machine. It made new SSH host keys, so every saved key for the host had to be replaced,
  and it rewrote the network settings, which dropped the machine's IPv6 address. Nothing warns you about this until
  the day it happens, which is why we now switch cloud-init off on every machine once it is set up.
- **Turn `live-restore` on before anything matters (2026-11-03).** Without it, restarting the Docker service stops
  every container, and an ordinary package update restarts the service. With it on, a Docker update on our control
  host left all 21 containers running. It has one side effect on a machine with a reverse proxy; the Coolify
  chapter covers that.
- **Cap the logs from the first day (2026-10-31).** The cap only applies to containers created after you set it.
  Older ones keep writing without a limit until they are recreated. No outage is on record from this; the cap went
  in before one could happen.
- **Keep both firewalls.** Step 6 showed a published container port passing the host firewall on the test machine.
  The provider's firewall sits outside the machine, so Docker cannot change it; the host firewall covers everything
  Docker doesn't publish.
- **After an Ubuntu release upgrade, check two files (2026-11-03).** The upgrade deleted `/etc/timezone`, and a
  container that mounted that file then failed to start. It also switched off Docker's package source in
  `/etc/apt/sources.list.d/`, so Docker stopped getting updates until it was put back.

## Tested

Every step above was run on a real server before it was written down. On 2026-11-17, on a Hetzner cloud server of
the smallest shared type, with Ubuntu 26.04.1, Docker 29.10.0 and Compose 5.8.0:

- every step of the script, one at a time, then the whole script a second time (no errors, nothing changed);
- that root and password logins are refused and the new user gets in;
- that a container keeps running across a restart of the Docker service, and gets the log cap;
- the two firewall tests in step 6, from a machine elsewhere on the internet;
- a reboot: the same host key, the same IPv4 and IPv6 addresses, the firewall on, swap on, cloud-init off.

Not tested: other providers, other Ubuntu releases, and a game with players on a machine this small. If your setup
is one of those, the steps should still hold, but you'd be the first to find out.
