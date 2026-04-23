#!/usr/bin/env bash
# Ensures config_get reads numeric JSON fields when jq is unavailable (winddown_minutes).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

printf '%s\n' '{"bedtime":"23:00","winddown_minutes":45}' >"$TMP"

source "$ROOT_DIR/lib/config.sh"
# Must set after source — lib/config.sh defines ZZZ_CONFIG to ~/.timetosleep/config.json
ZZZ_CONFIG="$TMP"
# Force grep fallback even when jq is installed
_has_jq() { return 1; }

v=$(config_get winddown_minutes)
if [[ "$v" != "45" ]]; then
  echo "FAIL: expected winddown_minutes=45, got '$v'" >&2
  exit 1
fi

echo "OK config numeric fallback"
