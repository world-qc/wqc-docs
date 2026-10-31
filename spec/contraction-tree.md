# Exact contraction tree

- **Status:** Working spec — scalar tree contract
- **Tier:** B (implementation snapshot)
- **Verified:** 2026-11-01
- **Verified against:** uncommitted `feature/contraction-tree` in `wqc-orchestrator`, `wqc-node`, and `wqc-core`
- **Audience:** Implementers of the scheduler, node, and core; reviewers of quorum, fees, and proof claims
- **Related:** [`mps-scalar.md`](mps-scalar.md) (the path with no tree), [`economics.md`](economics.md) (fees), [`p2p-protocols.md`](p2p-protocols.md) (signed bytes), [`zk-STARK.md`](zk-STARK.md) (what the proof binds), [`architecture-current.md`](architecture-current.md) (who dispatches)

## Scope

This document is the contract for a `statevector_scalar` task whose orchestrator
attaches an **exact contraction tree**:

- when that tree is attached, and when the task stays on the MPS path (§1);
- the JSON the signature carries (§2);
- the greedy plan that produces it (§3);
- what core executes, and what it rejects (§4);
- the signed suffix (§5);
- the quote and the gas inputs (§6);
- what the proof does not certify (§7).

A dispatch with no tree is [`mps-scalar.md`](mps-scalar.md). Expectation and
`sample_counts` never carry a tree. The node does not build a plan. There is no
factorial search and no cotengra dependency. WebGPU stays off by default.
`max_qubit_capability` is unchanged.

## 1. When a tree is attached

The orchestrator runs this greedy walk at quote, at submit, and at `Start`.
All three use the same rule. The scheduler keeps the `Start` tree and does not
plan again while it dispatches. The node does not plan.

Quote treats an empty `output_mode` as `statevector_scalar`, and submit stores
it as `statevector_scalar` before the task is saved. A trap sub-task copies the
parent's mode, so no dispatch carries an empty `output_mode`. A trap is still
built from a different circuit and does not receive the parent's tree.

| Circuit | Result |
|---------|--------|
| Quote with no circuit | No tree. Submit rejects an empty circuit. The 2048-qubit MPS stand-in in [`mps-scalar.md`](mps-scalar.md) §4 |
| Non-empty, plan fits | One slice. `estimated_slices = 1`. Not saturated |
| Non-empty, plan returns no tree | No tree. Cutwidth branch or time split, including their ceilings |
| `expectation`, `sample_counts` | No tree, in either case |

A fitting tree is one slice even when the cutwidth walk would hit `2^30` or the
4096-node cap. The gate cap (100000) and the qubit cap (4096) still return no
tree, and the estimate then saturates as in [`mps-scalar.md`](mps-scalar.md) §4.
Submit rejects that saturation before locking quorum. `Start` still returns
false on it, and submit then calls `abortTask`.

The planner refuses a tree above 1 GiB, and core checks the declared and
measured peak against that figure (§4). The quote uses that peak only as
`VRAM_MiB`. A node accepts the task when `qubit_count` is within its
`max_mps_qubits` and does not read `peak_bytes`. A 25-qubit star whose peak is
805306400 bytes is inside that width for a node whose `max_mps_qubits` is 128.
A 4096-qubit register of one `H` per wire has peak 131072 bytes and is refused
by a node whose `max_mps_qubits` is 2048.

The dispatched slice has empty `slice_assignments`, `qubit_count` equal to
`original_qubit_count`, `mps_time_split` zero, and `mps_site_order` empty.
`mps_max_bond_dim` is the value the MPS path would send: the boundary bond when
that path would time-split, and the usual recommendation otherwise. The STARK
trace is still an MPS sweep (§7). A slice that already has assignments does not
receive a tree. Recovery of a failed tree slice resends that saved sub-task,
including the same tree. It does not move the slice onto the MPS path.

`PruneCircuitBySlice` on empty assignments is the identity, so `circuit_id` is
the SHA3-256 of the parent circuit JSON. A branched slice still hashes the
pruned compact circuit.

