# Playbook 1. Prepare one server (tier 1)

For an agent. The chapter for people is [`chapters/01-servers.md`](../chapters/01-servers.md). Follow the steps in
order. Do not go on from a step whose check fails.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `SERVER` | The server's public address | none: a person gives it |
| `DEPLOY_USER` | The account to create and use from step 3 on | `nwn` |
| `GAME_PORT` | The game's UDP port | `5121` |
| `ALLOW_WEB` | `1` if this machine will serve a website | `0` |
| `SWAP_GB` | Swap file size in GB, `0` for none | `2` |

Secrets: none pass through you. A person rents the server and adds their SSH public key to it. You use an SSH key
that is already loaded on the machine you run from. Never ask for, print or store a private key or a provider
token.

## Preconditions

A fresh Ubuntu LTS server that root can reach with a key.

```sh
ssh root@$SERVER 'lsb_release -ds; id -u; command -v docker || echo "no docker"; sudo ufw status | head -1; cloud-init status'
```

Success: an Ubuntu LTS release (tested: `Ubuntu 26.04.1 LTS`), `0`, `no docker`, `Status: inactive`,
`status: done`. If Docker is already there or the firewall is already active, the machine is not fresh: stop and
ask.

Record the host key before you change anything:

```sh
ssh root@$SERVER 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' > hostkey.before
```

## Steps

### 1. Copy the templates

```sh
scp -r templates/host root@$SERVER:/root/host
```

Success: exit status 0.

### 2. Updates and the user

```sh
ssh root@$SERVER "cd /root/host && DEPLOY_USER=$DEPLOY_USER STEPS='updates user' ./prepare-host.sh"
```

Success: the last line is `== done: updates user`.

### 3. Prove the new user works

```sh
ssh $DEPLOY_USER@$SERVER 'whoami; sudo -n true && echo "sudo ok"'
```

Success: the user's name, then `sudo ok`. **If this fails, stop.** The next step refuses root logins, and going on
would lock everyone out.

### 4. The rest

```sh
ssh $DEPLOY_USER@$SERVER "sudo cp -r /root/host ~/host && sudo chown -R $DEPLOY_USER: ~/host"
ssh $DEPLOY_USER@$SERVER "cd ~/host && sudo DEPLOY_USER=$DEPLOY_USER GAME_PORT=$GAME_PORT ALLOW_WEB=$ALLOW_WEB SWAP_GB=$SWAP_GB STEPS='ssh firewall docker swap clock cloudinit' ./prepare-host.sh"
```

Success: the last line is `== done: ssh firewall docker swap clock cloudinit`.

### 5. Reboot

```sh
ssh $DEPLOY_USER@$SERVER 'sudo reboot'
```

Wait until SSH answers again (about a minute on the test machine).

## Verify

All of these, after the reboot:

```sh
ssh -o BatchMode=yes root@$SERVER true
```

Success: refused with `Permission denied (publickey)`.

```sh
ssh $DEPLOY_USER@$SERVER 'cloud-init status; sudo ufw status | head -1; swapon --show | tail -1; docker info --format "{{.LiveRestoreEnabled}} {{.LoggingDriver}}"; timedatectl show -p Timezone --value'
```

Success: `status: disabled`, `Status: active`, a `/swapfile` line (unless `SWAP_GB=0`), `true json-file`,
`Etc/UTC`. Note that `docker` works here without `sudo`: that proves the group was applied.

```sh
ssh $DEPLOY_USER@$SERVER 'ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub' | diff - hostkey.before
```

Success: no output. The host key is the one recorded before.

```sh
ssh $DEPLOY_USER@$SERVER 'sudo ufw status' 
```

Success: `22/tcp` and `$GAME_PORT/udp` allowed, plus `80/tcp` and `443/tcp` only when `ALLOW_WEB=1`, each for IPv4
and IPv6, and nothing else.

From a machine that is not the server, check that no other TCP port answers:

```sh
for p in 80 443 2375 3306 6379 8080; do timeout 4 bash -c "</dev/tcp/$SERVER/$p" 2>/dev/null && echo "open $p"; done
```

Success: no output on a machine with nothing deployed yet.

## Roll back

- **A new machine:** there is nothing to keep. A person deletes the server and starts again.
- **A machine that already ran something:** this playbook is not for it. If it was run there anyway, the files it
  changed are `/etc/ssh/sshd_config.d/10-keys-only.conf`, `/etc/sudoers.d/90-$DEPLOY_USER`,
  `/etc/docker/daemon.json` (the old one is kept beside it as `daemon.json.before-<date>`),
  `/etc/apt/sources.list.d/docker.list`, `/etc/fstab` (one `/swapfile` line), `/etc/cloud/cloud-init.disabled`,
  and the `ufw` rules.
- **Cannot be undone by you:** a lockout. If step 4 ran and no user can log in, only the provider's console can
  repair it.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- renting, resizing or deleting a server, or anything else that costs money;
- changing the provider's firewall (the person does that in the provider's console);
- running this on a machine that is not fresh (the preconditions fail);
- a host key that differs from `hostkey.before`;
- any step whose check fails twice.
