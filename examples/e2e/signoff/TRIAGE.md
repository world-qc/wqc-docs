# Public testnet triage (first 5 steps)

Short runbook for operators after launch. Rehearsal harness: [`README.md`](README.md). Reference stack and E2E runner: [`../../E2E.md`](../../E2E.md).

## 1. Is the orchestrator alive?

```bash
curl -sf https://<orch-host>/health
curl -sf https://<orch-host>/api/v1/p2p/bootstrap | jq '{peer_id, multiaddrs}'
```

If health fails: check process/container, economy store, and recent deploy. Do **not** wipe the economy store casually.

## 2. Are workers connected?

```bash
# per node (admin HTTP, often localhost-only)
curl -s http://127.0.0.1:8080/status | jq '{max_qubits,max_memory_gib,pending_tasks,outbox_pending}'
# worker logs — look for Connected to peer / bootstrap errors
```

No bids: bootstrap URL, node credentials, memory budget (`max_qubits` ≥ 10), stake.

## 3. Task stuck `pending` / `dispatched`?

```bash
curl -s "$ORCH/api/v1/task/$TASK_ID" | jq .
# orchestrator logs filtered by task id
# economy store: HGETALL task:<TASK_ID>:meta (when Redis-backed)
```

| Clue | Likely cause |
| --- | --- |
| `failed to form quorum` | too few online nodes vs `required_votes` / security_level |
| rising `outbox_pending` | P2P deliver retry — node↔orch connectivity |
| rising `pending_tasks` | core slow/down — check core worker health |
| submit `400` | client payload / billing `client_id` |

## 4. Client cannot pay / faucet / settlement?

Public: dashboard faucet → client balance. Confirm balance key (Redis example):

```bash
redis-cli GET economy:client:<id>:balance
```

Orchestrator HTTP faucet is **removed**. Local E2E uses direct economy-store `SET` only (see [`E2E.md`](../../E2E.md) §4).

Task completed but no economics receipt, unpaid rewards, or stuck burn:

```bash
curl -s "$ORCH/api/v1/task/$TASK_ID" | jq '{status,receipt_hash,receipt_url}'
# orchestrator logs: economy.settlement, burn settled, receipt
```

## 5. Proof / consolidation failure?

Check orchestrator logs for `proof`, `Root proof`, `aggregation`, `tamper`, `signature`.

Invalid peer bids are rejected at P2P receive (signature). Root proof failures fail the task (`proof aggregation failed`). Re-run a known-good curated case from [`circuits/`](../../circuits/) via [`run_e2e.sh`](../run_e2e.sh) before deep diving.

---

More detail: [`E2E.md`](../../E2E.md), [`e2e/README.md`](../README.md).
