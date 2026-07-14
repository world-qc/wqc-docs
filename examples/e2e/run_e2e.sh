#!/usr/bin/env bash
# E2E runner — see ../E2E.md
set -euo pipefail

ORCH_URL="${ORCH_URL:-http://localhost:9001}"
CLIENT_ID="${CLIENT_ID:-client-01}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${SCRIPT_DIR}/manifest.tsv"
TIER="${TIER:-fast}"
POLL_SECS="${POLL_SECS:-3}"
LOG_DIR="${LOG_DIR:-/tmp/wqc-e2e-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$LOG_DIR"

# shellcheck source=assert_manifest.sh
source "$SCRIPT_DIR/assert_manifest.sh"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need curl
need jq

echo "==> orchestrator health: $ORCH_URL"
curl -sf "$ORCH_URL/health" >/dev/null || { echo "orchestrator not reachable at $ORCH_URL" >&2; exit 1; }

if command -v docker >/dev/null 2>&1; then
  docker images world-qc/wqc-core:latest --format 'wqc-core: {{.Digest}} ({{.CreatedSince}})' 2>/dev/null \
    | tee "$LOG_DIR/core_image.txt" || true
fi

echo "==> client credit via Redis ($CLIENT_ID)"
REDIS_CONTAINER="${REDIS_CONTAINER:-wqc-redis}"
AMOUNT_PWQC="${CLIENT_CREDIT_PWQC:-100000000000000000000}"
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -qx "$REDIS_CONTAINER"; then
  docker exec "$REDIS_CONTAINER" redis-cli SET "economy:client:${CLIENT_ID}:balance" "$AMOUNT_PWQC" >/dev/null
  bal="$(docker exec "$REDIS_CONTAINER" redis-cli GET "economy:client:${CLIENT_ID}:balance")"
  echo "{\"client_id\":\"$CLIENT_ID\",\"balance_pwqc\":\"$bal\"}"
else
  need redis-cli
  REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
  REDIS_PORT="${REDIS_PORT:-6379}"
  if [[ -n "${REDIS_URL:-}" ]]; then
    redis-cli -u "$REDIS_URL" SET "economy:client:${CLIENT_ID}:balance" "$AMOUNT_PWQC" >/dev/null
    bal="$(redis-cli -u "$REDIS_URL" GET "economy:client:${CLIENT_ID}:balance")"
  else
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "economy:client:${CLIENT_ID}:balance" "$AMOUNT_PWQC" >/dev/null
    bal="$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "economy:client:${CLIENT_ID}:balance")"
  fi
  echo "{\"client_id\":\"$CLIENT_ID\",\"balance_pwqc\":\"$bal\"}"
fi

pass=0
fail=0
skip=0

run_case() {
  local name="$1" file="$2" timeout="$3" tier="$4" notes="$5"
  if [[ "$tier" != "$TIER" && "$TIER" != "all" ]]; then
    echo "SKIP [$name] tier=$tier (TIER=$TIER)"
    skip=$((skip + 1))
    return 0
  fi

  local path="$SCRIPT_DIR/$file"
  echo ""
  echo "=== CASE: $name ($file) — $notes"
  local submit_log="$LOG_DIR/${name}_submit.json"
  local poll_log="$LOG_DIR/${name}_poll.jsonl"
  local manifest_log="$LOG_DIR/${name}_manifest.json"

  if ! curl -sf -X POST "$ORCH_URL/api/v1/submit" \
    -H 'Content-Type: application/json' \
    -d @"$path" | tee "$submit_log" | jq -e '.task_id' >/dev/null; then
    echo "FAIL [$name] submit HTTP error"
    fail=$((fail + 1))
    return 1
  fi

  local task_id
  task_id="$(jq -r '.task_id' "$submit_log")"
  echo "task_id=$task_id"

  local deadline=$((SECONDS + timeout))
  local status="unknown"
  while (( SECONDS < deadline )); do
    local body
    body="$(curl -sf "$ORCH_URL/api/v1/task/$task_id")"
    echo "$body" | jq -c . | tee -a "$poll_log"
    status="$(echo "$body" | jq -r '.status')"
    if [[ "$status" == "completed" || "$status" == "failed" ]]; then
      break
    fi
    sleep "$POLL_SECS"
  done

  if [[ "$status" != "completed" ]]; then
    echo "FAIL [$name] status=$status (see $poll_log)"
    docker logs wqc-orchestrator-01 --tail 40 2>&1 | tee "$LOG_DIR/${name}_orch.log" >/dev/null || true
    docker logs wqc-node-01 --tail 20 2>&1 | tee "$LOG_DIR/${name}_node.log" >/dev/null || true
    fail=$((fail + 1))
    return 1
  fi

  local fetched=0
  for _ in 1 2 3; do
    local manifest_url
    manifest_url="$(jq -r '.manifest_url // empty' "$poll_log" | tail -1)"
    if [[ -n "$manifest_url" ]]; then
      local host_url="${manifest_url//wqc-s3-storage:9000/localhost:9000}"
      if curl -sf "$host_url" | jq -c . >"$manifest_log" 2>/dev/null && [[ -s "$manifest_log" ]]; then
        fetched=1
        break
      fi
    fi
    if docker exec wqc-s3-storage mc cat "local/wqc-results/manifests/${task_id}.json" 2>/dev/null \
      | jq -c . >"$manifest_log" 2>/dev/null && [[ -s "$manifest_log" ]]; then
      fetched=1
      break
    fi
    sleep 1
  done
  if [[ "$fetched" != "1" ]]; then
    echo "FAIL [$name] manifest fetch failed (task_id=$task_id)"
    fail=$((fail + 1))
    return 1
  fi

  if ! assert_manifest "$name" "$manifest_log"; then
    echo "FAIL [$name] manifest assertion (see $manifest_log)"
    fail=$((fail + 1))
    return 1
  fi

  echo "PASS [$name]"
  pass=$((pass + 1))
}

while IFS=$'\t' read -r name file timeout tier notes || [[ -n "${name:-}" ]]; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  run_case "$name" "$file" "$timeout" "$tier" "$notes" || true
done < "$MANIFEST"

echo ""
echo "==> summary: pass=$pass fail=$fail skip=$skip logs=$LOG_DIR"
[[ "$fail" -eq 0 ]]
