# Chapter 3. Coolify

**Status:** tier 2 is written and tested. Tier 1 doesn't use Coolify: plain Docker Compose (chapter 4) is all one
machine needs. Tier 3 (a helper for busy deploy queues) is not written yet.

## What you learn

How to run your machines from one dashboard. Coolify is a free, self-hosted deploy panel: it lives on your control
host, logs in to your other machines over SSH, and starts, stops and updates containers on them. Its best trick is
deploy on merge: you merge a pull request on GitHub, and a few seconds later the new version is running, without
anyone logging in anywhere.

When you're done, you'll have:

- Coolify on the control host from chapter 1's tier 2, with its dashboard closed to the internet;
- both machines in it, reached as your ordinary deploy user, with root logins still refused;
- the safety settings that matter, and a small check that repairs a known fault after Docker upgrades;
- one application that redeploys itself when a pull request is merged.

Moving the game itself into Coolify is chapter 4's tier 2. This chapter builds the panel and proves the loop.

**Time:** about an hour. The install took one to one and a half minutes on the test machines, and a merged change
was live 18 to 29 seconds after the merge.

## What Layonara does

- **Coolify on the control host manages every machine,** itself included. We run version 4.7.5.
- **The game server is a Docker Compose service** in Coolify, and each website is an application built from its
  repository's `Dockerfile`.
- **Deploy on merge** uses a webhook on each repository, pointed at Coolify's manual GitHub endpoint. We tried
  GitHub's app integration first; its webhook never arrived for us, and the plain repository webhook has worked
  every time.
- **Unused volumes are never deleted automatically,** on any machine.
- **A small check on every machine** restarts Coolify's proxy when a Docker upgrade leaves it holding an old
  connection to Docker. That fault cost us five hours of website on 2026-11-04.
- **The dashboard has its own name with HTTPS.** This chapter takes a simpler route that needs no name; I describe
  ours at the end.

## The human playbook

