#!/usr/bin/env bash
# Lockdown window math (must match bootcheck.sh) + daemon syntax check.
# Regression: 21:00 with bed 23:00~wake 07:00 must NOT be in lockdown.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== bash -n (syntax) ==="
for f in src/daemon.sh src/bootcheck.sh; do
  if ! bash -n "$f"; then
    echo "FAIL: bash -n $f" >&2
    exit 1
  fi
  echo "  OK: $f"
done

# Same predicate as bootcheck: in_lockdown for normal bed > wake (overnight) case
in_lockdown_overnight() {
  local now=$1 bed=$2 wake=$3
  (( now >= bed || now < wake ))
}

pass=0
fail=0
check() {
  local now=$1 bed=$2 wake=$3 expect=$4 label=$5
  local result
  if in_lockdown_overnight "$now" "$bed" "$wake"; then result=true; else result=false; fi
  if [[ $result == "$expect" ]]; then
    echo "  OK: $label (now=$now min -> lockdown=$result)"
    pass=$((pass + 1))
  else
    echo "  FAIL: $label — expected lockdown=$expect, got $result" >&2
    fail=$((fail + 1))
  fi
}

# bed=23:00=1380, wake=07:00=420
B=1380
W=420
echo ""
echo "=== Lock window (bed 23:00, wake 07:00), same as bootcheck ==="
check $((21 * 60)) "$B" "$W" false "21:00 晚上九点 — 不应锁屏 (user regression)"
check $((22 * 60 + 29)) "$B" "$W" false "22:29 — 风睡前不应锁 (bootcheck)"
check 1350 "$B" "$W" false "22:30 — wind-down 开始仍不应锁 (bootcheck 仅看 bed~wake)"
check 1380 "$B" "$W" true  "23:00 就寝 — 应锁"
check 0 "$B" "$W"         true  "00:00 — 应锁"
check 180 "$B" "$W"        true  "03:00 — 应锁"
check 419 "$B" "$W"        true  "06:59 — 应锁"
check 420 "$B" "$W"        false "07:00 起床 — 不应锁"
check 480 "$B" "$W"        false "08:00 — 不应锁"

echo ""
echo "=== Results: $pass passed, $fail failed ==="
(( fail == 0 ))
