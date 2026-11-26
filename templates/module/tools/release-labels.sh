#!/usr/bin/env bash
# Makes the release train's labels in a repository (or updates their descriptions). Chapter 16, tier 3.
#   tools/release-labels.sh owner/name
# The names must match .github/release.yml and the label check in workflows/release-train.yml.
set -euo pipefail
repo=${1:?usage: $0 owner/name}
while IFS='|' read -r name colour about; do
  gh label create "$name" -R "$repo" -c "$colour" -d "$about" -f > /dev/null && echo "label $name"
done <<'LABELS'
feature|1d76db|New in the world: players will notice it
content|0e8a16|New areas, items, creatures, music
balance|fbca04|Numbers players will feel
fix|d93f0b|Fixed
release-fix|b60205|A fix for the coming release, allowed through its freeze
tooling|c5def5|For builders and staff
no-changelog|ededed|Nobody needs to read about it: left out of the notes and the changelog
LABELS
