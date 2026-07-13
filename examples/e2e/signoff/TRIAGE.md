# Public testnet triage (first 5 steps)

Short runbook for operators after launch. Devnet rehearsal: [`README.md`](README.md).
Compose reference: `world-qc-docker/devnet/compose.yml` (public stacks differ in DNS/TLS only).

## 1. Is the orchestrator alive?

```bash
curl -sf https://<orch-host>/health   # or http://localhost:9001/health on devnet
curl -sf https://<orch-host>/api/v1/p2p/bootstrap | jq '{peer_id, multiaddrs}'
```

If health fails: check container/process, Redis, and recent deploy. Do **not** wipe Redis.

## 2. Are workers connected?

```bash
# per node (admin HTTP, often localhost-only)
curl -s http://127.0.0.1:8080/status | jq '{max_qubits,max_memory_gib,pending_tasks,outbox_pending}'
docker logs wqc-node-01 --tail 50   # look for Connected to peer / bootstrap errors
```

No bids: bootstrap URL, `WQC_TESTNET_NODE_KEY`, memory budget (`max_qubits` ≥ 10), stake.

## 3. Task stuck `pending` / `dispatched`?

```bash
curl -s "$ORCH/api/v1/task/$TASK_ID" | jq .
docker logs wqc-orchestrator-01 2>&1 | grep "$TASK_ID" | tail -40
docker exec wqc-redis redis-cli HGETALL "task:${TASK_ID}:meta"
```

| Clue | Likely cause |
| --- | --- |
| `failed to form quorum` | too few online nodes vs `required_votes` / security_level |
| rising `outbox_pending` | P2P deliver retry — node↔orch connectivity |
| rising `pending_tasks` | core slow/down — check `wqc-core` health |
| submit `400` | client payload / billing `client_id` |

## 4. Client cannot pay / faucet?

Public: dashboard faucet → Redis balance. Confirm:

```bash
docker exec wqc-redis redis-cli GET economy:client:<id>:balance
```

Orchestrator HTTP faucet is **removed**. E2E/dev uses Redis `SET` only.

## 5. Proof / consolidation failure?

```bash
docker logs wqc-orchestrator-01 2>&1 | grep -E 'proof|Root proof|aggregation|tamper|signature' | tail -40
```

Invalid peer bids are rejected at P2P receive (signature). Root proof failures fail the task (`proof aggregation failed`). Re-run a known-good curated case from `wqc-docs/examples/e2e/` before deep diving.

---

More detail: `AGENT_E2E.md`, `wqc-node/docs/OPERATIONS.md`, `wqc-orchestrator/docs/OBSERVABILITY.md`.
