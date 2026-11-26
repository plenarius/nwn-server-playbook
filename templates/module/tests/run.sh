#!/usr/bin/env bash
# Builds the test module, starts a headless NWNX server with an empty database, runs every test, and reports.
# Exits 0 when every test passed (or was skipped), 1 when any failed or the run didn't finish.
#
#   tests/run.sh                    every test
#   tests/run.sh --filter t_db_     only the tests whose names start with t_db_
#   tests/run.sh --filter t_db_roundtrip,t_math_   a list: whole names, and prefixes ending in _ (chapter 6, tier 3)
#   tests/run.sh --boot-only        build and start the module, run no tests (a change no test reaches)
#   tests/run.sh --retry            run failed tests once more on a fresh server; a pass then is FLAKY (tier 3)
#   tests/run.sh --no-build         run the test module built last time
#   tests/run.sh --timeout 300      give up after this many seconds (default 600)
#   tests/run.sh --content URL      with the haks and talk table from your download address (tools/fetch_content.sh)
#
# Needs Docker with Compose, nasher, and NWN_ROOT as for building (chapter 6). The server image is NWNX_IMAGE,
# or else the one named in .github/workflows/compile-check.yml, so the tests and the check use the same.
# Haks and a talk table, if your module uses them: --content, or TEST_HAK_DIR and TEST_TLK_DIR (folders).
# Results go to tests/.run/: logs/ (the server's and the engine's logs, and its console), junit.xml (for CI),
# results.json, and flakes.jsonl when a test was flaky or quarantined. A test named in tests/quarantine.txt is run
# and reported, but its failure doesn't fail the run. TEST_LANE, if set, names the lane in those records.
set -euo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TESTS")
OUT=$TESTS/.run

FILTER=t_ BUILD=1 TIMEOUT=600 CONTENT= BOOT_ONLY=0 RETRY=0
while [ $# -gt 0 ]; do
  case $1 in
    --filter) FILTER=$2; shift ;;
    --boot-only) BOOT_ONLY=1 ;;
    --retry) RETRY=1 ;;
    --no-build) BUILD=0 ;;
    --timeout) TIMEOUT=$2; shift ;;
    --content) CONTENT=$2; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
for f in ${FILTER//,/ }; do
  [[ $f =~ ^t_[a-z0-9_]*$ ]] || { echo "--filter takes test names and prefixes that start with t_: not $f" >&2; exit 2; }
done
# A name no test can have: the runner finds nothing, and the module still loads and starts.
[ $BOOT_ONLY = 0 ] || FILTER=t_nothing
export TEST_FILTER=$FILTER
export NWNX_IMAGE=${NWNX_IMAGE:-$(sed -n 's/^ *NWNX_IMAGE: *//p' "$ROOT/.github/workflows/compile-check.yml" | head -n 1)}
[ -n "$NWNX_IMAGE" ] || { echo "set NWNX_IMAGE" >&2; exit 2; }
# One Docker project per checkout, so two checkouts on one machine don't stop each other's servers.
export COMPOSE_PROJECT_NAME=tests-$(printf %s "$ROOT ${TEST_LANE:-}" | sha1sum | cut -c1-8)
compose() { docker compose -f "$TESTS/compose.yaml" "$@"; }

mkdir -p "$OUT/modules" "$OUT/hak" "$OUT/tlk"
if [ $BUILD = 1 ]; then
  (cd "$ROOT" && nasher pack test --yes --abortOnCompileError > "$OUT/build.log" 2>&1) ||
    { tail -n 20 "$OUT/build.log"; echo "the test module did not build" >&2; exit 1; }
  python3 "$ROOT/tools/check_compiled.py" "$ROOT/test.mod" "$ROOT/src" > /dev/null
  python3 "$ROOT/tools/check_compiled.py" "$ROOT/test.mod" "$TESTS/nss"
  mv -f "$ROOT/test.mod" "$OUT/modules/test.mod"
fi
[ -f "$OUT/modules/test.mod" ] || { echo "no test module built yet: run without --no-build" >&2; exit 1; }

# The haks and talk table the module lists. Without them the server stops with "Unable to load module" and no
# reason, so check first. Compose reads relative folders from tests/, so make them whole paths.
if [ -n "$CONTENT" ]; then
  "$TESTS/tools/fetch_content.sh" "$CONTENT" "$TESTS/.content"
  TEST_HAK_DIR=$TESTS/.content/hak TEST_TLK_DIR=$TESTS/.content/tlk
fi
TEST_HAK_DIR=$(realpath "${TEST_HAK_DIR:-$OUT/hak}") TEST_TLK_DIR=$(realpath "${TEST_TLK_DIR:-$OUT/tlk}")
export TEST_HAK_DIR TEST_TLK_DIR
python3 "$TESTS/tools/check_content.py" "$OUT/modules/test.mod" "$TEST_HAK_DIR" "$TEST_TLK_DIR" ||
  { echo "the test server would not load this module" >&2; exit 1; }

# Starts a fresh server and database, runs the tests TEST_FILTER names, and copies the logs into $1.
run_server() {
  local logs=$1 started
  compose down --volumes --remove-orphans > /dev/null 2>&1 || true
  started=$(date +%s)
  compose up -d --quiet-pull > "$OUT/compose.log" 2>&1 || { cat "$OUT/compose.log"; echo "the test server did not start" >&2; exit 1; }
  # Wait for the runner's last line, for the server to stop by itself, or for the time limit.
  while :; do
    if compose exec -T nwserver grep -qs 'TEST|END|' /nwn/run/logs.0/nwserverLog1.txt 2>/dev/null; then break; fi
    if [ -z "$(compose ps -q --status running nwserver)" ]; then echo "the test server stopped before the tests finished" >&2; break; fi
    if [ $(( $(date +%s) - started )) -ge "$TIMEOUT" ]; then echo "the tests did not finish within $TIMEOUT s" >&2; break; fi
    sleep 1
  done
  rm -rf "$logs"; mkdir -p "$logs"
  compose cp nwserver:/nwn/run/logs.0/. "$logs/" > /dev/null 2>&1 || true
  compose logs --no-color --no-log-prefix nwserver > "$logs/console.txt" 2>&1 || true
  compose down --volumes --remove-orphans > /dev/null 2>&1 || true
  echo "server ran for $(( $(date +%s) - started )) s"
}
trap 'compose down --volumes --remove-orphans > /dev/null 2>&1 || true' EXIT

QUARANTINE=$TESTS/quarantine.txt
args=(--quarantine "$QUARANTINE" --json "$OUT/results.json" --flakes "$OUT/flakes.jsonl")
[ $BOOT_ONLY = 0 ] || args+=(--allow-empty)
rm -rf "$OUT/retry" "$OUT/flakes.jsonl"
run_server "$OUT/logs"
if [ $RETRY = 1 ]; then
  again=$(python3 "$TESTS/tools/results.py" "$OUT/logs" "$OUT/junit.xml" --failed --quarantine "$QUARANTINE")
  if [ -n "$again" ]; then
    echo "failed: $again; running them once more, on a fresh server"
    TEST_FILTER=$again run_server "$OUT/retry/logs"
    args+=(--retry-logs "$OUT/retry/logs")
  fi
fi
python3 "$TESTS/tools/results.py" "$OUT/logs" "$OUT/junit.xml" "${args[@]}"
