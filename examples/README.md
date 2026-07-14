# WQC examples

Reference submit payloads and the local **devnet E2E** harness.

## Layout

| Path | Role |
|------|------|
| [`circuits/`](circuits/) | **SSOT** — all curated submit JSON (tutorial + regression) |
| [`e2e/`](e2e/) | Runner: `manifest.tsv`, `run_e2e.sh`, `assert_manifest.sh`, `signoff/` |

Topic folders `basis/`, `slice/`, and `phase_c/` were merged into `circuits/` (see redirect notes in [`circuits/README.md`](circuits/README.md)).

## Quick run

```bash
# fast suite (~30s) — 10 cases + golden manifest checks
TIER=fast wqc-docs/examples/e2e/run_e2e.sh

# include 28q OP1 expectation (~5 min)
TIER=all wqc-docs/examples/e2e/run_e2e.sh

# from repo root
scripts/devnet-smoke.sh
```

Manual submit of a circuit:

```bash
curl -s -X POST http://localhost:9001/api/v1/submit \
  -H "Content-Type: application/json" \
  -d @wqc-docs/examples/circuits/sample/sample_bell_counts.json | jq .
```

See [`AGENT_E2E.md`](../../AGENT_E2E.md) for orchestrator/Redis setup and signoff.
