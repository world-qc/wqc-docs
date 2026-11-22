# §6 Signoff RESULT

Filled after `./run_signoff.sh` (fast + all + drills) on the **composer-required**
devnet stack (`wqc-composer-01` healthy), in one pass with no re-runs. This run re-signs
off the stack after several changes:

- wide v2 leaves of up to 20 qubits (capability bit 9),
- v2 leaves for tasks declared above 16 qubits that touch fewer wires,
- v1 slicing that fixes only idle wires,
- E2E checks that can now fail and compare values (12 fast cases, 13 in all).

The previous signoff was 2026-11-18.

| Field | Value |
| --- | --- |
| Date | 2026-11-22 (UTC 14:43–14:48) |
| Host / operator | local colima (Apple silicon, aarch64 VM, 4 CPU, 24 GiB) |
| Reference stack | private devnet configuration (composer + orch + 5 nodes, Redis economy); curated circuits from [`examples/`](../../) / [`E2E.md`](../../E2E.md) §2 |
| Code | wqc-core `303ecd4`, wqc-node `da0d2ec`, wqc-orchestrator `c306dfe`, wqc-composer `17e1046`, wqc-stark-engine `2dafce2`, wqc-p2p-proxy `59d7258` (each `main`) |
| Orchestrator URL | `http://127.0.0.1:9001` |
| Composer health | Docker healthcheck `healthy` |
| Core image digest | `sha256:658a8233369f5501c47850faa351d2e6a2cce3d80bf1fee2b7a57545b73d4267` |
| Signoff log dir | `…/signoff-20261122` (local, not committed) |
| E2E log dir(s) | `…/e2e-fast`, `…/e2e-all` under the signoff log dir |

## Checklist

| Item | Pass? | Evidence |
| --- | --- | --- |
| `TIER=fast` E2E (12/12 + asserts) | PASS | `e2e-fast`: summary `pass=12 fail=0 skip=1`. Includes mid-circuit IF, noise, X/Y basis, 28q TN cut, and the unmeasured / unobserved wire cases. |
| `TIER=all` E2E (13/13 incl. slow) | PASS | `e2e-all`: summary `pass=13 fail=0 skip=0`, including `multislice_28q_zz`. |
| Node restart (pending/outbox) | PASS | `03_node_restart`: task `01a203b9-5cdf-76cf-a37c-7208755ae2e2` completed; `pending_after=0`, `outbox_after=0`. |
| Orchestrator restart | PASS | `04_orch_restart`: task `01a203b9-965c-70b9-b532-148b0dc5f85d` was in flight at the restart and ended `failed` through the startup stale cleanup, without slash (defined behaviour). Health and bootstrap peer `12D3KooWDmYmHPsTGDi9QNvEDURikkhWoj2wWEnSjwvQeDXmhak3` came back. |
| Quorum fault / recovery | PASS | `05_fault_injection`: four nodes stopped (`wqc-node-02`–`05`); ultra task `01a203b9-ecd2-7100-a5c4-527ca24f67b0` (required_votes = 3) ended `failed`; nodes restored. |
| Invalid proof / tamper (tests or drill) | PASS | `05_fault_injection/unit_tamper.txt`: `go test` exit 0 (bid signature mismatch, expectation consensus key mismatch, aggregator quorum trigger). |
| Multi-node memory budget | PASS | All five nodes report `max_qubits=27`, `max_memory_gib=2`, `pending_tasks=0`; sample task `01a203ba-9148-7f34-86aa-dffce0d42233` completed. |

## Notes

- Leaf schemes during the run (orchestrator log): 17 compose jobs with `scheme=sv_stark_v2`, 10 with the v1 scheme, and 8 tasks dispatched as v1 ("task has no v2 leaf"). Both paths are exercised.
- Every check in `assert_manifest.sh` can now fail a case (wqc-docs #79). Before, a bare `jq -e` that failed was ignored.
- The core and composer images were rebuilt from the `main` commits above before the run, and the nodes rebuilt from the `wqc-node` checkout at `main`. The orchestrator's verifier library (`dist/libwqc_stark_verifier.so`, linux arm64) was rebuilt from wqc-stark-engine `main`. It was byte-identical to the one in place.
- The whole run took about 5 minutes.
