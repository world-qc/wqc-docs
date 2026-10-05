# OpenQASM linear subset

- **Status:** Working spec — client input boundary
- **Tier:** B (implementation snapshot)
- **Verified:** 2026-10-05
- **Verified against:** `wqc-orchestrator` `internal/domain/qasm`
- **Audience:** Client developers submitting circuits
- **Related:** [`spec/circuit-payload.md`](circuit-payload.md) §8, `wqc-orchestrator/openapi/openapi.yaml`, [`examples/circuits/qasm/`](../examples/circuits/qasm/)

## Scope

OpenQASM 2.0 and 3.0 straight-line programs can be submitted in place of a
circuit JSON array. The orchestrator lowers them to the gate list in
[`circuit-payload.md`](circuit-payload.md) §1 before `ValidateSubmitRequest`.
`wqc-core` still receives that JSON only. This document is what the lowering
accepts and what it refuses. It is not a schedule and it does not change the
simulator, the slicer, or the proof system.

Two HTTP surfaces share one translator:

| Surface | Effect |
|---------|--------|
| `POST /api/v1/qasm/translate` | Preview. No task and no escrow. |
| `POST /api/v1/submit` field `openqasm` | Same lowering, then the existing submit path. Mutually exclusive with `circuit`. |

Escrow uses the lowered gate count. `swap` is three `CNOT`s, so a source line
is not a billable gate. An omitted qubit or classical width is inferred from
the declarations. A non-zero width that disagrees with those declarations is
rejected.

## What you can submit

Versions `OPENQASM 2.0;` and `OPENQASM 3.0;` only. `include` is accepted only
as the markers `stdgates.inc` and `qelib1.inc`. The file is not opened.

Registers flatten in declaration order. `q[0]` is qubit 0 and `c[0]` is cbit 0,
the same order as counts keys in [`circuit-payload.md`](circuit-payload.md) §3.1.
`qreg` / `creg` and `qubit` / `bit` are both accepted. The classical width is
the declared width, not the number of measurements.

| Source | What comes out |
|--------|----------------|
| `h` `x` `y` `z` `s` `t` `rx` `ry` `rz` `cx` `cz` `ccx` `measure` `reset` | The native gate. `cx` / `ccx` become `CNOT` / `CCNOT`. |
| `sdg` | `Z`, then `S` |
| `tdg` | `Z`, then `S`, then `T` |
| `swap` | three `CNOT`s |
| `id` / `i` | dropped, with a warning |
| `barrier` | dropped, with a warning |

`id`, `i`, and `barrier` warnings use `QASM_IGNORED`. The circuit is still
returned.

`sdg` and `tdg` stay phase-exact. `S` is `diag(1, i)` in the core and is not
rewritten as `RZ(π/2)`, because that global phase shows up in
`statevector_scalar`.

Angles are radians. `pi`, `+ - * /`, parentheses, and OpenQASM 3 `const` names
fold at translate time. A `const` may be used as a rotation angle or as a
register width. Inside a `gate` or `def`, an angle parameter hides a `const`
of the same name, and a parameter named `pi` is that parameter.

A `gate` or `def` whose body is itself straight-line is inlined, including a
call to another inlineable definition. Angle parameters and qubit or bit
parameters are substituted at the call. A `def` that puts every argument in
one parenthesis list must appear earlier in the source. Gate-style calls
(`name(angles) q0, q1`) are matched when the circuit is lowered, so definition
and call can appear in either order.

Both measure forms are accepted: `measure q -> c` and `c = measure q`.

## What is rejected

An error diagnostic rejects the whole program. There is no partial circuit.

| Condition | Code |
|-----------|------|
| `while`, `for`, `if`, `else`, `extern`, `defcal`, `delay`, `box`, `input` | `QASM_UNSUPPORTED_FEATURE` |
| Gate name outside the table (`sx`, `u3`, controlled rotations, `rxx`, `ryy`, `rzz`, …) | `QASM_UNSUPPORTED_GATE` |
| `include` other than the two markers above | `QASM_UNSUPPORTED_INCLUDE` |
| `opaque`, a `gate` / `def` body that is not straight-line, a recursive definition, or a definition that shadows a built-in gate | `QASM_CUSTOM_GATE` |
| Angle that is not a compile-time constant, including function calls | `QASM_NONCONST_PARAM` |
| Undeclared register | `QASM_UNDECLARED` |
| Index out of range, or an index on a gate parameter | `QASM_INDEX` |
| Source, statement, expression, register, or lowered-gate limit | `QASM_LIMIT` |
| Syntax the parser cannot read, including a `gate` or `def` whose name is a statement keyword | `QASM_PARSE` |
| Version missing, or not 2.0 / 3.0 | `QASM_VERSION` |
| Program that lowers to no gates | `QASM_EMPTY` |
| `circuit` and `openqasm` together, or an explicit width that disagrees with the declarations | `QASM_CONFLICT` |

OpenQASM `if` is rejected even though the JSON IR has an `IF` gate. The JSON
form is a single controlled gate. The OpenQASM form is a block, and it stays
outside this subset. A client that needs that control submits JSON.

## What this subset is not

- Not the full `stdgates.inc` library. `p`, `u`, `u1`, `u2`, `u3`, `sx`, and
  the controlled-rotation family are refused because their global phase is
  visible to `statevector_scalar` and the IR has no gate for that phase.
- Not pulse, calibration, or timing (`defcal`, `delay`, `box`).
- Not a change to `wqc-core`. Slicing and proofs run on the lowered JSON.

Qiskit circuits should be exported in the native basis (`h`, `cx`, `rx`, …),
not with `basis_gates=['u3', 'cx']`.
