# WQC end-to-end testing

Human-facing guide for manual submits, the curated regression harness, and signoff drills.
Submit payloads live in [`circuits/`](circuits/); runners in [`e2e/`](e2e/).

This document defines a **reference E2E stack** (logical services and URLs). Bring up a stack that satisfies §2 — including the bundled [`compose.yml`](compose.yml) sample — then run the scripts from this repository.

**Images:** the sample compose file builds from sibling repos checked out under one parent directory (`../../wqc-core`, `../../wqc-node`, …). Cloning only `wqc-docs` is not enough to `docker compose up` unless you already have equivalent images and retarget the compose file.

## 1. Purpose and scope

| Suite | Cases | Runtime (typical) | What it proves |
| --- | --- | --- | --- |
| `TIER=fast` | 10 | ~30–60 s | Scalar, counts, expectation, multislice, Phase C mid-circuit / noise, TN cut, X/Y basis |
| `TIER=all` | 11 | + slow OP1 | Adds `multislice_28q_zz` (28q ZZ expectation, minutes) |
| Signoff drills | E2E + 5 recovery/fault scripts | varies | §6-style rehearsal: restart, quorum stall, memory budget |

Public testnet differs only in DNS, TLS, and faucet UI — the orchestrator API and manifest shape are the same.

## 2. Reference E2E stack

Minimum logical layout for the harness in this repo:

| Component | Required capability | Default / example |
| --- | --- | --- |
| **Orchestrator HTTP** | `GET /health`, `POST /api/v1/submit`, `GET /api/v1/task/{id}`, `GET /api/v1/p2p/bootstrap` | `ORCH_URL=http://127.0.0.1:9001` |
| **Economy store** | Redis (or equivalent) key `economy:client:{client_id}:balance` | `REDIS_HOST=127.0.0.1`, `REDIS_PORT=6379` or `REDIS_URL` |
| **Object store** | S3-compatible bucket for manifests and proofs; presigned GET URLs on completed tasks | Host rewrite: internal hostname → reachable host (see §4) |
| **Worker swarm** | ≥ **5** nodes online for full signoff; ≥ **3** for `security_level=ultra` quorum drills | P2P bootstrap from orchestrator |
| **Core workers** | One compute container/process per bid-capable node | Image tag recorded in E2E logs |

### Sample Docker Compose

A minimal reference stack matching the container names and ports assumed by the E2E scripts is bundled as [`compose.yml`](compose.yml).

| Service | Role |
| --- | --- |
| `wqc-redis` | Economy store (`6379`) |
| `wqc-s3-storage` | Object store / MinIO (`9000`, console `9090`) |
| `wqc-orchestrator-01` | Orchestrator HTTP (`9001` → container `:9000`) |
| `wqc-p2p-proxy-01` | P2P hub (`4001` tcp/udp) |
| `wqc-core-01` … `wqc-core-05` | Compute workers (shared UDS volume) |
| `wqc-node-01` … `wqc-node-05` | Worker nodes (5 required for full signoff) |

**Layout requirement:** `compose.yml` expects `wqc-docs` alongside separate checkouts of sibling repos (`wqc-core`, `wqc-node`, `wqc-orchestrator`, `wqc-p2p-proxy`, `wqc-stark-engine`) under one parent directory. See the header comment in [`compose.yml`](compose.yml).

**Secrets:** [`compose.yml`](compose.yml) does not embed credentials. Copy [`.env.example`](.env.example) to `examples/.env`, then fill values before starting the stack.

