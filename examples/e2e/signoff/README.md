# §6 E2E signoff harness (devnet)

Reproducible normal-path E2E + recovery/fault drills for `PUBLIC_TESTNET_TASKS` §6.
Target stack: [`world-qc-docker/devnet/compose.yml`](../../../../world-qc-docker/devnet/compose.yml).

## Prerequisites

```bash
cd world-qc-docker/devnet
docker compose up -d
curl -sf http://localhost:9001/health
```

Client credit is applied by `run_e2e.sh` (Redis `economy:client:me:balance`).

## Run order

| Step | Script | What it proves |
| --- | --- | --- |
| 1 | `01_e2e_fast.sh` | Fast tier (9 cases) + manifest asserts |
| 2 | `02_e2e_all.sh` | Full suite incl. slow `multislice_28q_zz` (**required for §6**) |
| 3 | `03_node_restart.sh` | Node SQLite pending / outbox survive `docker restart` |
| 4 | `04_orch_restart.sh` | Orchestrator restart → health + bootstrap + task progress |
| 5 | `05_fault_injection.sh` | Quorum stall/recovery + tamper/proof unit evidence |
| 6 | `06_memory_budget.sh` | Multi-node `/status` memory / qubit caps |

Orchestrator:

```bash
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

See checklist in `RESULT.md` and `PUBLIC_TESTNET_TASKS.md` §6.
Triage after public launch: [`TRIAGE.md`](TRIAGE.md).
