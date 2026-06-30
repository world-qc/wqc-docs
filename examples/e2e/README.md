# Devnet E2E examples

Curated submit payloads for the local docker devnet. Used by `run_e2e.sh` and documented in [`AGENT_E2E.md`](../../../AGENT_E2E.md).

## Layout

| File | Mode | What it exercises |
| --- | --- | --- |
| `scalar_h2_amplitude.json` | `statevector_scalar` | 2q Bell, single slice |
| `sample_bell_counts.json` | `sample_counts` | Bell histogram `00`/`11` |
| `expectation_xz.json` | `expectation` | ⟨X⟩≈1, ⟨Z⟩≈0 on \|+⟩ |
| `multislice_4q_counts.json` | `sample_counts` | MP1 — idle q0–q1 fixed, measure q2–q3 |
| `mid_circuit_if_measure.json` | `sample_counts` | Phase C IF + mid-circuit MEASURE |
| `noise_depolarizing_counts.json` | `sample_counts` | Phase C `noise_model` meta |
| `tn_cut_scalar_28q.json` | `statevector_scalar` | 28q → 4 slices; TN cut picks idle wires (`e_2` before `e_0`) |
| `multislice_28q_zz.json` | `expectation` | OP1 — 28q ZZ on q26–q27 (slow tier) |

`manifest.tsv` lists cases, timeouts, and tier (`fast` / `slow`).

## Related examples (not duplicated here)

- `wqc-docs/examples/basis/` — X/Y basis (`x_sample_counts.json` may hit AIR issues on some GPU cores; prefer `e2e/sample_bell_counts.json` for smoke tests)
- `wqc-docs/examples/slice/` — originals for multislice cases (copied into `e2e/`)
- `wqc-docs/examples/phase_c/` — Phase C sources

## Quick run

```bash
# fast suite (~30s)
TIER=fast wqc-docs/examples/e2e/run_e2e.sh

# include 28q OP1 expectation (~5 min)
TIER=all wqc-docs/examples/e2e/run_e2e.sh
```
