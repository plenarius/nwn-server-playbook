#!/bin/sh
# Run as root on a machine around a snapshot that new servers will be made from.
#
#   prepare-snapshot.sh before    just before you take the snapshot
#   prepare-snapshot.sh after     as soon as the snapshot is finished, and on each server made from it
#
# Chapter 1 switches cloud-init off and keeps the network file it wrote. That file names this machine's network
# card, so a server made from a snapshot of it boots with no network at all, and every copy would share this
# machine's id. "before" switches cloud-init back on and clears the id and cloud-init's memory, so each new
# server gets its own id, host keys and network, the way a fresh one does. "after" puts this machine back as it
# was: without it, its own next boot would give it new host keys too. On a server made from the snapshot,
# "after" keeps its new id and switches cloud-init off again, as chapter 1 does.
set -eu
[ "$(id -u)" = 0 ] || { echo "run this as root (sudo)" >&2; exit 1; }
SAVE=/var/lib/prepare-snapshot
case ${1:-} in
  before)
    [ ! -e "$SAVE/machine-id" ] || { echo "already prepared; run 'after' first" >&2; exit 1; }
    mkdir -p "$SAVE"
    cp /etc/machine-id "$SAVE/machine-id"
    hostname > "$SAVE/hostname"
    rm -f /etc/cloud/cloud-init.disabled
    cloud-init clean --logs --machine-id
    sync
    echo "ready to snapshot: cloud-init on, machine id cleared. Run '$0 after' once the snapshot is done."
    ;;
  after)
    [ -e "$SAVE/machine-id" ] || { echo "nothing to put back: 'before' was not run" >&2; exit 1; }
    if [ "$(cat "$SAVE/hostname")" = "$(hostname)" ]; then
      cp "$SAVE/machine-id" /etc/machine-id
      what="put back: machine id $(cat /etc/machine-id)"
    else
      what="a new server from the snapshot: keeps its own machine id $(cat /etc/machine-id)"
    fi
    touch /etc/cloud/cloud-init.disabled
    rm -r "$SAVE"
    sync
    echo "$what, cloud-init off"
    ;;
  *) sed -n '2,5p' "$0" >&2; exit 2 ;;
esac
