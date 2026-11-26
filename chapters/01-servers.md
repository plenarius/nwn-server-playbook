# Chapter 1. Choosing and preparing servers

**Status:** all three tiers are written and tested. Tier 1 is one machine; tier 2, further down, adds a second
machine and a private network between the two; tier 3, at the end, makes short-lived servers from a script and adds
a third site at another provider.

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

---

## Tier 2. A second machine and a private network

### What you learn

Sooner or later one machine is asked to do too much. Building haks, running tests and hosting tools all compete
with the game for the same cores, and the game is the one your players feel. Tier 2 gives those jobs a machine of
their own, and joins the two machines with a private network so they can talk to each other without anything
being open to the internet.

When you're done, you'll have:

- a **game host** that runs the game and its database, and little else;
- a **control host** for everything around the game: builds, tools, and in later chapters Coolify and the
  operations service;
- a WireGuard network between them, each with an address of its own, such as `10.77.0.1` and `10.77.0.2`;
- the habit that goes with it: a service that only your own machines use is published on the private address,
  never on the public one.

**Time:** about half an hour, most of it preparing the second machine with tier 1's steps. The private network
itself took under a minute on the test.

### What Layonara does

- **The game host** has 2 dedicated cores, 8 GB and an 80 GB disk, and runs the game, its database and Redis.
- **The control host** has 4 cores and about 8 GB, and runs our tools: Coolify, the operations service, the
  Discord bot, the build machine for haks, a second game server for testing, and monitoring.
- **A WireGuard network** joins all our machines, with the control host as its hub. It uses one `/24` network,
  UDP port 51820, and a keepalive every 25 seconds.
- **The game's database and Redis are published only on the game host's private address.** The control host
  reaches them through the tunnel; the internet can't reach them at all.
- **Our machines are at two providers.** That's one reason we use WireGuard and not a provider's own private
  network: WireGuard doesn't care whose machines it joins.
- **Distance matters for chatty services.** The service that reads the game's database all day runs on the control
  host, about a millisecond from the game host. From one of our machines at the other provider, the same query
  would take about 25 ms. When we moved most services to that machine, this one stayed where it was.

### The human playbook

#### 9. GENERIC. Decide what goes where

Keep the **game host** for the game and its database. Everything players don't touch directly goes to the
**control host**. The rule of thumb I use: if it stopped for an hour, would anyone in the game notice? If not, it
belongs on the control host.

One exception is worth planning for. A service that talks to the game's database many times a second should sit
close to it: on the game host, or on a control host in the same data centre. A few milliseconds per query add up
quickly.

#### 10. ADAPT. Rent and prepare the second machine

Change: the provider, the region, the sizes.

- **The game host** deserves dedicated cores in tier 2. On shared cores the game runs beside other customers' work,
  and a busy neighbour shows up as lag. Ours has 2 dedicated cores and 8 GB.
- **The control host** can use shared cores. Ours has 4 cores and about 8 GB.
- **Put both in the same region**, so the network between them is fast. Between two test machines in the same
  Hetzner location the round trip was about a millisecond.

Prepare the new machine exactly as in steps 2 to 7. The script is the same; tier 1's settings are what you want on
both machines.

#### 11. ADAPT. Open the tunnel's port at the provider

Change: where your provider keeps its firewall.

Add one rule to each machine's provider firewall: **UDP 51820**, inbound, **from the other machine's public address
only**. WireGuard already ignores anyone without a key, but there's no reason to let strangers knock. I tested this
rule at Hetzner, and the tunnel came up through it as before.

#### 12. GENERIC. Make the private network

The script is [`templates/host/wireguard.sh`](../templates/host/wireguard.sh). If your copy of `templates/host` on
the machines is older than this section, copy it to both again (step 4 of tier 1).

Pick a private range that nothing else of yours uses. This guide uses `10.77.0.0/24`, with the control host at
`.1` and the game host at `.2`.

On the **control host**:

```sh
sudo ~/host/wireguard.sh init 10.77.0.1/24
```

On the **game host**:

```sh
sudo ~/host/wireguard.sh init 10.77.0.2/24
```

