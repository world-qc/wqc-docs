#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need curl
need jq
require_orch

LOG_DIR="${LOG_DIR:-$SIGNOFF_DIR/e2e-all}"
export ORCH_URL TIER=all LOG_DIR
mkdir -p "$LOG_DIR"
log "==> 02_e2e_all LOG_DIR=$LOG_DIR (includes slow multislice_28q_zz)"
if "$E2E_ROOT/run_e2e.sh"; then
  record_pass "02_e2e_all" "LOG_DIR=$LOG_DIR"
  exit 0
fi
record_fail "02_e2e_all" "LOG_DIR=$LOG_DIR"
exit 1
