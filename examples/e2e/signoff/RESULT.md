# §6 Signoff RESULT

Filled after `./run_signoff.sh` (fast + all + drills). Drills `03` and `06` were re-run after node admin HTTP recovered from rebuild delay (see Notes).

| Field | Value |
| --- | --- |
| Date | 2026-07-14 (JST) |
| Host / operator | local Colima |
| Reference stack | [`examples/compose.yml`](../../compose.yml) / [`E2E.md`](../../E2E.md) §2 |
| Orchestrator URL | `http://localhost:9001` |
| Core image digest | `sha256:e969910473a7dab3b2400d7e6b4e1db1d46d310e2c46755c2d7937c2d8d52bb0` |
| Signoff log dir | `/tmp/wqc-signoff-20260714-210250` |
| E2E log dir(s) | `…/e2e-fast`, `…/e2e-all` under the signoff log dir |

## Checklist

| Item | Pass? | Evidence |
| --- | --- | --- |
| `TIER=fast` E2E (10/10 + asserts) | PASS | `e2e-fast` — summary `pass=10 fail=0 skip=1` |
| `TIER=all` E2E (11/11 incl. slow) | PASS | `e2e-all` — summary `pass=11 fail=0 skip=0` incl. `multislice_28q_zz` |
| Node restart (pending/outbox) | PASS | `03_node_restart`: task `019f6088-db5b-73b7-8285-a1bc7c5d7804` completed after `docker restart wqc-node-01`; `/status` `pending_tasks=0` `outbox_pending=0` |
| Orchestrator restart | PASS | `04_orch_restart`: task `019f6084-2c70-729f-97f3-976bf51c0fd8` completed; bootstrap peer `12D3KooWDmYmHPsTGDi9QNvEDURikkhWoj2wWEnSjwvQeDXmhak3` |
| Quorum fault / recovery | PASS | `05_fault_injection`: ultra task `019f6084-8e83-722c-aee5-956cfd550be8` with 1 node → final `failed`; unit tests ok |
| Invalid proof / tamper (tests or drill) | PASS | `go test` via `ORCH_SRC`: `domain/operator`, `domain/result`, `domain/bid`, `application/service` exit 0 |
| Multi-node memory budget | PASS | all five nodes `max_qubits=26` `max_memory_gib=1`; sample task `019f6089-4924-7a17-a8ef-b83f98d006a4` completed |

## Notes

- First pass of this run: `01`/`02`/`04`/`05` PASS; `03` failed when admin HTTP was not ready within 30s after `docker restart` (cargo rebuild); `06` failed because nodes 02–05 were still recovering from the quorum drill. Re-ran `03` and `06` after all five `/status` endpoints responded — both PASS.
- `03_node_restart.sh` wait loop increased to 90 attempts to tolerate rebuild latency.
- Public triage: [`TRIAGE.md`](TRIAGE.md).