Each prints a **public key**, a line of 44 characters. Public keys are safe to copy around; that's what they're
for. Each machine also made a private key, which stays in `/etc/wireguard/wg0.conf` and never leaves the machine.

Now tell each machine about the other. With the game host's public key and public address, on the **control
host**:

```sh
sudo ~/host/wireguard.sh peer game GAME_HOST_PUBLIC_KEY 10.77.0.2 GAME_HOST_PUBLIC_ADDRESS
sudo ~/host/wireguard.sh up
```

And the mirror image on the **game host**:

```sh
sudo ~/host/wireguard.sh peer control CONTROL_HOST_PUBLIC_KEY 10.77.0.1 CONTROL_HOST_PUBLIC_ADDRESS
sudo ~/host/wireguard.sh up
```

`up` does four things: it starts the network, starts it at every boot, opens UDP 51820 in `ufw`, and lets
everything that arrives through the tunnel past the host firewall. That last one is a choice: everything that comes
through the tunnel comes from one of your own machines. It also makes Docker wait for the network at boot; step 14
says why.

Every command here is safe to run twice. Running `init` with a different address on a machine that already has
one is refused, so a typo can't quietly replace a working setup.

#### 13. GENERIC. Check it

From the control host:

```sh
ping -c 3 10.77.0.2
sudo wg show
```

You should see replies, and under the peer a line `latest handshake` a few seconds old. That handshake means the
two machines have recognised each other's keys. If there are no replies, the provider firewall rule from step 11 is
the first thing to look at.

#### 14. GENERIC. Publish private services on the private address

This is the habit the network is for. A service on the game host that only your control host should reach is
published like this:

```yaml
ports:
  - "10.77.0.2:3306:3306"
```

with the private address in front. Chapter 1's step 6 showed that a published port is open to the world even when
`ufw` has no rule for it. Published on the private address instead, it simply doesn't exist on the public one. I
checked both from the control host, where it answered, and from outside, where it didn't.

One trap comes with this, and it's why `up` makes Docker wait for the network. If Docker starts a container
before the private address exists, the container fails to start. I tried it: the container stopped with
`driver failed programming external connectivity`, and **it stayed stopped** even after the network came up a
moment later. At boot, Docker and WireGuard start at about the same time, so without help it's a coin toss. On the
test machine Docker started first in three boots out of four and still won the race by luck. The file `up` writes,
`/etc/systemd/system/docker.service.d/10-after-wireguard.conf`, makes Docker start after the network, every time.

#### 15. LAYONARA-ONLY. A hub with spokes

Our network has the control host as a hub with every other machine as a spoke, and it has grown one machine at a
time. For two machines there's no hub to speak of: each simply knows the other. If you add a third, give it a peer
line for each machine it needs to reach, and add it as a peer on those.

### The agent playbook

If you work with an AI agent, [`playbooks/01-servers-tier2.md`](../playbooks/01-servers-tier2.md) has these steps
in a fixed shape it can follow. Renting the machine and the provider firewall rule stay with you; the agent does
the rest and checks it.

### Lessons

- **Keep the database's closest friend close.** The millisecond between our game host and control host is why the
  service that queries the game's database most stayed on the control host when everything else moved. Placement
  is a performance decision as much as a tidy one.
- **Private services go on the private address.** Our game's database and Redis are published only on the game
  host's private address. Together with the provider firewall, that's two separate things that would both have to
  go wrong before a stranger could reach them.
- **Make Docker wait for the private network (2026-11-18).** This one I found while testing this section: a
  container published on the private address fails to start if it's started before the address exists, and Docker
  doesn't try again. One small file fixes it, and `wireguard.sh up` writes it for you.

### Tested

On 2026-11-18, on two fresh Hetzner cloud servers of the smallest shared type in the same location, both prepared
with tier 1:

- `init`, `peer` and `up` on both, then all three again on one of them (nothing changed, still one peer), and
  `init` with a different address (refused);
- ping both ways (about 1 ms) and a WireGuard handshake;
- a container published on the private address only: reachable from the control host, not from outside;
- starting that container while the private network was down: it failed and stayed stopped. Then four reboots
  without the ordering file (Docker started first in three of them) and three reboots with it (Docker started after
  the network every time, and the container ran);