Each step carries a label: GENERIC (the same for any server), ADAPT (works once you change the things it names) or
LAYONARA-ONLY (something we do that you probably shouldn't copy).

You need both machines from chapter 1's tier 2: prepared, with the private network up. The examples use `CONTROL`
and `GAME` for their public addresses and `10.77.0.1` and `10.77.0.2` for their private ones. The files for this
chapter are in [`templates/coolify`](../templates/coolify).

### 1. GENERIC. Close Coolify's ports before you install it

Coolify publishes its dashboard on port **8000** and two more ports, **6001** and **6002**, on every address of the
machine. They're published by Docker, so, as chapter 1's step 6 showed, `ufw` doesn't stop them. On the test
machine the dashboard answered from the internet the moment the install finished.

So before installing, check the control host's provider firewall. It should allow only what tier 2 already opened:
TCP 22 for SSH, and UDP 51820 from the game host. Nothing for 8000, 6001 or 6002. You'll reach the dashboard
through SSH instead, in step 3.

### 2. GENERIC. Install Coolify, with your admin account

On the control host, pick an email address and a password first. Coolify is strict about both, and if either fails
its rules it skips making the account **without stopping the install**:

- **the password** needs upper and lower case letters, a digit and a symbol, and must not appear in a list of
  breached passwords (Coolify checks online);
- **the email's domain** must accept mail. `example.org`, for one, doesn't, and was refused on the test.

Then:

```sh
ssh nwn@CONTROL
curl -fsSL -o install.sh https://cdn.coollabs.io/coolify/install.sh
export ROOT_USERNAME=admin
read -rp "Admin email: " ROOT_USER_EMAIL; read -rsp "Admin password: " ROOT_USER_PASSWORD; echo
export ROOT_USER_EMAIL ROOT_USER_PASSWORD
sudo --preserve-env=ROOT_USERNAME,ROOT_USER_EMAIL,ROOT_USER_PASSWORD bash install.sh 4.7.5
unset ROOT_USER_PASSWORD
```

The `4.7.5` pins the version, the one we run and the one tested here. The install ends with `Coolify is ready!`.
Then make sure the account really exists:

```sh
docker logs coolify 2>&1 | grep -i "root user"
```

You should see `Root user created successfully`. `Invalid Root User Environment Variables` means one of the two was
refused, and `docker exec coolify php artisan db:seed --class=RootUserSeeder --force` prints which rule failed.
Running the install again doesn't help: it keeps the first values. Instead, correct the `ROOT_USER_EMAIL` or
`ROOT_USER_PASSWORD` line in `/data/coolify/source/.env` (with `sudo nano`), then make Coolify read it and try
again:

```sh
sudo bash -c 'cd /data/coolify/source && docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate coolify'
sleep 30; docker exec coolify php artisan db:seed --class=RootUserSeeder --force
```

The install also changes Docker's settings on this machine: it keeps chapter 1's log limit and `live-restore`, and
adds a pool of addresses for Docker's own networks. It keeps a copy of your old settings beside them in
`/etc/docker/`.

### 3. GENERIC. Open the dashboard through SSH

From your own computer:

```sh
ssh -N -L 8000:localhost:8000 -L 6001:localhost:6001 -L 6002:localhost:6002 nwn@CONTROL
```

Leave that running, and open `http://localhost:8000` in your browser. Your browser talks to your own computer, and
SSH carries it, encrypted, to Coolify. Ports 6001 and 6002 carry the dashboard's live updates; with only 8000, the
dashboard works but complains that it `Cannot connect to real-time service`. Log in with the account from step 2.

The first time, Coolify offers a setup wizard. Choose **Skip setup**; the steps below do the same things with the
choices this guide needs.

### 4. GENERIC. Let Coolify in as your deploy user, not as root

Coolify connects to every machine over SSH, its own included, and by default as root. Tier 1 refuses root logins,
and that's worth keeping: on the test machine Coolify's own login was turned away with `ROOT LOGIN REFUSED`. So
Coolify logs in as `nwn` instead, which can use `sudo` without a password, exactly as you do.

The install put Coolify's public key in root's `authorized_keys`. Give it to `nwn` too, on the control host:

```sh
sudo grep coolify /root/.ssh/authorized_keys >> ~/.ssh/authorized_keys
```

Then in the dashboard: **Servers**, **localhost**, set **SSH user** to `nwn`, **Save changes**, and **Revalidate
Connection**. It should say the server is reachable and ready.

### 5. GENERIC. Add the game host, over the private network

On the game host, Coolify needs one small tool, and its key:

```sh
ssh nwn@GAME 'sudo apt-get install -y jq'
ssh nwn@CONTROL 'sudo grep coolify /root/.ssh/authorized_keys' | ssh nwn@GAME 'cat >> ~/.ssh/authorized_keys'
```

Then in the dashboard: **Servers**, **New Server**. Give it a name, the game host's **private** address
(`10.77.0.2`), SSH user `nwn`, port 22, and the private key called **localhost's key**. Validate it.

Using the private address means Coolify's connection to your game host travels through the tunnel from chapter 1,
never across the internet.

### 6. ADAPT. Decide about Coolify's web proxy on each machine

Change: whether a machine already serves websites some other way.

Coolify starts a web proxy, Traefik, on every machine it manages, on ports 80 and 443. It's what will put your
applications on the web with certificates. Two things to know:

- **Like the dashboard, its ports pass `ufw`.** On the test's game host, ports 80 and 443 answered from outside the
  moment Coolify started the proxy. Your provider firewall decides whether anyone can reach them.
- **It can't share 80 and 443.** If your game host still runs chapter 7's web server for NWSync or chapter 11's
  website, stop Coolify's proxy there: the server's **Proxy** page, **More actions**, **Stop Proxy**, and confirm.
  It stays stopped, through reboots, until you start it again. On the test, the stand-in web server kept ports 80
  and 443 through a reboot, and Coolify left it alone.

### 7. GENERIC. Never let Coolify delete "unused" volumes

On each server's **Docker Cleanup** page, under **Advanced cleanup**, **Unused volumes** should say **Keep unused
volumes**. It did by default on 4.7.5. Please check it anyway, on every server, and leave it there.

A volume can look unused to Docker and still hold data you care about. This is one of the few settings where the
cost of a mistake is your world's data.

### 8. GENERIC. Install the proxy check

When a Docker upgrade re-creates Docker's socket, a running Coolify proxy keeps the old one, and from then on it
can't see your applications. I reproduced it on the test machine: after restarting Docker's socket the way a
package upgrade does, the proxy logged `Cannot connect to the Docker daemon` every few seconds and didn't recover
on its own.

[`templates/coolify/proxy-socket-check.sh`](../templates/coolify/proxy-socket-check.sh) checks once a minute and
restarts the proxy only when it holds an old socket. On each machine with Coolify's proxy:

```sh
scp templates/coolify/proxy-socket-check.* nwn@MACHINE:
ssh nwn@MACHINE 'sudo install -m 755 proxy-socket-check.sh /usr/local/sbin/coolify-proxy-socket-check &&
  sudo install -m 644 proxy-socket-check.service /etc/systemd/system/coolify-proxy-socket-check.service &&
  sudo install -m 644 proxy-socket-check.timer /etc/systemd/system/coolify-proxy-socket-check.timer &&
  sudo systemctl daemon-reload && sudo systemctl enable --now coolify-proxy-socket-check.timer'
```

When it acts, `journalctl -u coolify-proxy-socket-check` says so. On the test it repaired the proxy within a minute
and left a healthy one untouched.

### 9. ADAPT. Let GitHub, and your game host, reach Coolify

Change: your provider's firewall rules.

Deploy on merge means GitHub tells Coolify about each merge, and Coolify's monitoring agent on the game host
reports back to Coolify too. Both arrive on port 8000. So open TCP 8000 at the control host's provider firewall to
exactly two kinds of sender:

- **GitHub's webhook senders.** GitHub publishes their addresses; `gh api meta -q '.hooks[]'` lists them (nine
  ranges on the day of the test). They change rarely, but they do change, so look again if webhooks stop arriving.
