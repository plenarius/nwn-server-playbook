# Playbook 2. Give the server a name (tier 1)

For an agent. The chapter for people is [`chapters/02-dns.md`](../chapters/02-dns.md). Follow the steps in order.
Do not go on from a step whose check fails.

This playbook creates the record with [`templates/dns/cf-record.sh`](../templates/dns/cf-record.sh), which works
with Cloudflare DNS only. If the domain's DNS is somewhere else, a person creates the record by hand (chapter,
step 3). You then skip step 2 and the first Verify check, and do the rest.

## Inputs

| Name | Meaning | Default |
|---|---|---|
| `DOMAIN` | The domain, such as `example.org` | none: a person gives it |
| `NAME` | The full name to create | `game.$DOMAIN` |
| `SERVER` | The server's public IPv4 address, from playbook 1 | none: a person gives it |
| `DEPLOY_USER` | The account made in playbook 1 | `nwn` |
| `TTL` | Seconds an answer may be remembered | `300` |

Secrets: `CF_API_TOKEN` (a token that may edit DNS in this one zone) and `CF_ZONE_ID`. A person puts both in the
environment of the shell you run in. Never ask for the token in a prompt, never print it, and never print a raw
answer from the DNS host's API. The script prints neither.

## Preconditions

Playbook 1 is done and the settings are there:

```sh
ssh -o BatchMode=yes $DEPLOY_USER@$SERVER true && echo "server ok"
[ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ] && echo "settings ok"
```

Success: `server ok` and `settings ok`.

The name has no record yet. Ask the DNS host, not a resolver:

```sh
templates/dns/cf-record.sh show $NAME
```

Success: `no record for $NAME`. If it prints a record, stop and ask.

**Do not look the name up with `dig`, `host`, `ping` or `ssh` before the record exists.** A resolver that is asked
too early remembers "no such name" for up to 30 minutes, and every later check through it then looks like a
failure.

## Steps

### 1. Say what you will create, and wait

Tell the person exactly this, with the values filled in, and wait for a yes:

> I will create one DNS record: `A $NAME` pointing at `$SERVER`, not proxied, TTL `$TTL`, in `$DOMAIN`.

A DNS record is public the moment it exists. Do not create it on an earlier, general go-ahead.

### 2. Create the record

```sh
TTL=$TTL templates/dns/cf-record.sh create $NAME $SERVER
```

Success: `created A $NAME $SERVER dns-only ttl $TTL`.

### 3. Check it at the source

```sh
NS=$(dig +short NS $DOMAIN | head -1)
dig +short $NAME A @$NS
```

Success: `$SERVER` and nothing else. It took up to 4 seconds on the test. Try again for up to a minute before you
call it a failure.

## Verify

```sh
templates/dns/cf-record.sh show $NAME
```

Success: `A $NAME $SERVER dns-only ttl $TTL comment: nwn-server-playbook`.

```sh
dig +short $NAME AAAA @$NS
```

Success: no output. The game server listens on IPv4 only, so the name must have no IPv6 address.

```sh
for r in 1.1.1.1 8.8.8.8; do dig +short $NAME A @$r; done
```

Success: `$SERVER` twice. An empty line here is not a failure while step 3 still succeeds: that resolver holds an
old "no such name" answer. Wait five minutes and try again, for up to 30 minutes.

```sh
ssh -o BatchMode=yes -o HostKeyAlias=$SERVER $DEPLOY_USER@$NAME hostname
```

Success: the server's host name, exit status 0. `HostKeyAlias` makes SSH check the machine behind the name against
the key already stored for the address, so no new key has to be trusted. `Could not resolve hostname` means your
own resolver holds the old answer: wait, as above. `Host key verification failed` means the name does not lead to
the server from playbook 1: stop and ask.

## Roll back

```sh
templates/dns/cf-record.sh delete $NAME
```

Success: `deleted A $NAME $SERVER`. Resolvers may go on giving the old answer for `$TTL` seconds. The script
refuses to delete a record it did not make.

Cannot be undone: the name was public while it existed, and others may have recorded it.

## Stop and ask

Hand back to a person, with what you found, before any of these:

- creating, changing or deleting any DNS record (step 1 is not optional, and a roll back needs a yes too);
- a name that already has a record;
- turning the proxy on or off for any name;
- touching any record this playbook did not create;
- `Cloudflare said: Authentication error`. Do not try again with another token or another guess: repeated failed
  attempts can get your address limited;
- `Host key verification failed` when you log in by name;
- the source (step 3) still not answering after a minute.
