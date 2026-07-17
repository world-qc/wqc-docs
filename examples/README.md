# WQC examples

Reference submit payloads and the **E2E harness** for regression against a WQC orchestrator stack.

**Full guide:** [`E2E.md`](E2E.md) — reference stack definition, manual submit, automated runner, signoff, and triage.

**Compose prerequisite:** [`compose.yml`](compose.yml) builds from sibling monorepo checkouts (`wqc-core`, `wqc-node`, `wqc-orchestrator`, `wqc-p2p-proxy`, `wqc-stark-engine`). A standalone clone of `wqc-docs` alone cannot build those images — use the monorepo layout, or pre-built images that satisfy the [reference E2E stack](E2E.md#2-reference-e2e-stack).

## Layout

| Path | Role |
|------|------|
| [`E2E.md`](E2E.md) | Human-facing E2E guide (reference stack + [`compose.yml`](compose.yml)) |
| [`circuits/`](circuits/) | **SSOT** — all curated submit JSON (tutorial + regression) |
| [`e2e/`](e2e/) | Runner: `manifest.tsv`, `run_e2e.sh`, `assert_manifest.sh`, `signoff/` |
| [`compose.yml`](compose.yml) | Sample Docker Compose for the reference E2E stack |
| [`scripts/redis-reseed-operator-pubkeys.sh`](scripts/redis-reseed-operator-pubkeys.sh) | Register operator pubkeys in Redis after stack start |

Topic folders `basis/`, `slice/`, and `phase_c/` were merged into `circuits/` (see [`circuits/README.md`](circuits/README.md)).

## Quick run

From the **`wqc-docs` repository root** (start the stack with [`compose.yml`](compose.yml) — see [`E2E.md` §2](E2E.md#sample-docker-compose)):

```bash
cp examples/.env.example examples/.env   # Ed25519 secrets — see E2E.md
docker compose -f examples/compose.yml up -d
./examples/scripts/redis-reseed-operator-pubkeys.sh
export ORCH_URL="${ORCH_URL:-http://127.0.0.1:9001}"
export COMPOSE_DIR="${COMPOSE_DIR:-$PWD/examples}"

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