Examples, nearest neighbour unless noted:

| Circuit | Tree | Quote |
|---------|------|-------|
| 16q depth-8 RY+CNOT brickwork | yes, `peak_bytes` 1310784 | 1 slice, `VRAM_MiB` 2 |
| 20q all-to-all CNOT clique | yes (20 open legs) | 1 slice. The cutwidth walk of the same circuit remains 32 |
| 50q depth-8 brickwork | no | 1 slice on the cutwidth walk. The bond proxy is 16, below χ=128, so no time split |
| 50q depth-16 brickwork | no | 1 slice via the time split at gate 392, boundary bond 16 |
| 50q, one `H` on each wire | yes, 50 separate 1-leg tensors | 1 slice |

## 2. IR

The signed JSON is `encoding/json` of this object. Keys are in this order.
Unset operand fields are omitted. Alphabetized keys do not verify.

```json
{"nodes":[{"op":"contract","left":{"ket0":0},"right":{"gate":0}}],"peak_bytes":32}
```

That object is `H` on wire 0. `peak_bytes` is 32.

| Object | Keys, in order | Meaning |
|--------|----------------|---------|
| tree | `nodes`, `peak_bytes` | Contractions, then the declared live peak in bytes |
| node | `op`, `left`, `right` | `op` is `contract` |
| operand | one of `ket0`, `gate`, `node` | Parent wire of a ket-0 leaf, index in the parent circuit, or earlier node |

`gate` counts every gate, including `MEASURE`, `RESET`, and `IF`, which are not
themselves nodes. A circuit with no unitary is `{"nodes":[],"peak_bytes":0}`.
`site_order` is not a field. Wire numbers are the parent circuit's.

A state tensor is a dense array of open parent wires. Bit `i` of the index is
`wires[i]` after those wires are sorted ascending. One complex amplitude is 16
bytes, so a tensor of `L` legs is `16 << L` bytes. A `ket0` leaf has one leg
(32 bytes).

## 3. Planner

Gates are considered in circuit order. `MEASURE`, `RESET`, and `IF` are skipped.
The scalar sweep ignores those gates, so a `RESET` on a scalar circuit does not
change the amplitude. The body of an `IF` is not pulled out. A unitary is `H`,
`X`, `Y`, `Z`, `S`, `T`, `RX`, `RY`, `RZ`, `CNOT`, `CZ`, or `CCNOT`. Any other
type, a duplicate wire, an out-of-range wire, zero qubits, more than 4096
qubits, or more than 100000 gates yields no tree.

A unitary is applied only when every wire it touches is already open on one
state tensor. Until then the planner multiplies the states that hold those
wires. Among those products it picks the fewest result legs, then the pair
whose tensors were produced by the younger gate (a leaf sorts after any gate),
then the smaller minimum wire, then the smaller maximum wire. When those four
match, it keeps the tensor that appears earlier in this gate's argument list.
That last tie is two equal-sized tensors inside one non-contiguous tensor, so
both pairs share that tensor's endpoints. The result has the same number of
legs either way, and the declared peak does not move.

The gate is the right operand. The left state is the one with the smaller
minimum wire. Two gates are not contracted with each other. A gate is applied
only when all of its wires are already open. Untouched wires stay implicit
`|0⟩` and contribute a factor of 1.

The declared peak, while an outer product is allocated, is the other live
tensors plus both inputs plus the result. A gate apply adds no second copy.
The plan returns no tree when a result would pass 26 legs, that sum would pass
1 GiB (`2^30` bytes), or the sum overflows. The leg rule would allow one tensor
of 26 legs, which is exactly 1 GiB. A join that produces 26 legs keeps both
inputs alive, so 25 legs plus 1 leg is about 1.5 GiB and the peak check returns
no tree. The largest tensor this planner emits has 25 legs.

## 4. Executor

