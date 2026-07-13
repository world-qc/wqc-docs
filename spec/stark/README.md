# WQC STARK Proof Specification

This directory defines the binary proof format, AIR constraints, and verification protocol used by the WQC cryptographic proof engine. The spec governs the interface between three components:

- **Prover** (node-side): produces execution traces from quantum circuit simulation and generates STARK proofs.
- **Verifier** (orchestrator-side): ingests proofs, checks public-input binding, and validates AIR / FRI / aggregate constraints.
- **Leaf compose**: wraps unitary execution proofs together with distribution or trajectory proofs into a single verifiable node.

## Versions

| Transcript version | Marker | Mechanism |
|--------------------|--------|-----------|
| v1 | `_M31_QUANTUM_AIR_V1_` | Embedded trace + recomputed AIR constraint sum |
| v2 | `_M31_PLONKY3_STARK_V2_` | Plonky3 FRI STARK over Mersenne31 Circle PCS |
| v3 | `_WQC_COMPOSE_V3_` | Structural tree compose (binary child proofs + R2 aggregation tail) |

Auxiliary segments attach to the unitary body for `sample_counts` outputs:

| Segment | Marker | Function |
|---------|--------|----------|
| Distribution | `_M31_DIST_V1_` / `_M31_DIST_V2_` | Binds seed, shots, probabilities, measurement spec |
| Born zk | `_M31_BORN_TAIL_V1_` | Zero-knowledge proof of Born-rule distribution |
| Trajectory | `_M31_TRAJ_V1_` / `_M31_TRAJ_V2_` | Binds mid-circuit measurement events and digests |
| Trajectory zk | `_M31_TRAJ_STARK_V1_` | Zero-knowledge proof of trajectory marginals and shot sampling |
| R2 aggregation | `_WQC_AGG_TAIL_V4_` | O(1) aggregation STARK over compose-tree digests |

## Public inputs (`StarkContext`)

Every proof binds the following fields in its transcript:

| Field | Type | Description |
|-------|------|-------------|
| `circuit_id` | string | Hash identifying the pruned circuit sub-graph |
| `sub_task_id` | string | Unique sub-task identifier |
| `node_id` | string | Identifier of the proving node |
| `slice_id` | string | Binary slice path in the tensor network tree |
| `output_hash` | string | SHA3-256 hex of the result payload (scalar or canonical sample counts JSON) |
| `terminal_statevector_digest` | string (optional) | SHA3-256 hex linking unitary leaf to Born/trajectory distribution |
| `measurement_spec_hash` | string (optional) | SHA3-256 hex of the canonical measurement spec JSON |

Optional fields are encoded only when non-empty and are identified by a fixed prefix (`MSH1` for `measurement_spec_hash`).

## Verification flow

1. **Marker detection** — read the proof prefix to determine transcript version.
2. **Public-input binding** — verify that all context fields match the embedded proof metadata.
3. **Proof validation** — execute version-specific verification:
   - v1: re-expand trace, recompute AIR constraint sum (must be 0), check boundary amplitudes.
   - v2: verify Plonky3 FRI STARK, then process any auxiliary segments.
   - v3: recursively verify child proofs, then verify R2 aggregation tail (fast path) or walk the tree (audit path).
4. **Distribution / trajectory binding** — for `sample_counts` outputs, verify that the deterministic sampling pipeline (Born/trajectory probabilities → PRNG → counts) matches the claimed result.

## Constants

### Soft caps (noiseless sample_counts)

| Limit | Value |
|-------|-------|
| Algebraic Born / marginal qubits | 16 |
| Plonky3 Born zk qubits | 16 |
| Born zk outcomes | 64 |
| Trajectory marginal zk qubits | 16 |
| Per-shot sampling events | 2048 |

### Transcript markers

| Marker | Value |
|--------|-------|
| `V1_MARKER` | `_M31_QUANTUM_AIR_V1_` |
| `V2_MARKER` | `_M31_PLONKY3_STARK_V2_` |
| `V3_COMPOSE_MARKER` | `_WQC_COMPOSE_V3_` |
| `LEGACY_MARKER` | `_M31_QUANTUM_AIR_STARK_` (rejected) |
| `BORN_LEAF_MARKER` | `_M31_BORN_LEAF_V1_` |
| `TRAJ_LEAF_MARKER` | `_M31_TRAJ_LEAF_V1_` |
| `DIST_MARKER_V1` | `_M31_DIST_V1_` |
| `DIST_MARKER_V2` | `_M31_DIST_V2_` |
| `BORN_TAIL_MARKER` | `_M31_BORN_TAIL_V1_` |
| `TRAJ_MARKER` | `_M31_TRAJ_V1_` / `_M31_TRAJ_V2_` |
| `TRAJ_STARK_MARKER` | `_M31_TRAJ_STARK_V1_` |
| `AGG_TAIL_MARKER` | `_WQC_AGG_TAIL_V4_` |
| `MEASUREMENT_SPEC_HASH_PREFIX` | `MSH1` |

## Files

| File | Scope |
|------|-------|
| [transcript.md](transcript.md) | Binary proof format for all transcript versions |
| [air.md](air.md) | Trace column layout, gate encoding, AIR constraints |
| [distribution.md](distribution.md) | Distribution / trajectory binding and sampling protocol |
| [aggregation.md](aggregation.md) | Proof aggregation (v3 compose, R2 aggregation STARK) |