- **The game host's public address.** Without it, the server shows **Attention required** in Coolify's server list.
  On the test that was the monitoring agent failing to report, and allowing the game host cleared it.

Everyone else still finds port 8000 closed; I checked from outside. Webhooks then travel as plain HTTP. GitHub
signs each one with a secret, so they can't be forged, but their contents (commit messages, names) aren't
encrypted. If that matters to you, give Coolify a name with HTTPS, as we do; that path isn't tested in this
chapter.

### 10. GENERIC. Deploy on merge, once, to see it work

The loop is the same for every application, so try it with something small first. Any repository with a
`Dockerfile` will do; a folder holding one `index.html` and this two-line `Dockerfile` is plenty:

```dockerfile
FROM nginx:1.29-alpine
COPY index.html /usr/share/nginx/html/index.html
```

1. **A deploy key.** On your own computer, `ssh-keygen -t ed25519 -N "" -f coolify-deploy`. In the repository on
   GitHub: **Settings**, **Deploy keys**, add `coolify-deploy.pub`, read-only. In Coolify: **Keys & Tokens**,
   **Private Keys**, add `coolify-deploy`, the private half. Then delete both files from your computer; the keys
   live where they're used.
2. **The application.** In Coolify: **Projects**, make one, then add a resource: **Private Git Repository (with
   Deploy Key)**. Choose the control host as its server, the key from step 1, the repository's SSH address
   (`git@github.com:you/repo.git`), the branch `main`, and the build pack **Dockerfile**, with the folder holding
   the `Dockerfile` as **Base directory**. For this test, set **Port mappings** (under **Edit Networking**) to
   `127.0.0.1:8081:80`, so the site is only reachable from the control host itself. Deploy it. (Coolify also gives
   every application an address ending in `sslip.io`; with ports 80 and 443 closed at the control host's provider
   firewall, nobody outside can reach it.)
3. **The webhook.** In the application: **Webhooks**, **Manual Git webhooks**, **GitHub**. Press **Generate** for a
   secret, save, and copy the **Webhook URL**. On GitHub: **Settings**, **Webhooks**, **Add webhook**: that URL
   with your control host's public address in it, content type `application/json`, the same secret, just the push
   event. GitHub sends a test ping straight away; its delivery should show `200`.
4. **Merge something.** Change `index.html` in a pull request and merge it. Then, on the control host:

   ```sh
   curl -s http://127.0.0.1:8081/
   ```

   Within half a minute you should see your change. A push to any other branch deploys nothing.

That's the whole loop: a reviewed change on GitHub becomes a running change on your server, and nobody had to log
in to make it happen.

### 11. GENERIC. Settings reach a container when Coolify makes it again

Settings you add in Coolify reach the container the next time Coolify **deploys** or **restarts** it from the
dashboard; both made the container again on the test. Restarting the container any other way, such as `docker
restart` or a restart from inside the game, keeps the old settings.

Coolify also adds variables of its own to every container: on the test, `COOLIFY_URL`, `COOLIFY_FQDN`,
`COOLIFY_BRANCH` and others, plus `HOST`, `HOSTNAME` and `SOURCE_COMMIT`. Please don't give your own settings any
of those names.

