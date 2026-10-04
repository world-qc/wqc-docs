# OpenQASM examples

Linear OpenQASM 2.0 / 3.0 programs for `POST /api/v1/qasm/translate` and the
`openqasm` field on `POST /api/v1/submit`. These are not E2E manifest rows.
The lowered JSON is the circuit payload in [`circuit-payload.md`](../../../spec/circuit-payload.md) §8.

| File | What it lowers to |
|------|-------------------|
| `bell.qasm` | `H`, `CNOT`, two `MEASURE` (register-wide `measure q -> c`) |
| `bell.qasm3` | Same gates, OpenQASM 3 `qubit` / `bit` and `c = measure q` |

`swap` becomes three `CNOT`s and `tdg` becomes `Z`, `S`, `T`. Quote escrow from
`lowered_gate_count`, not from the number of source lines.

Named `const` values fold. A `gate` or `def` with a straight-line body is
inlined. `while`, `if`, `extern`, `opaque`, `sx`, and `u3` are rejected. Export Qiskit circuits
with the native basis (`h`, `cx`, `rx`, …), not `basis_gates=['u3','cx']`.
