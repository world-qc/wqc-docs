# E2E signoff harness

Reproducible normal-path E2E plus recovery and fault drills. Target stack is defined in [`../../E2E.md`](../../E2E.md) §2 (reference E2E stack).

## Prerequisites

1. A running stack that satisfies [`E2E.md` §2](../../E2E.md#2-reference-e2e-stack).
2. For drills 03–06: set **`COMPOSE_DIR`** to the directory containing your stack’s `compose.yml`.
3. Orchestrator reachable at `ORCH_URL` (default `http://127.0.0.1:9001`).

```bash
export ORCH_URL="${ORCH_URL:-http://127.0.0.1:9001}"
export COMPOSE_DIR=/path/to/your/stack
curl -sf "$ORCH_URL/health"
```

Client credit is applied by `run_e2e.sh` (Redis key `economy:client:client-01:balance`).

## Run order

| Step | Script | What it proves |
| --- | --- | --- |
| 1 | `01_e2e_fast.sh` | Fast tier (10 cases) + manifest asserts |
| 2 | `02_e2e_all.sh` | Full suite incl. slow `multislice_28q_zz` (**required for §6**) |
| 3 | `03_node_restart.sh` | Node SQLite pending / outbox survive `docker restart` |
| 4 | `04_orch_restart.sh` | Orchestrator restart → health + bootstrap + task progress |
| 5 | `05_fault_injection.sh` | Quorum stall/recovery + tamper/proof unit evidence |
| 6 | `06_memory_budget.sh` | Multi-node `/status` memory / qubit caps |

```bash
cd examples/e2e/signoff   # from wqc-docs repo root
./run_signoff.sh                 # full §6
SKIP_SLOW=1 ./run_signoff.sh     # fast + drills only (not enough to close §6)
```

Artifacts land under `$SIGNOFF_DIR` (default `/tmp/wqc-signoff-<timestamp>`).
Commit only [`RESULT.md`](RESULT.md) (filled from [`RESULT.template.md`](RESULT.template.md)).

## Expected log markers

| Area | Marker |
| --- | --- |
| E2E pass | `PASS [case]` / runner exit 0 |
| Quorum lock | orchestrator: `quorum locked, starting scheduler` |
| Quorum agree | `quorum agreement reached` |
| Task close | `task consolidated and closed` |
| Node work | `Worker: Finished task` / `[P2P Result] Delivered` |
| Quorum stall | `failed to form quorum` or task stuck `pending` with few nodes |
| Bid tamper | unit: `expected invalid signature` (`operator` package) |

## Completion

See checklist in `RESULT.md`. Operator triage: [`TRIAGE.md`](TRIAGE.md).