- a reboot of the control host: the tunnel came back by itself;
- a restart of Docker on the game host: the container kept running and stayed reachable;
- a provider firewall at Hetzner allowing UDP 51820 only from the control host: the tunnel came up through it;
- a scan of the game host's public address from outside: only SSH answered.

Not tested: three or more machines, machines at two different providers, and IPv6 inside the tunnel.

---

## Tier 3. Servers from a script, and a third site

### What you learn

By tier 3 you'll want machines that live for an hour: a big one to build all your haks at once, a copy of the
game to try a risky change on, a clean machine to test a guide like this one. Renting those by hand works, but
it's also how you find a forgotten 48-core server on next month's bill. This tier lets a script do it, with the
guard rails built in. It also adds a third machine somewhere else, so that one provider having a bad day can't
take everything with it.

When you're done, you'll have:

- a **project of its own** at Hetzner for short-lived servers, and a token that can't touch anything else;
- a script that **creates a server with an expiry**, refuses one that would go over your **budget**, and only
  ever deletes what it made;
- **snapshots**: a prepared machine saved once and copied in a minute, without the two traps that come with it;
- a **reaper** on an always-on machine that deletes any of those servers left running past its time;
- an understanding of **legacy prices**, and why a machine on one should never be resized;
- a **third site** at another provider, holding a copy of your backups and an outside watchdog.

**Time:** about half an hour for the script and the reaper. The third site is tier 1's chapter again on one more
machine, plus a few minutes for the private network. On the test, a new server answered the API in about
12 seconds, a snapshot took 18 seconds and a server made from it answered SSH about 40 seconds later.

### What Layonara does

- **A separate project for every machine a script makes.** Our short-lived servers live in their own Hetzner
  project, with a token for that project only. A script with a bug in it can't reach the live game host, because
  its token doesn't know the game host exists.
- **Labels on everything.** Each of those servers carries what it's for, its role, and an `expires` label with the
  time it should be gone. Nothing is made without one.
- **A ceiling on time and money.** At most 6 hours a server, and at most €10 for one session. Our biggest type, 48
  dedicated cores, is €1.38 an hour in Ashburn and €1.16 in Helsinki. Hetzner bills every hour that has started,
  so the expiry is set two minutes short of the last paid hour.
- **Two ways to go, independent of each other.** Each server deletes itself at its expiry, and a reaper on one of
  our always-on machines deletes any server in that project more than 5 minutes past its expiry, or without one,
  and tells us on Discord. If one of the two fails, the other still does the job.
- **A golden snapshot.** Our heavy servers start from a snapshot with the tools and repositories already on it, so
  a session is ready in about two minutes. We keep the two newest; each is about 32 GB and costs about €0.46 a
  month. Before one is saved, everything secret is removed and the disk is searched for every secret value, and
  each copy gets a new machine id and host keys of its own.
- **One machine on a legacy price.** Our game host is on an old price of €16.99 a month. The same type is listed at
  €43.49 today, and a rescale or a bigger disk would move it to today's price for good. So we never resize it.
- **Machines at two providers.** A machine at a second provider runs our websites and CI, and holds the second copy
  of our backups. Our outside watchdog runs at Cloudflare, which is a third company again.

### The human playbook

#### 16. GENERIC. A project and a token of their own

In Hetzner's console, create a **new project** (I call mine after what it's for, like "burst"), open it,
**Security**, **API tokens**, **Generate API token**, with **Read & Write**. Hetzner shows the token once.

Keep it in a file only you can read, on the computer you'll run the script from:

```sh
mkdir -p ~/.config/hcloud && chmod 700 ~/.config/hcloud
read -rs TOKEN && printf '%s\n' "$TOKEN" > ~/.config/hcloud/playbook.token && unset TOKEN
chmod 600 ~/.config/hcloud/playbook.token
```

The token is pasted, not shown, and never lands in your shell's history. In the same project, under **Security**,
**SSH keys**, add your public key, and note the name you give it.

Please don't use your live machines' project for this. A token for a project can do anything in that project,
delete included. A project of its own is what keeps a scripting mistake small.

#### 17. GENERIC. The script