Core runs the tree once. The amplitude is `⟨0…0\|ψ⟩`: the product of the
`\|0…0⟩` entry of each live state tensor. It then runs the ordinary MPS sweep
so the prover still has rows (§7).

Validation checks the circuit, an identity site order, and that a peak is
declared and at most 1 GiB. The walk checks leg count, measures the live peak,
and checks that each gate is consumed in circuit order. The declared peak must
equal that measurement. A declaration of 32 bytes on a walk that measures
1310784 bytes is HTTP 400, even though both values are within 1 GiB.
A tree-shape or budget failure, including this mismatch, is HTTP 400.
An MPS error on the sweep trace stays HTTP 500. The planner never emits a peak
above 1 GiB; core is the only party that checks a dispatched peak against it.
No party compares the peak with the node's memory budget: acceptance remains
`max_mps_qubits` (§1).

Core also rejects, as HTTP 400, a tree on a non-scalar task, a tree with
assignments, a tree with `mps_time_split` set, a tree whose `qubit_count`
differs from `original_qubit_count`, and a non-identity `mps_site_order`.
The exact tree's own site order must be empty. An explicit identity `0..n` is
normalized to empty before that check, so both forms are accepted.

## 5. Wire

On the signed dispatch ([`p2p-protocols.md`](p2p-protocols.md)), the tree is
appended only when present, after `mps_time_split`:

```
contraction_tree_len   uint32 BE
contraction_tree       []byte    (the JSON in §2)
```

A dispatch with no tree has neither field, so its bytes match the layout from
before this suffix. A tree task has `mps_time_split` zero, so that uint32 is
also absent and the suffix begins at `contraction_tree_len`. An older node,
which stops at `security_level` or at `mps_time_split`, rejects the signature
of a tree task and verifies every other dispatch.

The node checks that signature and copies `contraction_tree` onto
`POST /compute`. It does not build another tree. Omitting the field on
`/compute` keeps today's `contract_slice` path.

## 6. Quote and gas

`POST /api/v1/economy/quote` gains no fields. Coefficients stay
`α · VRAM_MiB + β · GateCount + γ · TraceRows` with `α = β = γ = 1`.

For a scalar whose tree fits, `estimated_slices` is 1 and `VRAM_MiB` is
`⌈peak_bytes / 2^20⌉`, which is 0 when the peak is 0. The time-split bond
override does not apply. Settlement of that sub-task uses the same peak, so
the escrow and the payment see one workspace.

A scalar with no tree keeps `⌈N · χ² · 32 / 2^20⌉` and, when a time split is
planned, the boundary bond from [`mps-scalar.md`](mps-scalar.md) §5.5.

## 7. Proof

The leaf STARK is the unitary AIR of the MPS sweep ([`zk-STARK.md`](zk-STARK.md)).
`proof_scope` stays empty. There is no overlap tail and no new auxiliary
segment. The sweep may truncate at `mps_max_bond_dim`. That truncation does not
change the exact amplitude this path returns, and it is not a reason to drop the
tree. Where `χ` is below the bond the circuit needs, that exact amplitude
differs from the value the MPS path returns. That difference is why the tree is
attached.

The AIR does not bind the exact amplitude to the circuit. Quorum agreement on
the snapped amplitude is what clients can rely on. This is the same kind of
trust as a time-split amplitude, and it is not a proof of a general circuit.

## 8. Out of scope

- A search over contraction orders, and any cotengra-shaped planner.
- Born-rule or expectation values on this tree. Those modes stay dense, host
  ≤ 20 qubits and zk ≤ 16.
- Binding the tree to the circuit inside the AIR.
- Making WebGPU the default.
- Comparing `peak_bytes` with the node's memory budget. Acceptance stays
  `max_mps_qubits` (§1). The planner's cap and core's check are separate from
  that admission.
- Rewriting [`circuit-payload.md`](circuit-payload.md). A scalar `RESET` is
  ignored here and by the MPS sweep (§3). That document still describes `RESET`
  as a projection onto `|0⟩`.
