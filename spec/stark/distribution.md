# Distribution and Trajectory Binding

For `sample_counts` outputs, the proof must demonstrate that the claimed measurement counts are the unique deterministic result of the proved unitary execution, the bound `sample_seed`, and the bound measurement specification.

## Pipeline

```
Unitary execution STARK
  → Born / marginal probabilities (deterministic function of terminal state)
  → PRNG(sample_seed) + inverse-CDF sampling (deterministic)
  → counts / output_result_hash
```

The verifier checks each stage against the commitment in the proof transcript.

## Layers

### Algebraic binding (C2a)

The distribution or trajectory segment commits to:

- **seed**: 64-bit integer deterministically derived from the task specification.
- **shots**: number of sampling iterations.
- **measurement_spec_hash**: SHA3-256 hex of the canonical measurement specification JSON.
- **probability digest**: SHA3-256 of the concatenated floating-point probabilities (terminal Born distribution) or per-event marginal probabilities (trajectory).

The verifier recomputes the expected counts from the committed probabilities and seed, then compares the resulting `output_result_hash` against the one in the public inputs.

### Born zero-knowledge proof (C2b)

A streaming `DistributionAir` operates over the terminal Born probability table. One trace row per basis outcome, independent of the exponential column blowup from a dense 2^n representation.

The AIR enforces:

- Probabilities are expressed in fixed-point arithmetic.
- Sum of probabilities equals 1 (within rounding tolerance).
- Probability digest binding to the committed value.
- Optional unitary link digest binding when the proof is composed (`leaf:unitary_born`).

### Trajectory zero-knowledge proof (C2c)

For circuits with mid-circuit measurements, each unique pre-measurement state is proven via a Z-marginal AIR. An optional per-shot Bernoulli sampling AIR proves each individual measurement outcome:

1. The prover replays `StdRng(shot_seed)` to produce a uniform random value `u` in [0, 1) for each MEASURE event.
2. The AIR constrains a fixed-point comparison: outcome = 1 if `u ≥ p_0`, else 0.
3. Gap-bit decomposition ensures the comparison is correctly bounded.

The host provides `u` algebraically (replayed from seed); the AIR only proves the fixed-point inequality for the claimed outcome.

## Compose labels

When the unitary proof and the distribution/trajectory proof are produced as separate child proofs, they are wrapped in a v3 compose node:

| compose_label | Left child | Right child |
|---------------|------------|-------------|
| `leaf:unitary_born` | v2 unitary proof | Born leaf (`_M31_BORN_LEAF_V1_`) |
| `leaf:unitary_traj` | v2 unitary proof | Trajectory leaf (`_M31_TRAJ_LEAF_V1_`) |

The compose verifier cross-checks that the `terminal_statevector_digest` (or `measurement_spec_hash`) from the unitary child matches the value in the distribution/trajectory segment.

## Binding without zero-knowledge

When zero-knowledge AIRs are not enabled, the algebraic segment alone provides binding. The verifier recomputes the expected counts from the committed probabilities and seed. This is strictly weaker than a full STARK (the prover could deviate from the true Born rule without being caught), but sufficient when the execution trace itself is already STARK-proven.
