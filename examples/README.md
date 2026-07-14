# WQC examples

Reference submit payloads and the **E2E harness** for regression against a WQC orchestrator stack.

**Full guide:** [`E2E.md`](E2E.md) — reference stack definition, manual submit, automated runner, signoff, and triage.

## Layout

| Path | Role |
|------|------|
| [`circuits/`](circuits/) | **SSOT** — all curated submit JSON (tutorial + regression) |
| [`e2e/`](e2e/) | Runner: `manifest.tsv`, `run_e2e.sh`, `assert_manifest.sh`, `signoff/` |
| [`E2E.md`](E2E.md) | Human-facing E2E documentation |

Topic folders `basis/`, `slice/`, and `phase_c/` were merged into `circuits/` (see [`circuits/README.md`](circuits/README.md)).

## Quick run

From the **`wqc-docs` repository root** (with a stack satisfying [`E2E.md` §2](E2E.md#2-reference-e2e-stack)):

```bash
export ORCH_URL="${ORCH_URL:-http://127.0.0.1:9001}"

# fast suite (~30s) — 10 cases + golden manifest checks
TIER=fast ./examples/e2e/run_e2e.sh

# include 28q OP1 expectation (~5 min)
TIER=all ./examples/e2e/run_e2e.sh
```

Manual submit of a circuit:

```bash
curl -s -X POST "$ORCH_URL/api/v1/submit" \
  -H "Content-Type: application/json" \
  -d @examples/circuits/sample/sample_bell_counts.json | jq .
```
