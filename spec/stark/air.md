# Trace Column Layout and AIR Constraints

## Trace columns

The execution trace has 11 f64 columns per row (`TRACE_WIDTH`). Each row represents the quantum state at a single point in the circuit execution.

| Index | Name | Description |
|-------|------|-------------|
| 0 | `v0_re` | Real part of amplitude register 0 |
| 1 | `v0_im` | Imaginary part of amplitude register 0 |
| 2 | `v1_re` | Real part of amplitude register 1 |
| 3 | `v1_im` | Imaginary part of amplitude register 1 |
| 4 | `gate_id` | Gate identifier for the current row |
| 5 | `target_qubit` | Target qubit index |
| 6 | `ctrl_active` | Control activation flag (> 0.5 = active) |
| 7 | `ctrl_active_2` | Second control activation flag (for CCNOT) |
| 8 | `ctrl_qubit` | Control qubit index |
| 9 | `ctrl_qubit_2` | Second control qubit index |
| 10 | `transition_link` | Transition continuity flag (1.0 = link to next row) |

### Row pattern

Each active gate produces two consecutive rows:

1. **Pre-gate row**: contains the gate parameters (`gate_id`, `target_qubit`, controls) and the amplitudes *before* the gate is applied.
2. **Post-gate row**: has `gate_id = 0` (no gate) and contains the amplitudes *after* the gate is applied.

A terminal boundary row follows the last gate with `gate_id = 0` and `transition_link = 0`.

### Gate encoding

| gate_id | Gate | Description |
|---------|------|-------------|
| 0 | NONE | Post-gate or terminal row |
| 1 | H | Hadamard |
| 2 | X | Pauli-X (NOT) |
| 3 | Y | Pauli-Y |
| 4 | Z | Pauli-Z |
| 5 | RX | Rotation-X |
| 6 | RY | Rotation-Y |
| 7 | RZ | Rotation-Z |
| 8 | CNOT | Controlled-X |
| 9 | CZ | Controlled-Z |
| 10 | CCNOT | Toffoli (controlled-controlled-X) |
| 11 | MEASURE | Measurement (trajectory branch) |
| 12 | IDLE | Idle (no-op, amplitudes unchanged) |

## AIR columns (expanded)

The prover expands the 11-column trace to 21 AIR columns before constraint evaluation.

| AIR columns | Source | Purpose |
|-------------|--------|---------|
| 0–3 | v0_re, v0_im, v1_re, v1_im | Amplitude registers |
| 4 | gate_id | Gate selector |
| 5 | target_qubit | Target qubit |
| 6 | ctrl_active | Control flag selector |
| 7 | ctrl_active_2 | Second control flag selector |
| 8 | ctrl_qubit | Control qubit |
| 9 | ctrl_qubit_2 | Second control qubit |
| 10 | transition_link | Link continuity |
| 11–20 | selector expansion gates | Individual gate selectors (one-hot derived from gate_id) |

## AIR constraints

The constraint polynomial enforces:

### Amplitude continuity

When `transition_link = 1.0`, adjacent rows in the same amplitude register must be equal. This links post-gate rows to the next pre-gate row when the next gate operates on the same target qubit.

### Gate constraints

Each active gate enforces a specific amplitude transformation on `v0` and `v1`:

- **H (Hadamard)**: maps `|0⟩ → (|0⟩ + |1⟩)/√2, |1⟩ → (|0⟩ − |1⟩)/√2`
- **X, Y, Z**: standard Pauli rotations
- **RX, RY, RZ**: rotation gates by a fixed angle
- **CNOT**: flips target when control is |1⟩
- **CZ**: phase-flips target when control is |1⟩
- **CCNOT**: flips target when both controls are |1⟩
- **MEASURE**: collapses to |0⟩ or |1⟩ with no amplitude continuity constraint
- **IDLE**: amplitudes unchanged

### Selector consistency

`gate_id` must decode bijectively to the one-hot selector columns (columns 11–20). Exactly one selector must be 1.0 and the rest 0.0.

### Control consistency

When `ctrl_active = 1.0`, the control qubit index must be valid and the gate behavior must depend on the control amplitude.

### Boundary condition

The terminal row amplitudes must match the `boundary_v0_re`, `boundary_v0_im`, `boundary_v1_re`, `boundary_v1_im` values committed in the v1 proof header.
