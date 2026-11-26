#!/usr/bin/env bash
# Run once after you copy or clone this repository. It tells nasher, for this folder only,
# to stop when a script fails to compile instead of building a module without it.
set -euo pipefail
nasher config --local --set abortOnCompileError true
nasher config --local --list
