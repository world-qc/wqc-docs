# Circuit payload semantics

- **Status:** Working spec — payload contract
- **Tier:** B (implementation snapshot)
- **Verified:** 2026-08-29
- **Verified against:** `wqc-orchestrator@9f539f6` `wqc-core@f162911` `wqc-node@2718da4`
- **Audience:** Client developers, and implementers of the submit / dispatch / compute path
- **Related:** `wqc-orchestrator/openapi/openapi.yaml`, `wqc-core/openapi/openapi.yaml`, `wqc-core/doc/trace-spec.md`, [`spec/zk-STARK.md`](zk-STARK.md)

## Scope

This document is the source of truth for the **meaning** of a circuit payload: the gate
grammar, measurement rules, output modes, determinism guarantees, and scale limits that
hold across the whole pipeline.

The **structural** contract of each HTTP surface — required fields, types, status codes —
lives in the OpenAPI file of the repository that implements it. Those specs cite this
document rather than restating it:

| Surface | Structural spec |
|---------|-----------------|
| Client → orchestrator (`POST /api/v1/submit`) | `wqc-orchestrator/openapi/openapi.yaml` |
| Node → core (`POST /compute`) | `wqc-core/openapi/openapi.yaml` |

Orchestrator → node dispatch is not HTTP; it is a signed binary `SubTask` frame over
libp2p, documented in `wqc-orchestrator/internal/domain/task/wire.go`.

## 1. Gate grammar

A circuit is a JSON array of gates. Each gate is an adjacently tagged object: `type`
selects the operation and `params` carries its operands.

| `type` | `params` shape | Meaning |
|--------|----------------|---------|
| `H` `X` `Y` `Z` `S` `T` | qubit index | Single-qubit unitary |
| `RESET` | qubit index | Project the qubit to \|0⟩ |
| `CNOT` `CZ` | `[control, target]` | Two-qubit unitary |
| `CCNOT` | `[control_1, control_2, target]` | Toffoli |
| `RX` `RY` `RZ` | `[qubit, theta_radians]` | Rotation; `theta` is a float |
| `MEASURE` | `{ "qubit": q, "cbit": c }` | Z-basis measurement into a classical bit |
| `IF` | `{ "cbit": c, "value": 0\|1, "gate": <gate> }` | Apply the nested gate when `classical[c] == value` |

Qubit indices are **global** (relative to the submitted `qubit_count`) in a client
payload. After slicing they are **local** to the compact register, so the same gate list
carries different indices at different pipeline stages.

### 1.1 Two `params` dialects

Single-parameter gates (`H`, `X`, `Y`, `Z`, `S`, `T`, `RESET`) have two accepted wire
forms, and the two ends of the pipeline do **not** accept the same set.

| Stage | `{"type": "H", "params": 0}` | `{"type": "H", "params": [0]}` |
|-------|------------------------------|--------------------------------|
| Client → orchestrator | accepted | accepted |
| Node → core `/compute` | accepted | **rejected — `400`** |

The orchestrator normalizes either form while pruning. `wqc-node` then flattens
one-element arrays to a bare value (`normalize_gate_params`), recursing into
`IF.params.gate`, immediately before calling core. Core deserializes into a Rust enum
whose single-parameter variants take a scalar, so an array is a type error there.

**Client guidance:** either form is fine for `POST /api/v1/submit`; the curated examples
under [`examples/circuits/`](../examples/circuits/) use the array form.

**Implementer guidance:** anything that calls core `/compute` directly — test harnesses,
debugging scripts, alternative node implementations — must emit the bare form. Do not
copy a client payload straight through.

## 2. Measurement

`MEASURE` is **Z-basis only**. There is no basis parameter.

To measure in another basis, rotate first:

| Target basis | Insert immediately before `MEASURE` |
|--------------|--------------------------------------|
| X | `H` on the same qubit |
| Y | `RX` with `theta = -π/2` on the same qubit |

For `expectation` mode, do not rotate — put `X` or `Y` directly in the observable label.

Reference payloads live in [`examples/circuits/sample/`](../examples/circuits/sample/)
(X/Y basis histograms) and [`examples/circuits/expectation/`](../examples/circuits/expectation/).

