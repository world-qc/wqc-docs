# Proof Transcript Formats

## v1: Embedded trace proof

```
<sub_task_id\0>
<_M31_QUANTUM_AIR_V1_>
<circuit_id\0><node_id\0><slice_id\0><output_hash\0>
[optional terminal_statevector_digest\0]
[optional MSH1<measurement_spec_hash>\0]
<trace_rows: u32 LE>
<trace: f64 LE repeated trace_rows * 11>
<air_sum: u32 LE>
<boundary_v0_re: u32 LE>
<boundary_v0_im: u32 LE>
<boundary_v1_re: u32 LE>
<boundary_v1_im: u32 LE>
```

All string fields are NUL-terminated C strings. Multibyte integers are little-endian.

The trace section stores 11 f64 columns per row (see [air.md](air.md)). The verifier re-expands the trace to 21 AIR columns and recomputes the constraint sum. A valid proof must have `air_sum == 0`. The boundary values encode the real and imaginary parts of the two amplitude registers (`v0`, `v1`) from the final trace row, scaled by 2^30 and rounded to u32.

## v2: Plonky3 FRI STARK proof

```
<sub_task_id\0>
<_M31_PLONKY3_STARK_V2_>
<circuit_id\0><node_id\0><slice_id\0><output_hash\0>
[optional terminal_statevector_digest\0]
[optional MSH1<measurement_spec_hash>\0]
<proof_len: u32 LE>
<proof: postcard-encoded p3_uni_stark::Proof>
```

The FRI STARK uses Polygon Plonky3 over the Mersenne31 field with Circle PCS commitment. The postcard-encoded proof contains the quotient polynomial evaluations, Merkle openings, and FRI layers. The verifier reconstructs the AIR trace from the same quantum execution inputs (not embedded) and evaluates the constraint polynomial over the trace extension.

After the unitary proof body, auxiliary segments may follow (detected by their markers):

- Distribution segment: `_M31_DIST_V1_` or `_M31_DIST_V2_`
- Trajectory segment: `_M31_TRAJ_V1_` or `_M31_TRAJ_V2_`
- Born zk tail: `_M31_BORN_TAIL_V1_` (inside distribution segment)
- Trajectory zk tail: `_M31_TRAJ_STARK_V1_` (inside trajectory segment)

## v3: Compose proof

v3 compose nodes wrap two child proofs into a single verifiable node with optional R2 aggregation.

```
<parent_task_id\0>
<_WQC_COMPOSE_V3_>
<compose_label\0>
<manifest_root_hash\0>
<left_child_hash: 32 bytes>
<right_child_hash: 32 bytes>
<left_len: u32 LE>
<left_child: left_len bytes>
<right_len: u32 LE>
<right_child: right_len bytes>
[optional R2 aggregation tail (see aggregation.md)]
```

### Compose labels

| Label | Left child | Right child |
|-------|------------|-------------|
| `leaf:unitary_born` | v2 unitary proof (+ optional MSH / terminal digest) | Born leaf (`_M31_BORN_LEAF_V1_`) |
| `leaf:unitary_traj` | v2 unitary proof (+ link digest) | Trajectory leaf (`_M31_TRAJ_LEAF_V1_`) |
| *(task/slice tree)* | Verified slice winner | Verified slice winner |

## Distribution segment

Appended after the unitary proof body for `sample_counts` outputs.

### v1 (legacy)

```
<_M31_DIST_V1_>
<seed: u64 LE>
<shots: u32 LE>
<probability_digest: 32 bytes SHA3-256>
<probabilities: f64 LE * 2^n>
```

### v2

```
<_M31_DIST_V2_>
<seed: u64 LE>
<shots: u32 LE>
<measurement_spec_hash: 64 ASCII hex chars>
<probability_digest: 32 bytes SHA3-256>
<probabilities: f64 LE * 2^n>
[optional _M31_BORN_TAIL_V1_ tail]
```

The Born zk tail, when present, contains an inner STARK proving the correctness of the probability distribution.

## Trajectory segment

Appended after the unitary proof body for mid-circuit measurement outputs.

```
<_M31_TRAJ_V1_> or _M31_TRAJ_V2_
<event_count: u32 LE>
for each event:
  <measured_qubit: u32 LE>
  <outcome: u32 LE>
  <pre_measure_state_digest: 32 bytes>
  <p0: u32 LE fixed-point>
  <p1: u32 LE fixed-point>
[optional _M31_TRAJ_STARK_V1_ tail]
```

v2 includes an optional `unitary_link_digest` (64 ASCII hex chars + NUL) before the event list.

The trajectory zk tail contains marginal STARK proofs for each unique pre-measure state, plus an optional per-shot Bernoulli sampling STARK.