**Ed25519 keys (orchestrator + nodes):** use [wqc-keygen](https://github.com/world-qc/wqc-keygen) — the shared utility for `wqc-node` and `wqc-orchestrator` identity. It prints a base64 private seed and the matching public key in one step.

```bash
# Docker (no local Rust required)
docker build -t wqc-keygen https://github.com/world-qc/wqc-keygen.git
docker run --rm wqc-keygen generate

# Or from a checkout
cargo run -- generate

# Re-derive public key from an existing private seed
docker run --rm wqc-keygen from-private "<PRIVATE_KEY>"
```

| `.env` variable | How many | Notes |
| --- | --- | --- |
| `WQC_ORCHESTRATOR_PRIVATE_KEY` | 1 | **Same** value on orchestrator and p2p-proxy |
| `WQC_NODE_01_PRIVATE_KEY` … `05` | 5 | One `generate` run per node |
| `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` | 1 | Object-store credentials (any strong local values) |

**Operator keys (`WQC_TESTNET_NODE_KEY`):** not in `.env`. The sample [`compose.yml`](compose.yml) uses fixed local identifiers `nk_e2e-node-01` … `05`. These are **not** dashboard-issued keys — any unique non-empty string would work; derivation is HKDF over the raw bytes (`wqc-operator-v1`). The `nk_` prefix is convention only.

After the stack is up, register matching operator **public** keys in Redis (required for bids):

```bash
chmod +x examples/scripts/redis-reseed-operator-pubkeys.sh
./examples/scripts/redis-reseed-operator-pubkeys.sh
```

Re-run after a Redis flush. See [`scripts/redis-reseed-operator-pubkeys.sh`](scripts/redis-reseed-operator-pubkeys.sh).

Do not commit `examples/.env`.

**Start (from `wqc-docs` repo root):**

```bash
cp examples/.env.example examples/.env   # edit — do not commit .env
docker compose -f examples/compose.yml up -d
./examples/scripts/redis-reseed-operator-pubkeys.sh
curl -sf http://127.0.0.1:9001/health
export ORCH_URL=http://127.0.0.1:9001
export COMPOSE_DIR="$PWD/examples"
TIER=fast ./examples/e2e/run_e2e.sh
```

Omitted from the sample (not required for examples E2E): reverse proxy, dashboards, testnet UI, Prometheus/Grafana.

### Billing and quorum

| Setting | Reference value |
| --- | --- |
| Client billing | **enabled** — every submit needs `"client_id"` |
| Example client | `client-01` (override with `CLIENT_ID`) |
| Client credit (E2E) | Set balance before batch runs (see §4) — default `1e20` pWQC via `CLIENT_CREDIT_PWQC` |
| P2P bootstrap (in-cluster) | `http://<orchestrator-host>:9000/api/v1/p2p/bootstrap` |

### Health check

```bash
curl -sf "$ORCH_URL/health"
curl -sf "$ORCH_URL/api/v1/p2p/bootstrap" | jq '{peer_id, multiaddrs}'
```

### Docker naming overrides (optional)

Scripts assume conventional container names when `docker` is available. Override if your stack uses different names:

| Variable | Default | Used by |
| --- | --- | --- |
| `REDIS_CONTAINER` | `wqc-redis` | `run_e2e.sh`, signoff credit |
| `NODE_CONTAINER` | `wqc-node-01` | `03_node_restart.sh` |
| `ORCH_CONTAINER` | `wqc-orchestrator-01` | `04_orch_restart.sh`, failure logs |
| Object store admin | `wqc-s3-storage` | manifest fallback via `mc cat` |

Signoff drills that **stop/start** services use Docker Compose:

| Variable | Meaning |
| --- | --- |
| `COMPOSE_DIR` | Directory containing [`compose.yml`](compose.yml) (default: `examples/` in this repo when present) |

## 3. Prerequisites

Tools:

- `curl`, `jq`
- `redis-cli` **or** Docker access to the economy Redis container
- For signoff drills 03–06: `docker`, [`compose.yml`](compose.yml) (set `COMPOSE_DIR` if not using the default)

From a clone of **this repository** (`wqc-docs`):

```bash
chmod +x examples/e2e/run_e2e.sh examples/e2e/assert_manifest.sh
chmod +x examples/e2e/signoff/*.sh
```

## 4. Manual flow

### Submit

```http
POST /api/v1/submit
Content-Type: application/json
```

| Field | Notes |
| --- | --- |
| `client_id` | Required when billing is on |
| `qubit_count` | Global register width |
| `security_level` | `"low"` \| `"normal"` \| `"high"` \| `"ultra"` → `required_votes` **and** FRI `num_queries` (8/16/32/40) for unitary / Born / trajectory / compose outer STARKs and PCS cert slots (see [zk-STARK.md §5.1](../spec/zk-STARK.md#51-securitylevel--fri-query-ladder)). Nested FriFold/DeepRo/Mmcs internals stay at 40. |
| `circuit` | Gate list (`type` + `params`) |
| `output_mode` | Omit → `statevector_scalar`. Also `sample_counts`, `expectation` |
| `shots` | Required for `sample_counts` |
| `classical_bit_count` | Required when circuit has `MEASURE` |
| `observables` | Required for `expectation` |

`sample_seed` is **orchestrator-generated** (not client-supplied).

Example (from repo root):

```bash
export ORCH_URL="${ORCH_URL:-http://127.0.0.1:9001}"
curl -s -X POST "$ORCH_URL/api/v1/submit" \
  -H 'Content-Type: application/json' \
  -d @examples/circuits/sample/sample_bell_counts.json | jq .
```

### Client credit

Before batch E2E, fund the client balance:

```bash
# Via redis-cli (adjust host/port or use REDIS_URL)
redis-cli SET economy:client:client-01:balance 100000000000000000000
redis-cli GET economy:client:client-01:balance

# Or via Docker when REDIS_CONTAINER is running
docker exec wqc-redis redis-cli SET economy:client:client-01:balance 100000000000000000000
```

The automated runner applies the same key before cases (see §6).

### Poll task status

```bash
TASK_ID=019f…
curl -s "$ORCH_URL/api/v1/task/$TASK_ID" | jq .
```

| `status` | Meaning |
| --- | --- |
| `pending` | Bidding / not yet dispatched |
| `dispatched` | Slices in flight |
| `finalizing` | All slice quorums done; PCS wait (majority nomination → optional CAS open call → orch fallback) / compose / manifest seal (`phase`: `waiting_pcs` → `composing_proofs` → `sealing_manifest`) |
| `completed` | Manifest + `proof_root_hash` available |
| `failed` | See `error` field |

### Manifest inspection

Presigned URLs may use an **internal hostname** (e.g. `wqc-s3-storage:9000`). Rewrite to a host-reachable endpoint:

```bash
URL=$(curl -s "$ORCH_URL/api/v1/task/$TASK_ID" | jq -r .manifest_url)
HOST_URL="${URL//wqc-s3-storage:9000/127.0.0.1:9000}"
curl -s "$HOST_URL" | jq .
```

If object-store admin tools are available in your stack:

```bash
docker exec wqc-s3-storage mc cat "local/wqc-results/manifests/${TASK_ID}.json" | jq .
```

Expect `result_type`, `sample_result` / `expectation_result`, `slices`, `root_hash`, and for counts tasks dominant bitstrings (e.g. Bell → `"00"` and `"11"`).

Phase C meta (optional): `measurement_spec_hash`, `noise_model` in orchestrator task meta for applicable submits.

## 5. Curated circuits and manifest

| Path | Role |
| --- | --- |
| [`circuits/`](circuits/) | **SSOT** — all submit JSON |
| [`e2e/manifest.tsv`](e2e/manifest.tsv) | Case registry (`name`, path, timeout, tier) |
| [`e2e/assert_manifest.sh`](e2e/assert_manifest.sh) | Per-case golden checks after `completed` |

| Tier | Cases |
| --- | --- |
| `fast` (10) | scalar, bell counts, expectation, multislice 4q, mid-circuit IF, multislice mid-circuit IF, noise, tn_cut 28q, x_basis, y_basis |
| `slow` | `multislice_28q_zz` (OP1, ~minutes) |

See [`circuits/README.md`](circuits/README.md) for file layout and shot conventions (`512` for regression counts, `1024` for deterministic X/Y basis).

## 6. Automated runner

From **`wqc-docs` repository root**:

```bash
export ORCH_URL="${ORCH_URL:-http://127.0.0.1:9001}"

# Fast tier (10 cases + manifest golden checks)
TIER=fast ./examples/e2e/run_e2e.sh

# Full suite including slow 28q expectation (11 cases)
TIER=all ./examples/e2e/run_e2e.sh
```

Environment overrides:

| Variable | Default | Purpose |
| --- | --- | --- |
| `ORCH_URL` | `http://localhost:9001` | Orchestrator base URL |
| `CLIENT_ID` | `client-01` | Billing client |
| `TIER` | `fast` | `fast`, `all`, or a single tier name from manifest |
| `POLL_SECS` | `3` | Poll interval |
| `LOG_DIR` | `/tmp/wqc-e2e-<timestamp>` | Per-case artifacts |
| `CLIENT_CREDIT_PWQC` | `100000000000000000000` | Pre-run balance SET |
| `REDIS_CONTAINER` | `wqc-redis` | Docker Redis for credit |
| `REDIS_HOST` / `REDIS_PORT` / `REDIS_URL` | `127.0.0.1:6379` | Direct redis-cli path |

Logs per case: `$LOG_DIR/<case>_submit.json`, `_poll.jsonl`, `_manifest.json`, `_orch.log` (on failure), plus `$LOG_DIR/core_image.txt` when Docker is available.

Exit code **0** = all selected cases reached `completed` **and** passed manifest assertions.

## 7. Signoff drills

Harness: [`e2e/signoff/`](e2e/signoff/) — reproducible E2E plus recovery and fault exercises.

**Prerequisites:** §2 reference stack running; [`compose.yml`](compose.yml) for drills that restart or stop containers.

```bash
export ORCH_URL="${ORCH_URL:-http://127.0.0.1:9001}"
export COMPOSE_DIR="${COMPOSE_DIR:-$PWD/examples}"   # wqc-docs repo root

docker compose -f "$COMPOSE_DIR/compose.yml" up -d
curl -sf "$ORCH_URL/health"

cd examples/e2e/signoff
./run_signoff.sh                 # fast + all + drills
SKIP_SLOW=1 ./run_signoff.sh     # fast + drills only (does not close full §6 checklist)
```

| Step | Script | What it proves |
| --- | --- | --- |
| 1 | `01_e2e_fast.sh` | Fast tier (10 cases) + manifest asserts |
| 2 | `02_e2e_all.sh` | Full suite incl. slow `multislice_28q_zz` |
| 3 | `03_node_restart.sh` | Node pending / outbox survive restart |
| 4 | `04_orch_restart.sh` | Orchestrator restart → health + bootstrap + task progress |
| 5 | `05_fault_injection.sh` | Quorum stall/recovery; optional orchestrator unit tests |
| 6 | `06_memory_budget.sh` | Multi-node `/status` memory / qubit caps |

Drill-specific variables:

| Variable | Purpose |
| --- | --- |
| `COMPOSE_DIR` | Directory with [`compose.yml`](compose.yml); default `examples/` when running from this repo |
| `ORCH_SRC` | Optional path to `wqc-orchestrator` checkout for `go test` in drill 05 |
| `SIGNOFF_DIR` | Artifact root (default `/tmp/wqc-signoff-<timestamp>`) |

Record results in [`e2e/signoff/RESULT.md`](e2e/signoff/RESULT.md) (from [`RESULT.template.md`](e2e/signoff/RESULT.template.md)). Operator triage after public launch: [`e2e/signoff/TRIAGE.md`](e2e/signoff/TRIAGE.md).

### Expected log markers

| Area | Marker |
| --- | --- |
| E2E pass | `PASS [case]` / runner exit 0 |
| Quorum lock | orchestrator: `quorum locked, starting scheduler` |
| Quorum agree | `quorum agreement reached` |
| Task close | `task consolidated and closed` |
| Node work | `Worker: Finished task` / `[P2P Result] Delivered` |
| Quorum stall | `failed to form quorum` or task stuck `pending` with few nodes |
| TN cut (`tn_cut_scalar_28q`) | slicing log shows `edge_id=e_2` first (idle wire), not `e_0` |

## 8. Failure diagnosis

| Symptom | First check |
| --- | --- |
| submit `400` | `client_id`, `classical_bit_count`, `output_mode` in payload |
| `status=failed` / `Compute failure` | worker logs; core image stale? |
| `air_sum != 0` | rebuild all core workers; trace fold for `H,H` / `RX(±π/2)` |
| TN cut picks `edge_id=e_0` first | orchestrator still on old binary — restart or fix compile |
| manifest URL 404 from host | rewrite internal object-store hostname or use admin `mc cat` |
| `ASSERT [...] manifest` failed | task completed but wrong physics — see `assert_manifest.sh` |
| stuck `pending` | orchestrator logs; economy balance; quorum / node count |
| node restart mid-task | worker `/status` → `pending_tasks` / `outbox_pending`; drill `03_node_restart.sh` |
| orch restart mid-task | health + `/api/v1/p2p/bootstrap`; drill `04_orch_restart.sh` |
| quorum stall (`ultra`) | too few nodes online — drill `05_fault_injection.sh` |
| proof / bid tamper | orchestrator rejects bad signatures; root verify fails task |

### Known pitfalls

1. **Missing `client_id`** → submit 400 when billing enabled.
2. **Presigned manifest URL** uses in-cluster DNS — rewrite hostname or fetch via object-store admin.
3. **Orchestrator hot-reload** may leave an old binary after compile errors — verify TN cut log or restart orchestrator.
4. **28q scalar** produces **4 slices** — allow ~180 s timeout in manifest.

## 9. Last verified

Update this section when re-running against your reference stack.

| Field | Value |
| --- | --- |
| Date | 2026-07-14 |
| `TIER=fast` | 10/10 `completed` + manifest assertions |
| `TIER=all` | 11/11 incl. slow `multislice_28q_zz` |
| Signoff | [`e2e/signoff/RESULT.md`](e2e/signoff/RESULT.md) — drills PASS (logs `/tmp/wqc-signoff-20260714-210250`) |
| Core image | `sha256:e969910473a7dab3b2400d7e6b4e1db1d46d310e2c46755c2d7937c2d8d52bb0` |
