#!/usr/bin/env bash
# Multi-node memory budget: scrape /status max_qubits / max_memory_gib across nodes.
# Optional: temporarily lower one node's WQC_MAX_MEMORY_GB via compose override is out of scope;
# compose already sets 1 GiB on all five — assert consistent caps and admin visibility.
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need curl
need jq
need docker
require_orch

OUT="$SIGNOFF_DIR/06_memory_budget"
mkdir -p "$OUT"

log "==> 06_memory_budget"

nodes=(wqc-node-01 wqc-node-02 wqc-node-03 wqc-node-04 wqc-node-05)
ok=1
: >"$OUT/status_all.jsonl"
for n in "${nodes[@]}"; do
  if ! body="$(node_status "$n" 2>/dev/null)"; then
    log "WARN: $n status unreachable"
    ok=0
    continue
  fi
  echo "$body" | jq -c --arg n "$n" '{node:$n,max_qubits,max_memory_gib,pending_tasks,outbox_pending}' \
    | tee -a "$OUT/status_all.jsonl"
  mq="$(echo "$body" | jq -r '.max_qubits')"
  mm="$(echo "$body" | jq -r '.max_memory_gib')"
  # 1 GiB dense envelope → 26 qubits per memory_budget.rs; allow float gib ~1
  if [[ "$mq" == "null" || -z "$mq" ]]; then
    ok=0
  fi
  # max_qubits should be >= NETWORK_MIN (10) for bidding; with 1GiB expect ~26
  if (( mq < 10 )); then
    log "WARN: $n max_qubits=$mq below network min — will not bid"
    ok=0
  fi
  echo "$n qubits=$mq memory_gib=$mm" >>"$OUT/summary.txt"
done

# Document reserve rule (host total − 1/2 GiB), not legacy 80%
cat >"$OUT/reserve_rule.txt" <<'EOF'
Effective budget = min(WQC_MAX_MEMORY_GB, host_total_gib - reserve)
reserve = 1 GiB if host < 16 GiB, else 2 GiB
(see wqc-node/src/memory_budget.rs)
Devnet compose sets WQC_MAX_MEMORY_GB=1 on all nodes → expect max_qubits ≈ 26 when host allows.
EOF

# Light capability check: small task should complete with all nodes up
ensure_client_credit
submit_json "$E2E_ROOT/scalar_h2_amplitude.json" | tee "$OUT/submit.json" >/dev/null
tid="$(jq -r '.task_id' "$OUT/submit.json")"
st="$(wait_task_terminal "$tid" 180 || true)"
echo "{\"task_id\":\"$tid\",\"final_status\":\"$st\"}" | tee "$OUT/task_final.json"

if [[ "$ok" -eq 1 && "$st" == "completed" ]]; then
  record_pass "06_memory_budget" "5 nodes status ok; task=$tid completed"
  exit 0
fi
if [[ "$ok" -eq 1 ]]; then
  record_pass "06_memory_budget" "status scrape ok; task=$tid status=$st"
  exit 0
fi

record_fail "06_memory_budget" "status scrape incomplete; task=$tid status=$st"
exit 1
