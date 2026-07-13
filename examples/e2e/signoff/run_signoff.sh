#!/usr/bin/env bash
# Full §6 signoff runner. SKIP_SLOW=1 skips 02_e2e_all (not sufficient to close §6).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$ROOT/lib.sh"

need curl
need jq
need docker
require_orch

export SIGNOFF_DIR
: >"$SIGNOFF_DIR/DRILLS.md"
{
  echo "# Signoff run"
  echo "- started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- ORCH_URL: $ORCH_URL"
  echo "- SIGNOFF_DIR: $SIGNOFF_DIR"
  echo "- SKIP_SLOW: ${SKIP_SLOW:-0}"
  echo
} | tee "$SIGNOFF_DIR/RUN.txt"

if command -v docker >/dev/null; then
  docker images world-qc/wqc-core:latest --format '{{.Digest}}' 2>/dev/null | tee "$SIGNOFF_DIR/core_digest.txt" || true
fi

fail=0
run_step() {
  local script="$1"
  log ""
  log "######## $script ########"
  if ! "$ROOT/$script"; then
    fail=$((fail + 1))
    log "step failed: $script (continuing)"
  fi
}

run_step 01_e2e_fast.sh
if [[ "${SKIP_SLOW:-0}" == "1" ]]; then
  log "SKIP 02_e2e_all (SKIP_SLOW=1) — §6 still requires a TIER=all run"
  echo "- 02_e2e_all: SKIPPED (SKIP_SLOW=1)" >>"$SIGNOFF_DIR/DRILLS.md"
else
  run_step 02_e2e_all.sh
fi
run_step 03_node_restart.sh
run_step 04_orch_restart.sh
run_step 05_fault_injection.sh
run_step 06_memory_budget.sh

{
  echo
  echo "- finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- failures: $fail"
} | tee -a "$SIGNOFF_DIR/RUN.txt"

log ""
log "Signoff artifacts: $SIGNOFF_DIR"
log "Copy notes into RESULT.md from RESULT.template.md"
[[ "$fail" -eq 0 ]]
exit $?
