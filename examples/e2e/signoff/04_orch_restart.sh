#!/usr/bin/env bash
# Orchestrator restart: submit (or idle), restart orch, confirm health/bootstrap and task outcome.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need curl
need jq
need docker
require_orch
ensure_client_credit

ORCH="${ORCH_CONTAINER:-wqc-orchestrator-01}"
OUT="$SIGNOFF_DIR/04_orch_restart"
mkdir -p "$OUT"

log "==> 04_orch_restart orch=$ORCH"

PAYLOAD="$E2E_ROOT/scalar_h2_amplitude.json"
submit_json "$PAYLOAD" | tee "$OUT/submit.json" >/dev/null
tid="$(jq -r '.task_id' "$OUT/submit.json")"
[[ -n "$tid" && "$tid" != null ]] || { record_fail "04_orch_restart" "submit failed"; exit 1; }
log "task_id=$tid"
sleep 1

docker restart "$ORCH" | tee "$OUT/restart.txt"

# Wait for health
ok=0
for _ in $(seq 1 60); do
  if curl -sf "$ORCH_URL/health" >/dev/null; then
    ok=1
    break
  fi
  sleep 1
done
[[ "$ok" -eq 1 ]] || { record_fail "04_orch_restart" "health did not return"; exit 1; }
curl -sf "$ORCH_URL/health" | tee "$OUT/health.json" >/dev/null

boot="$(curl -sf "$ORCH_URL/api/v1/p2p/bootstrap" || true)"
echo "$boot" | tee "$OUT/bootstrap.json" >/dev/null
peer="$(echo "$boot" | jq -r '.peer_id // empty')"
[[ -n "$peer" ]] || { record_fail "04_orch_restart" "bootstrap missing peer_id"; exit 1; }

# Give air/reload a moment; nodes re-dial bootstrap.
sleep 5
st="$(wait_task_terminal "$tid" 300 || true)"
echo "{\"task_id\":\"$tid\",\"final_status\":\"$st\",\"bootstrap_peer\":\"$peer\"}" | tee "$OUT/task_final.json"

docker logs "$ORCH" --tail 60 2>&1 | tee "$OUT/orch_tail.log" >/dev/null || true

if [[ "$st" == "completed" ]]; then
  record_pass "04_orch_restart" "task=$tid completed peer=$peer"
  exit 0
fi
if [[ "$st" == "failed" ]]; then
  # Explicit failure after restart is acceptable evidence of defined behavior.
  record_pass "04_orch_restart" "task=$tid failed (defined) peer=$peer"
  exit 0
fi

# Pre-restart task may be lost from in-memory state; prove post-restart submit works.
submit_json "$PAYLOAD" | tee "$OUT/submit_after.json" >/dev/null
tid2="$(jq -r '.task_id' "$OUT/submit_after.json")"
st2="$(wait_task_terminal "$tid2" 180 || true)"
echo "{\"task_id\":\"$tid2\",\"final_status\":\"$st2\"}" | tee "$OUT/task_after_final.json"
if [[ "$st2" == "completed" ]]; then
  record_pass "04_orch_restart" "pre_task=$tid status=$st; post_submit=$tid2 completed; peer=$peer"
  exit 0
fi

record_fail "04_orch_restart" "pre=$tid/$st post=$tid2/$st2"
exit 1
