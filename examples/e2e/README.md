# Devnet E2E harness

Curated **runners** for the local docker devnet. Submit payloads live under [`../circuits/`](../circuits/) and are listed in `manifest.tsv`. See [`AGENT_E2E.md`](../../../AGENT_E2E.md).

## Layout

| File | Role |
| --- | --- |
| `manifest.tsv` | Case registry (`name`, path under `circuits/`, timeout, tier) |
| `run_e2e.sh` | Submit → poll → download task → golden assert |
| `assert_manifest.sh` | Per-case slice golden checks |
| `signoff/` | Public-testnet style signoff drills |

## Cases (see `manifest.tsv`)

| name | Mode | What it exercises |
| --- | --- | --- |
| `scalar_h2_amplitude` | `statevector_scalar` | 2q Bell, single slice |
| `sample_bell_counts` | `sample_counts` | Bell histogram `00`/`11` |
| `expectation_xz` | `expectation` | ⟨X⟩≈1, ⟨Z⟩≈0 on \|+⟩ |
| `multislice_4q_counts` | `sample_counts` | MP1 — idle q0–q1 fixed, measure q2–q3 |
| `mid_circuit_if_measure` | `sample_counts` | Phase C IF + mid-circuit MEASURE |
| `multislice_4q_mid_circuit_if` | `sample_counts` | C2c MP1 idle wires + mid-circuit IF (trajectory zk) |
| `noise_depolarizing_counts` | `sample_counts` | Phase C `noise_model` meta |
| `tn_cut_scalar_28q` | `statevector_scalar` | 28q → 4 slices; TN cut picks idle wires |
| `x_basis_sample_counts` | `sample_counts` | X-basis → `{"0":1024}` |
| `y_basis_sample_counts` | `sample_counts` | Y-basis → `{"0":1024}` |
| `multislice_28q_zz` | `expectation` | OP1 — 28q ZZ (slow tier) |

Fast tier: **10** cases. `TIER=all` adds the slow OP1 case.

## Golden manifest checks

After each task reaches `completed`, `assert_manifest.sh` validates slice outputs (not just HTTP status).

## Quick run

```bash
TIER=fast wqc-docs/examples/e2e/run_e2e.sh
TIER=all wqc-docs/examples/e2e/run_e2e.sh
scripts/devnet-smoke.sh
```
