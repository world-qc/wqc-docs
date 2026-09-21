# §6 Signoff RESULT

Filled after `./run_signoff.sh` (fast + all + drills) on the **composer-required**
devnet stack (`wqc-composer-01` healthy). Drill `06` was re-run after
`wqc-node-04` admin HTTP recovered from the quorum drill (see Notes).

| Field | Value |
| --- | --- |
| Date | 2026-09-21 (JST) |
| Host / operator | local Colima |
| Reference stack | [`world-qc-docker/devnet`](../../../../world-qc-docker/devnet) (composer + orch + 5 nodes); curated circuits from [`examples/`](../../) / [`E2E.md`](../../E2E.md) §2 |
| Orchestrator URL | `http://localhost:9001` |
| Composer health | `http://127.0.0.1:9101/health` → `ok composer_id=composer-01` |
| Core image digest | `sha256:0df2d6f9ac09fd9e3209b7abd08ee75fb923f4c9795a3899a35fabfd746afb1b` |
| Signoff log dir | `/tmp/wqc-signoff-20260921-153528` |
| E2E log dir(s) | `…/e2e-fast`, `…/e2e-all` under the signoff log dir |

## Checklist

| Item | Pass? | Evidence |
| --- | --- | --- |
| `TIER=fast` E2E (10/10 + asserts) | PASS | `e2e-fast` — summary `pass=10 fail=0 skip=1` (incl. mid-circuit IF) |
| `TIER=all` E2E (11/11 incl. slow) | PASS | `e2e-all` — summary `pass=11 fail=0 skip=0` incl. `multislice_28q_zz` |
| Node restart (pending/outbox) | PASS | `03_node_restart`: task `01a0c2af-c707-7904-bafc-177ef9031885` completed; `pending_after=0` `outbox_after=0` |
| Orchestrator restart | PASS | `04_orch_restart`: post-submit `01a0c2b4-b1b3-76b1-aa0d-ef804747fcc9` completed; bootstrap peer `12D3KooWDmYmHPsTGDi9QNvEDURikkhWoj2wWEnSjwvQeDXmhak3` |
| Quorum fault / recovery | PASS | `05_fault_injection`: ultra task `01a0c2b4-fb7a-7986-a8f9-d8ae2dcb6cfb` → final `failed`; unit tests via `ORCH_SRC` |
| Invalid proof / tamper (tests or drill) | PASS | `go test` evidence under `05_fault_injection/unit_tamper.txt` |
| Multi-node memory budget | PASS | all five nodes `max_qubits=27` `max_memory_gib=2`; sample task `01a0c2b7-427f-7bc4-9a9e-b899ad071ead` completed |

## Notes

- First pass of this run: `01`/`02`/`03`/`04`/`05` PASS; `06` failed when `wqc-node-04` admin HTTP was unreachable after the quorum drill. Restarted `wqc-node-04`, re-ran `06` — PASS.
- Manifest fetch on the host uses container `mc cat` with MinIO credentials (`run_e2e.sh`); rewriting a presigned URL hostname alone yields `SignatureDoesNotMatch`.
- Mid-circuit leaf RecAgg required a stark-engine wire fix: leaf `fri_chal_mmcs` decode used AggregationAir’s commit-round ceiling (4); shot-sampling FRI can exceed it — raised to `LEAF_FRI_MAX_ROUNDS` and rebuilt core / orch verifier / composer lockstep.
