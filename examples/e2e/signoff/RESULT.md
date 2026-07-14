# §6 Signoff RESULT

Filled after `./run_signoff.sh` drills + re-run of `01`/`02` with corrected client credit (28q escrow).

| Field | Value |
| --- | --- |
| Date | 2026-07-13 (JST) |
| Host / operator | local Colima / Auto |
| Reference stack | `examples/E2E.md` §2 (internal devnet checkout) |
| Orchestrator URL | `http://localhost:9001` |
| Core image digest | `sha256:e969910473a7dab3b2400d7e6b4e1db1d46d310e2c46755c2d7937c2d8d52bb0` |
| Signoff log dir (drills) | `/tmp/wqc-signoff-20260713-150932` |
| E2E log dir (fast+all PASS) | `/tmp/wqc-signoff-e2e-20260713-151242` |

## Checklist

| Item | Pass? | Evidence |
| --- | --- | --- |
| `TIER=fast` E2E (9/9 + asserts) | PASS | `/tmp/wqc-signoff-e2e-20260713-151242/e2e-fast` — summary `pass=9 fail=0` |
| `TIER=all` E2E (incl. slow) | PASS | `/tmp/wqc-signoff-e2e-20260713-151242/e2e-all` — `pass=10 fail=0` incl. `multislice_28q_zz` |
| Node restart (pending/outbox) | PASS | `03_node_restart`: task `019f5a19-4162-7b7b-b3ad-94568661d583` completed after `docker restart wqc-node-01`; `/status` `pending_tasks=0` `outbox_pending=0` |
| Orchestrator restart | PASS | `04_orch_restart`: task `019f5a19-7990-7960-9f4b-f026bbc3b6a7` completed; bootstrap peer `12D3KooWDmYmHPsTGDi9QNvEDURikkhWoj2wWEnSjwvQeDXmhak3` |
| Quorum fault / recovery | PASS | `05_fault_injection`: ultra task `019f5a19-c7ac-75f3-9ea7-518c739f5b5d` with 1 node → orch `failed to form quorum: got 1 bids, need 5 for required_votes=3` → final `failed` after node restore |
| Invalid proof / tamper (tests) | PASS | `go test` ok: `domain/operator` (bad bid sig), `domain/result` (consensus mismatch), `domain/bid`, `application/service`; notes cite `VerifyRootProof` + P2P signature reject |
| Multi-node memory budget | PASS | all five nodes `max_qubits=26` `max_memory_gib=1`; sample task completed |

## Notes

- First full `run_signoff` failed fast/all on 28q submit (`402 insufficient client balance`); default `CLIENT_CREDIT_PWQC` raised to `1e20` in `run_e2e.sh` / signoff `lib.sh`.
- `run_e2e.sh` also fixed `AMOUNT_PWQC` unbound-variable typo (`set -u`).
- Node admin HTTP has no `curl` in image; signoff uses `docker run --network container:… curlimages/curl`.
- Public triage: [`TRIAGE.md`](TRIAGE.md).