### 2.1 Terminal vs mid-circuit

A circuit uses **mid-circuit semantics** when it contains `RESET`, `IF`, or any unitary
gate after the first `MEASURE`. Otherwise its measurements are **terminal**.

The distinction is not cosmetic — it selects the execution and proving strategy:

| | Terminal | Mid-circuit |
|--|----------|-------------|
| Sampling | Born probabilities from the contracted statevector | Per-shot trajectory simulation |
| Proof tail | Born distribution segment | Trajectory segment |
| Qubit limit | bounded in practice by statevector width | **hard limit of 20** |

## 3. Output modes

`output_mode` selects what the task returns and what the STARK binds.

| Mode | Returns | `output_result_hash` binds |
|------|---------|----------------------------|
| `statevector_scalar` (default) | Amplitude at \|0…0⟩ on free wires | Canonical `ComplexResult` JSON |
| `sample_counts` | Shot histogram and `shots` | Canonical counts JSON |
| `expectation` | Expectation value per observable `id` | Canonical expectation JSON |

In every mode the unitary execution trace is what the leaf STARK proves. The output mode
only changes which result digest is bound into the public inputs.

`statevector_scalar` rejects circuits containing `MEASURE`. `expectation` requires
`observables` and rejects `MEASURE`. `sample_counts` requires at least one `MEASURE`,
plus `classical_bit_count` and `shots`.

The scalar amplitude is present in **all** responses, including `sample_counts` and
`expectation`, because contraction always produces it.

### 3.1 `counts` key order

Histogram keys are bitstrings in **Qiskit order**: the **rightmost** character is
`cbit 0`. A two-bit register where `cbit 0 = 1` and `cbit 1 = 0` is the key `"01"`.

Classical bits never written by a `MEASURE` are `0`.

## 4. Determinism and quorum

`sample_counts` is reproducible by construction. The client does **not** supply a seed:
the orchestrator generates `sample_seed` from a CSPRNG at submit time and copies it into
every sub-task. All workers on a slice therefore sample the same histogram.

This is what makes shot-based results consensus-checkable:

| Mode | Quorum comparison |
|------|-------------------|
| `statevector_scalar` | Epsilon match on the amplitude |
| `expectation` | Epsilon match on each value |
| `sample_counts` | **Exact** match under the shared seed |

A worker returning a differently-seeded or noisy histogram fails quorum. This is also
why `noise_model` weakens the proof — see §6.

## 5. Scale limits

| Limit | Value | Where enforced |
|-------|-------|----------------|
| `classical_bit_count` | `1..=16` | Submit validation |
| Mid-circuit `sample_counts` qubits | `<= 20` | Submit validation and core |
| Measured qubits (compact register after slicing) | `<= 20` | Slice policy |

These come from probability-table enumeration and dense trajectory state, not from the
STARK. Large sliced workloads should use `statevector_scalar`, which has no such cap.

## 6. Optional noise model

`noise_model` applies simulator noise during **mid-circuit trajectory sampling only**:

| Field | Meaning |
|-------|---------|
| `depolarizing_p` | Probability of a random Pauli after each single-qubit gate |
| `readout_error` | Probability of a classical bit flip after each `MEASURE` |

Both are probabilities in `[0, 1]`.

Noise is **not bound into the STARK**. A noisy run downgrades the distribution binding to
unbound, so the transcript no longer certifies the histogram. Treat `noise_model` as a
research and simulation feature, not a verifiable production mode.

## 7. Observables

For `expectation`, each observable is a named Pauli sum `O = Σ coeff_k · P_k`.

Each term has a `label` and a complex `coeff`. The label is a Pauli string over the
alphabet `I`, `X`, `Y`, `Z`, and its **length must equal `qubit_count`**.

Labels use the **same Qiskit order as `counts` keys**: the **rightmost** character
applies to **qubit 0**. So on a two-qubit register, `"IX"` means `X` on qubit 0 and
identity on qubit 1.

Observable `id` must be unique within a request, and results are keyed by it. An
observable with no terms, an unknown Pauli character, or a length mismatch is rejected.
`expectation` also forbids `MEASURE` gates entirely.
