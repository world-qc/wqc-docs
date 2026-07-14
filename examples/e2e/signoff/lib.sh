#!/usr/bin/env bash
# Shared helpers for signoff drills.
set -euo pipefail

SIGNOFF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
E2E_ROOT="$(cd "$SIGNOFF_ROOT/.." && pwd)"
EXAMPLES_ROOT="$(cd "$E2E_ROOT/.." && pwd)"
CIRCUITS_ROOT="$EXAMPLES_ROOT/circuits"
REPO_ROOT="$(cd "$SIGNOFF_ROOT/../../../.." && pwd)"
ORCH_URL="${ORCH_URL:-http://localhost:9001}"
COMPOSE_DIR="${COMPOSE_DIR:-$REPO_ROOT/world-qc-docker/devnet}"
SIGNOFF_DIR="${SIGNOFF_DIR:-/tmp/wqc-signoff-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$SIGNOFF_DIR"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing: $1"; }

require_orch() {
  curl -sf "$ORCH_URL/health" >/dev/null || die "orchestrator not reachable at $ORCH_URL — cd world-qc-docker/devnet && docker compose up -d"
}

# Node images may lack curl; share the node's network namespace from a curl sidecar.
node_status() {
  local name="${1:?node container}"
  if docker exec "$name" sh -c 'command -v curl >/dev/null' 2>/dev/null; then
    docker exec "$name" curl -sf "http://127.0.0.1:8080/status"
    return
  fi
  docker run --rm --network "container:$name" curlimages/curl:8.5.0 \
    -sf "http://127.0.0.1:8080/status"
}

ensure_client_credit() {
  local client="${CLIENT_ID:-client-01}"
  # Default covers 28q TN / multislice escrow (~4e18+ per task); override via CLIENT_CREDIT_PWQC.
  local amount="${CLIENT_CREDIT_PWQC:-100000000000000000000}"
  docker exec wqc-redis redis-cli SET "economy:client:${client}:balance" "$amount" >/dev/null
}

submit_json() {
  local path="$1"
  curl -sf -X POST "$ORCH_URL/api/v1/submit" \
    -H 'Content-Type: application/json' \
    -d @"$path"
}

task_status() {
  local tid="$1"
  curl -sf "$ORCH_URL/api/v1/task/$tid" | jq -r '.status'
}

wait_task_terminal() {
  local tid="$1"
  local timeout="${2:-180}"
  local deadline=$((SECONDS + timeout))
  local st="unknown"
  while (( SECONDS < deadline )); do
    st="$(task_status "$tid" || echo unknown)"
    if [[ "$st" == "completed" || "$st" == "failed" ]]; then
      echo "$st"
      return 0
    fi
    sleep 2
  done
  echo "$st"
  return 1
}

record_pass() {
  local name="$1"
  local note="${2:-}"
  mkdir -p "$SIGNOFF_DIR"
  {
    echo "## $name"
    echo "- result: PASS"
    echo "- time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [[ -n "$note" ]] && echo "- note: $note"
    echo
  } >>"$SIGNOFF_DIR/DRILLS.md"
  log "PASS [$name] $note"
}

record_fail() {
  local name="$1"
  local note="${2:-}"
  mkdir -p "$SIGNOFF_DIR"
  {
    echo "## $name"
    echo "- result: FAIL"
    echo "- time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [[ -n "$note" ]] && echo "- note: $note"
    echo
  } >>"$SIGNOFF_DIR/DRILLS.md"
  log "FAIL [$name] $note" >&2
}
