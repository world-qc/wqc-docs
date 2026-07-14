# §6 Signoff RESULT

Fill after a full `./run_signoff.sh` (or equivalent manual run). Do not commit raw `/tmp` logs.

| Field | Value |
| --- | --- |
| Date (UTC or local) | |
| Host / operator | |
| Compose | `world-qc-docker/devnet/compose.yml` |
| Orchestrator URL | `http://localhost:9001` |
| Core image digest | |
| Signoff log dir | `/tmp/wqc-signoff-…` |
| E2E log dir(s) | `/tmp/wqc-e2e-…` |

## Checklist

| Item | Pass? | Evidence |
| --- | --- | --- |
| `TIER=fast` E2E (10/10 + asserts) | | log dir / exit 0 |
| `TIER=all` E2E (11/11 incl. slow) | | log dir / exit 0 |
| Node restart (pending/outbox) | | `03_node_restart` notes |
| Orchestrator restart | | `04_orch_restart` notes |
| Quorum fault / recovery | | `05_fault_injection` notes |
| Invalid proof / tamper (tests or drill) | | unit test output path |
| Multi-node memory budget | | `06_memory_budget` `/status` snapshots |

## Notes

(optional: failures, skips, follow-ups)
