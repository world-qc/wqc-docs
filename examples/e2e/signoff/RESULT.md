# §6 Signoff RESULT

Filled after `./run_signoff.sh` (fast + all + drills) on the **composer-required**
devnet stack (`wqc-composer-01` healthy), in one pass with no re-runs. This run re-signs
off the stack after the v2 state-vector leaves (`sv_stark_v2`) and work budgets; the
previous signoff was 2026-09-21.

| Field | Value |
| --- | --- |
| Date | 2026-11-18 (UTC 05:51–05:56) |
| Host / operator | local Docker Desktop (Apple silicon) |
| Reference stack | private devnet configuration (composer + orch + 5 nodes, Redis economy); curated circuits from [`examples/`](../../) / [`E2E.md`](../../E2E.md) §2 |
| Code | wqc-core `d6701fa`, wqc-node `1aae70b`, wqc-orchestrator `ea4b9fd`, wqc-composer `ac9e898`, wqc-stark-engine `a7630aa`, wqc-p2p-proxy `59d7258` (each `main`) |
| Orchestrator URL | `http://127.0.0.1:9001` |
| Composer health | `ok composer_id=composer-01` |
| Core image digest | `sha256:745cf54334ab41c1ce9fd327b7af6a3ac1383d03cac96acc1e6ce4740bfed597` |
| Signoff log dir | `…/signoff-20261118` (local, not committed) |
| E2E log dir(s) | `…/e2e-fast`, `…/e2e-all` under the signoff log dir |

## Checklist

| Item | Pass? | Evidence |
| --- | --- | --- |
| `TIER=fast` E2E (10/10 + asserts) | PASS | `e2e-fast` — summary `pass=10 fail=0 skip=1` (incl. mid-circuit IF, noise, X/Y basis, 28q TN cut) |
| `TIER=all` E2E (11/11 incl. slow) | PASS | `e2e-all` — summary `pass=11 fail=0 skip=0` incl. `multislice_28q_zz` |
| Node restart (pending/outbox) | PASS | `03_node_restart`: task `01a1ed39-25ba-7829-9f15-6fb1cb64fb96` completed; `pending_after=0` `outbox_after=0` |
| Orchestrator restart | PASS | `04_orch_restart`: task `01a1ed39-5e1f-78c8-9ddf-e2d0d5246c34` submitted 1 s before the restart → `failed` by the startup stale cleanup, without slash (defined behaviour, see Notes); health and bootstrap peer `12D3KooWDmYmHPsTGDi9QNvEDURikkhWoj2wWEnSjwvQeDXmhak3` back |
| Quorum fault / recovery | PASS | `05_fault_injection`: three nodes stopped → task `01a1ed39-b17c-7592-8d76-eea56b6b8e0f` final `failed`; nodes restored |
| Invalid proof / tamper (tests or drill) | PASS | `05_fault_injection/unit_tamper.txt` — `go test` exit 0 (bid signature mismatch, expectation consensus key mismatch, aggregator quorum trigger) |
| Multi-node memory budget | PASS | all five nodes `max_qubits=27` `max_memory_gib=2`, `pending_tasks=0`; sample task `01a1ed3a-50f0-7d11-bac0-cdccf1b1bcf3` completed |

## Notes

- Leaf schemes during the run (orchestrator log): 14 compose jobs with `scheme=sv_stark_v2`, 7 tasks dispatched as v1 ("task has no v2 leaf"). Both paths are exercised.
- `04_orch_restart`: in 2026-09-21 the task finished before the restart; here it was still in flight when the restart came, 1 s after the submit. The orchestrator's startup drain (`stale cleanup: drained active subtasks without slash`) failed it without slashing, which the script accepts as defined behaviour.
- The whole run took about 4.5 minutes.
- The orchestrator's verifier library was rebuilt from wqc-stark-engine `main` (arm64) before the run, so the orchestrator and the composer ran the same stark-engine.
