#!/usr/bin/env bash
# Builds the test module, starts a headless NWNX server with an empty database, runs every test, and reports.
# Exits 0 when every test passed (or was skipped), 1 when any failed or the run didn't finish.
#
#   tests/run.sh                    every test
#   tests/run.sh --filter t_db_     only the tests whose names start with t_db_
#   tests/run.sh --no-build         run the test module built last time
#   tests/run.sh --timeout 300      give up after this many seconds (default 600)
#
# Needs Docker with Compose, nasher, and NWN_ROOT as for building (chapter 6). The server image is NWNX_IMAGE,
# or else the one named in .github/workflows/compile-check.yml, so the tests and the check use the same.
# Haks and a talk table, if your module uses them: TEST_HAK_DIR and TEST_TLK_DIR (folders; read-only).
# Results go to tests/.run/: logs/ (the server's and the engine's logs, and its console) and junit.xml (for CI).
set -euo pipefail
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TESTS")
OUT=$TESTS/.run

FILTER=t_ BUILD=1 TIMEOUT=600
while [ $# -gt 0 ]; do
  case $1 in
    --filter) FILTER=$2; shift ;;
    --no-build) BUILD=0 ;;
    --timeout) TIMEOUT=$2; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
case $FILTER in t_*) ;; *) echo "--filter must start with t_" >&2; exit 2 ;; esac

export TEST_FILTER=$FILTER
export NWNX_IMAGE=${NWNX_IMAGE:-$(sed -n 's/^ *NWNX_IMAGE: *//p' "$ROOT/.github/workflows/compile-check.yml" | head -n 1)}
[ -n "$NWNX_IMAGE" ] || { echo "set NWNX_IMAGE" >&2; exit 2; }
# One Docker project per checkout, so two checkouts on one machine don't stop each other's servers.
export COMPOSE_PROJECT_NAME=tests-$(printf %s "$ROOT" | sha1sum | cut -c1-8)
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

save_logs() {
  rm -rf "$OUT/logs"; mkdir -p "$OUT/logs"
  compose cp nwserver:/nwn/run/logs.0/. "$OUT/logs/" > /dev/null 2>&1 || true
  compose logs --no-color --no-log-prefix nwserver > "$OUT/logs/console.txt" 2>&1 || true
}
compose down --volumes --remove-orphans > /dev/null 2>&1 || true
trap 'compose down --volumes --remove-orphans > /dev/null 2>&1 || true' EXIT
started=$(date +%s)
compose up -d --quiet-pull > "$OUT/compose.log" 2>&1 || { cat "$OUT/compose.log"; echo "the test server did not start" >&2; exit 1; }

# Wait for the runner's last line, for the server to stop by itself, or for the time limit.
while :; do
  if compose exec -T nwserver grep -qs 'TEST|END|' /nwn/run/logs.0/nwserverLog1.txt 2>/dev/null; then break; fi
  if [ -z "$(compose ps -q --status running nwserver)" ]; then echo "the test server stopped before the tests finished" >&2; break; fi
  if [ $(( $(date +%s) - started )) -ge "$TIMEOUT" ]; then echo "the tests did not finish within $TIMEOUT s" >&2; break; fi
  sleep 1
done
save_logs
echo "server ran for $(( $(date +%s) - started )) s"
python3 "$TESTS/tools/results.py" "$OUT/logs" "$OUT/junit.xml"
