# Circuit examples (SSOT)

All curated submit payloads live here. The E2E registry (`../e2e/manifest.tsv`) points at these files; do **not** keep parallel copies under `e2e/`.

| Dir | Mode / focus | Files |
|-----|----------------|-------|
| [`scalar/`](scalar/) | `statevector_scalar` | `scalar_h2_amplitude`, `tn_cut_scalar_28q` |
| [`sample/`](sample/) | `sample_counts` (terminal) | Bell, X/Y basis |
| [`expectation/`](expectation/) | `expectation` | `expectation_xz`, `multislice_28q_zz` (OP1, slow) |
| [`multislice/`](multislice/) | MP1 idle-wire sample | `multislice_4q_counts` |
| [`mid_circuit/`](mid_circuit/) | Phase C1 / C2c IF + MEASURE | mid-circuit IF (± multislice) |
| [`noise/`](noise/) | Phase C3 noise_model | `noise_depolarizing_counts` |

## Convention

- **Filename stem ≈ E2E case `name`** in `manifest.tsv`.
- Regression-oriented `sample_counts` cases used by E2E typically use **`shots: 512`** (locked in `assert_manifest.sh`). Deterministic X/Y basis demos use **`shots: 1024`**.
- Prefer editing files here; rebuild/restart nodes only if core/orch behavior changes, not for payload renames alone.

## Path redirects (former topic dirs)

| Old path | New path |
|----------|----------|
| `examples/basis/x_sample_counts.json` | `circuits/sample/x_basis_sample_counts.json` |
| `examples/basis/y_sample_counts.json` | `circuits/sample/y_basis_sample_counts.json` |
| `examples/basis/xy_expectation.json` | `circuits/expectation/expectation_xz.json` |
| `examples/slice/multislice_sample_counts.json` | `circuits/multislice/multislice_4q_counts.json` |
| `examples/slice/multislice_expectation.json` | `circuits/expectation/multislice_28q_zz.json` |
| `examples/phase_c/mid_circuit_if_measure.json` | `circuits/mid_circuit/mid_circuit_if_measure.json` |
| `examples/phase_c/multislice_4q_mid_circuit_if.json` | `circuits/mid_circuit/multislice_4q_mid_circuit_if.json` |
| `examples/phase_c/noise_model_sample_counts.json` | `circuits/noise/noise_depolarizing_counts.json` |
| `examples/e2e/*.json` (payloads) | same names under `circuits/…/` |

See WHITEPAPER §3.4, `PHASE_C_SCOPE.md`, and topic notes historically in basis/slice READMEs (folded into this table).
