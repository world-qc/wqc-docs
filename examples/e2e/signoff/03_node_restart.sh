#!/usr/bin/env bash
# Node restart drill: submit work, restart wqc-node-01, confirm admin status + task progress.
# Aligns with wqc-node/docs/OPERATIONS.md Crash recovery.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need curl
need jq
need docker
require_orch
ensure_client_credit

NODE="${NODE_CONTAINER:-wqc-node-01}"
OUT="$SIGNOFF_DIR/03_node_restart"
mkdir -p "$OUT"

log "==> 03_node_restart node=$NODE"

before="$(node_status "$NODE" || true)"
echo "$before" | tee "$OUT/status_before.json" | jq -c '{pending_tasks,outbox_pending,max_qubits,max_memory_gib}' || true

# Prefer a short-lived but real task so restart may land mid-flight or shortly after.
PAYLOAD="$CIRCUITS_ROOT/sample/sample_bell_counts.json"
submit_json "$PAYLOAD" | tee "$OUT/submit.json" >/dev/null
tid="$(jq -r '.task_id' "$OUT/submit.json")"
[[ -n "$tid" && "$tid" != null ]] || { record_fail "03_node_restart" "submit failed"; exit 1; }
log "task_id=$tid"

# Brief wait so dispatch can start, then restart.
sleep 2
docker restart "$NODE" | tee "$OUT/restart.txt"
# Wait for admin HTTP
for _ in $(seq 1 30); do
  if node_status "$NODE" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

after="$(node_status "$NODE")"
echo "$after" | tee "$OUT/status_after.json" | jq -c '{pending_tasks,outbox_pending,max_qubits,max_memory_gib,health}' || true

# Task should still reach a terminal state via remaining nodes / retries.
st="$(wait_task_terminal "$tid" 240 || true)"
echo "{\"task_id\":\"$tid\",\"final_status\":\"$st\"}" | tee "$OUT/task_final.json"

# Capture recent node logs for outbox / worker markers
docker logs "$NODE" --tail 80 2>&1 | tee "$OUT/node_tail.log" >/dev/null || true

if [[ "$st" == "completed" || "$st" == "failed" ]]; then
  # completed is ideal; failed is still evidence that orch did not hang forever.
  note="task=$tid status=$st pending_after=$(echo "$after" | jq -r '.pending_tasks') outbox_after=$(echo "$after" | jq -r '.outbox_pending')"
  if [[ "$st" == "completed" ]]; then
    record_pass "03_node_restart" "$note"
    exit 0
  fi
  # failed after restart is acceptable for signoff if status API recovered
  record_pass "03_node_restart" "$note (terminal failed; admin status recovered)"
  exit 0
fi

record_fail "03_node_restart" "task=$tid stuck status=$st"
exit 1