[`templates/provider/hcloud-servers.py`](../templates/provider/hcloud-servers.py) is one file, Python 3 alone, with
nothing to install. Copy it somewhere on your path and check that it can talk to Hetzner:

```sh
install -m 755 templates/provider/hcloud-servers.py ~/.local/bin/hcloud-servers
hcloud-servers price cx23 hel1
hcloud-servers list
```

You should see `EUR 0.0088 an hour` (the list price on 2026-11-26, with VAT) and, for an empty project,
`at most EUR 0.00 in all; budget EUR 5.00`.

Everything it makes carries the label `managed-by=playbook`, and it refuses to delete, protect or reap anything
without that label. I tried: asked to delete a server it hadn't made, it said `not touching burst: it has no
managed-by=... label, so this script did not make it` and did nothing.

#### 18. GENERIC. Make a server that knows when to go

```sh
export SSH_KEYS=my-key            # the name of your key in the project
hcloud-servers create build-1 cx23 2 hel1
```

That's a server called `build-1`, of type `cx23`, for 2 hours, in Helsinki, with Ubuntu 26.04. It prints the
address when the server is running, and before that a line like
`created build-1 (cx23, hel1, image ubuntu-26.04), expires 19:56 UTC, at most EUR 0.02`.

Before it creates anything, it adds up what could be spent: every server of its own that is running, each counted
to its expiry, plus the new one. If that's over your budget (`BUDGET_EUR`, €5 unless you say otherwise), it
refuses. On the test, asking for our biggest type for 6 hours:

```text
refused: this server could cost EUR 6.97, the ones running up to EUR 0.08, together over the budget of EUR 5.00 (BUDGET_EUR)
```

It also refuses anything longer than 6 hours (`MAX_HOURS`). Both numbers are yours to choose. Pick ones that
would make you wince a little but not panic.

When you're done with a server, don't wait for the reaper:

```sh
hcloud-servers delete build-1
```

#### 19. GENERIC. Snapshots, without the two traps

A snapshot is a saved copy of a server's disk. You prepare a machine once, with Docker, your tools, perhaps a copy
of the game, save it, and every new server made from it starts there instead of from a bare Ubuntu.

Here's the part that caught me while testing this chapter. Tier 1 switches cloud-init off on every machine, and
keeps the network settings it wrote. **Those settings name the machine's network card.** A server made from a
snapshot of such a machine has a different card, so it **boots with no network at all**: no SSH, not even ping. And
every copy of any snapshot shares the original's machine id, which some tools use to tell machines apart.

[`templates/provider/prepare-snapshot.sh`](../templates/provider/prepare-snapshot.sh) handles both. Copy it to the
machine you want to save (`scp templates/provider/prepare-snapshot.sh nwn@SERVER:host/`), and then, from your own
computer:

```sh
ssh nwn@SERVER 'sudo ~/host/prepare-snapshot.sh before'
hcloud-servers snapshot SERVER-NAME "builder with tools, 2026-11-26"
ssh nwn@SERVER 'sudo ~/host/prepare-snapshot.sh after'
```

`before` switches cloud-init back on and clears the machine id, so each copy makes its own id, host keys and
network on its first boot. `after` puts the original back exactly as it was. Please don't skip `after`: without
it, the original makes itself new host keys at its next reboot, which is the very thing tier 1 switched
cloud-init off to prevent. I checked both: with `after`, the original came back from a reboot with the same id and
host key; without it, my SSH client refused the machine's new key.

`snapshot` prints the snapshot's number. Make servers from it by giving that number as the image:

```sh
hcloud-servers create build-2 cx23 2 hel1 461330554
ssh nwn@NEW_SERVER 'sudo ~/host/prepare-snapshot.sh after'
```

On a copy, `after` sees it's a different machine, keeps its new id and switches cloud-init off again, as tier 1
does. Snapshots cost a little every month for as long as you keep them:

```sh
hcloud-servers images
hcloud-servers delete-image 461330554
```

A snapshot of a fresh machine was 0.8 GB, about a cent a month; ours with all the tools on is 32 GB, about €0.46.

**Never save a snapshot with a secret on it.** Anything on the disk is copied into every server you make from it.
Put secrets onto a new server after it starts, over SSH, and keep them in memory (`/run`) where you can.

#### 20. GENERIC. A reaper for forgotten servers

The expiry label only says when a server should be gone. Something has to act on it, and it shouldn't be your
laptop, which is asleep when it matters. Put the reaper on a machine that's always on, such as your control host.

```sh
scp templates/provider/hcloud-servers.py templates/provider/hcloud-reaper.* templates/provider/reaper.env.example nwn@CONTROL:
ssh nwn@CONTROL 'sudo install -m 755 hcloud-servers.py /usr/local/bin/hcloud-servers && sudo install -d -m 700 /etc/hcloud-reaper && sudo install -m 600 reaper.env.example /etc/hcloud-reaper/reaper.env && sudo install -m 644 hcloud-reaper.service hcloud-reaper.timer /etc/systemd/system/ && sudo systemctl daemon-reload && echo installed'
ssh nwn@CONTROL 'read -rs -p "Token: " t; echo; printf "%s\n" "$t" | sudo install -m 600 /dev/stdin /etc/hcloud-reaper/token && echo saved'
ssh nwn@CONTROL 'sudo systemctl start hcloud-reaper.service; sudo journalctl -u hcloud-reaper -n 3 --no-pager -o cat; sudo systemctl enable --now hcloud-reaper.timer'
```

You should see `nothing to reap`. Every ten minutes it deletes any server with your label that is more than 5
minutes past its expiry (`GRACE_MIN`), or has no expiry at all. A server you've protected (next step) it leaves
alone and says so. To hear about each one, give it a Discord webhook: the two commented lines in the service say
how.

It runs as a throwaway user that systemd makes for each run, and gets the token handed to it by systemd; the
file itself stays readable only by root.

`hcloud-servers reap --dry-run` shows what it would delete, from anywhere you have the token.

#### 21. GENERIC. Protect what must never go

Hetzner can refuse to delete or rebuild a server until you take the protection off. Switch it on for every
permanent machine: the server's page in the console, **Protection**, both switches. For the script's own servers,
`hcloud-servers protect NAME on`. On the test, a delete of a protected server came back with
`server deletion is protected` and nothing happened.

Protection doesn't cover a rescale. That's what the next step is about.

#### 22. LAYONARA-ONLY. Legacy prices: never resize that machine

Providers change their prices now and then, and a server you already have usually keeps the price it had. That
old price is called a **legacy price**. Ours is €16.99 a month for a type listed at €43.49 today.

The catch is that the old price belongs to the server as it is. **A rescale to another type, even for an hour, or
a bigger disk, moves it to today's price for good.** Going back to the old type afterwards gives you the old type
at today's price. No warning in the console says so.

So if you have a machine like that, write it down where everyone with access to the console will see it, and
when it's too small one day, rent a new machine and move to it. Moving is tier 1's chapter and the backup chapter's
restore, and it's an evening's work, not a crisis.

If you're starting fresh, none of this applies to you yet. It's simply worth knowing before you resize a machine
you've had for a few years.

#### 23. ADAPT. A third site at another provider

Change: the provider, the region.

Everything so far lives at one provider. A provider having a bad day is rare, but when it happens, everything
there goes at once: the game, the control host, and with them the backups on the control host and the watchdog
that would have told you. A third machine at another company keeps two things outside that:

- **a second copy of your backups**, so a lost account or a lost data centre doesn't take every copy with it;
- **an outside watchdog**, so the alert about the outage doesn't depend on the outage.

It doesn't need to be big: the test used the smallest type. Prepare it with tier 1's steps, then join it to the
private network as a third peer. On the new machine (here `10.77.0.3`):

```sh
sudo ~/host/wireguard.sh init 10.77.0.3/24
sudo ~/host/wireguard.sh peer control CONTROL_HOST_PUBLIC_KEY 10.77.0.1 CONTROL_HOST_PUBLIC_ADDRESS
sudo ~/host/wireguard.sh peer game GAME_HOST_PUBLIC_KEY 10.77.0.2 GAME_HOST_PUBLIC_ADDRESS
sudo ~/host/wireguard.sh up
```

and on each of the other two, one more `peer third THIRD_PUBLIC_KEY 10.77.0.3 THIRD_PUBLIC_ADDRESS` and `up`.
Open UDP 51820 at each provider's firewall for the new machine's address too (step 11).

Then, on the third machine:

- the **backup copy**: chapter 12's second destination, or a pull over the private network;
- the **watchdog**: chapter 13's, installed here instead of (or as well as) on the control host.

**Distance is the cost.** On the test, the two machines in one location were about 1 ms apart and the third, in
another country, about 35 ms. That's nothing for a nightly copy or a check every two minutes, and a lot for a
service that talks to the game's database all day (step 9). Keep those on the game's side.

### The agent playbook

If you work with an AI agent, [`playbooks/01-servers-tier3.md`](../playbooks/01-servers-tier3.md) has these steps in
a fixed shape it can follow. Making the project and the token, renting the third machine and any server that
costs money stay with you, unless you give the agent a budget.

### Lessons

- **A token per project, and a project per purpose.** It's why our scripted servers can't touch the game host: not
  care, just a token that doesn't reach it.
- **Two independent ways to go.** Our servers delete themselves at their expiry, and a reaper elsewhere deletes
  anything that didn't. A self-delete once ran two hours late because a timer had moved under it (2026-11-17);
  since then it's set to a time on the clock, and the reaper was there anyway.
- **Bill-shaped limits.** Hetzner bills each started hour, so our expiry is two minutes short of the last paid hour,
  and the budget counts whole hours.
- **Snapshots copy what you forgot.** The network file, the machine id and any secret on the disk all go into every
  copy. I found the network one while writing this chapter, on a copy that never answered; our own image build
  scans for secrets before every snapshot.
- **Know which machine is on an old price,** and leave its size alone.

### Tested

On 2026-11-26, in a Hetzner project for short-lived servers, with servers of the smallest shared type (`cx23`) and
Ubuntu 26.04, from a Linux workstation with Python 3.12:

- `price`, `list`, and `create` in Helsinki and Falkenstein, with the labels and the expiry;
- the cost guard refusing a 48-core server for 6 hours over a €5 budget, and a smaller one over a €0.10 budget;
  `MAX_HOURS` refusing 7 hours;
- `delete` and `protect` refusing a server without the label; a delete of a protected server refused by Hetzner;
- `reap`: a server created for about a minute, left untouched by `--dry-run` with the 5-minute grace, then
  deleted with the grace at 0 and its alert posted to a local stand-in for Discord; a server with its expiry
  label removed by hand, deleted as `no expiry label`; step 20's commands as written on another server (as
  root), whose timer then deleted an expired server by itself (grace set to 0 for the test) and posted its alert
  through the two webhook lines;
- snapshots: one of a fresh server, a server made from it (my marker file there, new host key, same machine id); a
  snapshot of a machine with cloud-init switched off by tier 1's script: its copy never answered, twice (the
  network file names the old card); then `prepare-snapshot.sh before`, the snapshot, `after`: the original kept its
  id and host key across a reboot, the copy booted with network and its own id and key, and kept them across a
  reboot after `after`; `images` and `delete-image`;
- the third site: two servers in Helsinki and one in Falkenstein joined with `wireguard.sh` as three peers (ping
  about 1 ms and 35 ms); a 50 MB file pulled over the private network to the third in about 2 seconds, checksum
  equal; chapter 13's watchdog on the third, watching a page on the Helsinki game host; then both Helsinki servers
  powered off through the API: the watchdog's one alert arrived 3 minutes and 16 seconds later, and its
  "passing again" message 87 seconds after they were powered on; the private network came back by itself;

The agent playbook's commands were run on the same servers, with `root` in place of the deploy user on the ones
that hadn't been through tier 1. In all, twelve test servers, none for much over an hour, and seven small
snapshots: about €0.12.

Not tested: a third machine at a **different provider**. I had no account at a second one for the test, so a third
Hetzner location stood in for it; WireGuard doesn't care which company a machine is at, but the latency will
differ. Also not tested: a server's self-delete at expiry (chapter 15 covers that, with the burst servers), and a
real rescale of a legacy-priced machine, for the obvious reason, and the reaper meeting a protected server past its
expiry.
