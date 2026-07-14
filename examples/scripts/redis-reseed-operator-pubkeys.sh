#!/usr/bin/env bash
# Register economy:operator:{id}:pubkey in Redis from WQC_TESTNET_NODE_KEY values in
# examples/compose.yml (local E2E — no dashboard required).
#
# Run after first `docker compose up` or any Redis flush that drops operator pubkeys.
# Bids fail with "operator verification failed" until pubkeys are present.
#
# Usage (from wqc-docs repo root):
#   ./examples/scripts/redis-reseed-operator-pubkeys.sh
#
#   REDIS_URL=redis://127.0.0.1:6379 ./examples/scripts/redis-reseed-operator-pubkeys.sh
#   COMPOSE_FILE=examples/compose.yml ./examples/scripts/redis-reseed-operator-pubkeys.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-$EXAMPLES_ROOT/compose.yml}"
REDIS_URL="${REDIS_URL:-redis://127.0.0.1:6379}"
REDIS_CONTAINER="${REDIS_CONTAINER:-wqc-redis}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need node

redis_cli() {
  if command -v docker >/dev/null 2>&1 \
    && docker ps --format '{{.Names}}' | grep -qx "$REDIS_CONTAINER"; then
    docker exec "$REDIS_CONTAINER" redis-cli "$@"
    return
  fi
  redis-cli -u "$REDIS_URL" "$@"
}

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "compose file not found: $COMPOSE_FILE" >&2
  exit 1
fi

node_keys=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # YAML: WQC_TESTNET_NODE_KEY: nk_e2e-node-01
  if [[ "$line" =~ WQC_TESTNET_NODE_KEY:[[:space:]]*(.+)$ ]]; then
    val="${BASH_REMATCH[1]}"
    val="${val%%#*}"
    val="$(echo "$val" | tr -d ' \"')"
    [[ -n "$val" && "$val" != \$\{* ]] && node_keys+=("$val")
  fi
done < "$COMPOSE_FILE"

if [[ "${#node_keys[@]}" -eq 0 ]]; then
  echo "No literal WQC_TESTNET_NODE_KEY values in $COMPOSE_FILE" >&2
  exit 1
fi

deduped=()
while IFS= read -r nk; do
  [[ -n "$nk" ]] && deduped+=("$nk")
done < <(printf '%s\n' "${node_keys[@]}" | sort -u)
node_keys=("${deduped[@]}")

echo "Compose: $COMPOSE_FILE"
echo "Re-seeding operator pubkeys for ${#node_keys[@]} node key(s)"
echo

registered=0
for node_key in "${node_keys[@]}"; do
  read -r operator_id pubkey_b64 < <(
    node -e "
      import { deriveOperatorFromNodeKey } from '${SCRIPT_DIR}/lib/derive-operator.mjs';
      const { operatorId, publicKeyB64 } = deriveOperatorFromNodeKey(process.argv[1]);
      console.log(operatorId + ' ' + publicKeyB64);
    " "$node_key"
  )
  redis_cli SET "economy:operator:${operator_id}:pubkey" "$pubkey_b64" >/dev/null
  echo "SET economy:operator:${operator_id}:pubkey  (${node_key})"
  registered=$((registered + 1))
done

echo
echo "Done: registered $registered operator pubkey(s)."