### 12. GENERIC. An API token, for scripts and agents

Later chapters, and any agent you work with, talk to Coolify through its API. It's off after a new install.

1. **Settings**, **Advanced**, and under **API and MCP** set **API access** to **Enabled**.
2. **Keys & Tokens**, **API Tokens**, **New Token**. Give it a description, open **Permissions** and tick **Root**,
   and press **Create Token**.
3. The token is shown **once**. Put it straight into your password manager.

Two details: a new token **expires after 30 days** unless you choose otherwise under **Expires in**, so note the
date; and anyone holding a Root token can do everything you can in Coolify, so give each script or agent its own,
and delete it when it's done.

### 13. LAYONARA-ONLY. A name for the dashboard, and a queue helper

Our dashboard has its own name with HTTPS, so GitHub's webhooks travel encrypted, and we reach it without an SSH
tunnel. We also run a small helper that cancels queued deploys made pointless by a newer one: after a burst of nine
merges in half an hour, each deploy waited 15 to 18 minutes in line. A new server won't see that kind of queue for
a long while, which is why it belongs to tier 3.

## The agent playbook

If you work with an AI agent, [`playbooks/03-coolify.md`](../playbooks/03-coolify.md) has these steps in a fixed
shape it can follow. The admin account, the provider firewall and anything in GitHub's settings stay with you; the
agent installs, checks and wires the rest.

## Lessons

These are the things that went wrong for us, written down so they don't have to go wrong for you. The dates are
when they happened to Layonara.

- **Repair the proxy after Docker upgrades (2026-11-04).** A Docker upgrade left Coolify's proxy holding an old
  socket, and our websites were unreachable for five hours. The check in step 8 exists because of that day.
- **Use the plain repository webhook.** GitHub's app integration looked like the tidier way to deploy on merge, and
  its webhook never arrived. The repository webhook in step 10 has worked every time.
- **Don't reuse Coolify's names.** Coolify sets `COOLIFY_URL` in every container. We had a setting of the same
  name, and Coolify's value quietly replaced ours.
- **Script by name, not by container name.** Coolify adds a changing suffix to a container's name on each deploy.
  On the test the site's container was named after its application and the time of the deploy. Scripts that look
  for a container should look for the start of its name.
- **Write down what you type into Coolify.** Settings, variables and scheduled tasks entered in the dashboard live
  only in Coolify's own database. Keep a list of them somewhere you'd look if the control host were lost.

## Tested

On 2026-11-18, with Coolify 4.7.5, on two fresh Hetzner cloud servers of the smallest shared type that had been
through chapter 1, both tiers:

- the install, its port 8000 answering from outside before the provider firewall, and a second install run on top
  (safe);
- the admin account: refused for a password without a symbol and for `example.org` as the email domain, and the log
  line that says so; then made with a valid pair;
- Coolify refused as root on its own machine, and working as `nwn` on both machines, the game host added by its
  private address;
- the proxy on the game host publishing 80 and 443 past `ufw`; stopping it from the dashboard; a stand-in web
  server keeping 80 and 443 through a reboot;
- the volume setting's default;
- the proxy fault after restarting Docker's socket, and the check repairing it within a minute;
- the provider firewall: 8000 open only to GitHub's webhook senders and the game host, closed from elsewhere, and
  the **Attention required** state before the game host was allowed;
- a private repository with a deploy key and a manual GitHub webhook: the first deploy in about 24 seconds, merged
  changes live in 18 seconds, twice (once through the provider firewall), and no deploy for a push to another
  branch;
- a setting reaching the container on a dashboard restart and on a deploy; the variables Coolify adds;
- a reboot of both machines: Coolify, the application, the proxy and both servers came back usable;
- on a second pair of fresh servers, with the provider firewall in place first: the install exactly as step 2
  writes it; in the dashboard itself, skipping the setup wizard, switching the API on and making a Root token (step
  12); the real-time warning through a tunnel that carried only port 8000, and its absence with 6001 and 6002
  added; then the agent playbook as written, and a merge that was live 29 seconds later.

The servers, the key and the application were made through Coolify's API, which does what those dashboard pages do.
The dashboard's labels quoted in this chapter were read from the running dashboard on the day, and stopping the
proxy was done in the dashboard itself.

Not tested: clicking through the **New Server** and new application forms, Coolify's dashboard at its own name with
HTTPS, and other versions of Coolify.
