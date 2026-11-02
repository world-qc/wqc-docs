# Exact contraction tree

- **Status:** Working spec — scalar tree contract (state tree and network tree)
- **Tier:** B (implementation snapshot)
- **Verified:** 2026-11-03
- **Verified against:** `wqc-orchestrator@6662024` `wqc-node@e7bd9f6` `wqc-core@dd61e55` on `feature/network-contraction`. Prior snapshot: `wqc-orchestrator@206493a` `wqc-node@e81930c` `wqc-core@43c69c0` on `feature/contraction-tree`
- **Audience:** Implementers of the scheduler, node, and core; reviewers of quorum, fees, and proof claims
- **Related:** [`mps-scalar.md`](mps-scalar.md) (the path with no tree), [`economics.md`](economics.md) (fees), [`p2p-protocols.md`](p2p-protocols.md) (signed bytes), [`zk-STARK.md`](zk-STARK.md) (what the proof binds), [`architecture-current.md`](architecture-current.md) (who dispatches)

## Scope

This document is the contract for a `statevector_scalar` task whose orchestrator
attaches an **exact contraction tree**. There are two kinds:

- a **state tree** contracts gates into state tensors in circuit order (§3.1);
- a **network tree** (`"kind":"network"`) closes every wire with `⟨0|` and
  contracts the whole circuit as one tensor network, in any order (§3.2).

It covers:

- when a tree is attached, which kind, and when the task stays on the MPS path (§1);
- the JSON the signature carries (§2);
- the plans that produce it (§3);
- what core executes, and what it rejects (§4);
- the signed suffix (§5);
- the quote and the gas inputs (§6);
- what the proof does not certify (§7).

A dispatch with no tree is [`mps-scalar.md`](mps-scalar.md). Expectation and
`sample_counts` never carry a tree. The node does not build a plan. The
network order comes from a bounded, seeded greedy search (§3.2). There is no
cotengra dependency. WebGPU stays off by default. `max_qubit_capability` is
unchanged.

## 1. When a tree is attached

The orchestrator plans both kinds at quote, at submit, and at `Start`, with the
same rules each time (§3). When both fit, it attaches the one with the smaller
`peak_bytes`; on a tie it keeps the state tree. The scheduler keeps the `Start`
tree and does not plan again while it dispatches. The node does not plan.

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

Both planners refuse a tree above 1 GiB, and core checks the declared and
measured peak against that figure (§4). The quote uses that peak only as
`VRAM_MiB`. A node accepts the task when `qubit_count` is within its
`max_mps_qubits` and does not read `peak_bytes`. A 25-qubit star gets a network
tree of 3488 bytes (its state tree would be 805306400 bytes) and is inside that
width for a node whose `max_mps_qubits` is 128. A 4096-qubit register of one
`H` per wire keeps its state tree of 131072 bytes (the network tree is 131168)
and is refused by a node whose `max_mps_qubits` is 2048.

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

Examples, nearest neighbour unless noted. Peaks are `peak_bytes`.

| Circuit | State tree | Network tree | Attached | Quote |
|---------|-----------:|-------------:|----------|-------|
| 16q depth-8 RY+CNOT brickwork | 1310784 | 22528 | network | 1 slice, `VRAM_MiB` 1 |
| 20q all-to-all CNOT clique | 25165856 | 1277952 | network | 1 slice. The cutwidth walk of the same circuit remains 32 |
| 50q depth-8 RY+CNOT brickwork | does not fit | 95488 | network | 1 slice |
| 50q depth-16 RY+CNOT brickwork | does not fit | 17367040 | network | 1 slice. Without the tree it would time-split at boundary bond 16 |
| 50q, one `H` on each wire | 1600 | 1696 | state | 1 slice |
| 1D 30q depth-32 RY+RZ+CNOT brickwork | does not fit | does not fit | none | the cutwidth walk (256 slices) |

Wherever a time split fits (boundary bond at most χ=128), a network tree has
fitted in every circuit measured so far, so the time split and the cutwidth
walk are now the path for circuits no tree can hold.

## 2. IR

The signed JSON is `encoding/json` of this object. Keys are in this order.
Unset fields are omitted. Alphabetized keys do not verify.

```json
{"nodes":[{"op":"contract","left":{"ket0":0},"right":{"gate":0}}],"peak_bytes":32}
```

That object is the state tree of `H` on wire 0. `peak_bytes` is 32. The network
tree of the same circuit is:

```json
{"kind":"network","nodes":[{"op":"contract","left":{"ket0":0},"right":{"gate":0}},{"op":"contract","left":{"bra0":0},"right":{"node":0}}],"peak_bytes":128}
```

| Object | Keys, in order | Meaning |
|--------|----------------|---------|
| tree | `kind`, `nodes`, `peak_bytes` | `kind` is `network` or absent (state tree). Contractions, then the declared live peak in bytes |
| node | `op`, `left`, `right` | `op` is `contract` |
| operand | one of `ket0`, `gate`, `node`, `bra0` | Parent wire of a `\|0⟩` leaf, index in the parent circuit, earlier node, or parent wire of a `⟨0\|` leaf (network only) |

`gate` counts every gate, including `MEASURE`, `RESET`, and `IF`, which are not
themselves nodes. A circuit with no unitary is `{"nodes":[],"peak_bytes":0}`.
`site_order` is not a field. Wire numbers are the parent circuit's.

A state tensor is a dense array of open parent wires. Bit `i` of the index is
`wires[i]` after those wires are sorted ascending. One complex amplitude is 16
bytes, so a tensor of `L` legs is `16 << L` bytes. A `ket0` leaf has one leg
(32 bytes).

In a network tree a node may take any two live tensors, leaves or nodes, in any
order. Every leaf is used once and the root is a scalar with no legs. The
leg layout is in §3.2.

## 3. Planners

Both planners skip the same gates and accept the same unitaries. A unitary is
`H`, `X`, `Y`, `Z`, `S`, `T`, `RX`, `RY`, `RZ`, `CNOT`, `CZ`, or `CCNOT`. Any
other type, a duplicate wire, an out-of-range wire, zero qubits, more than 4096
qubits, or more than 100000 gates yields no tree of either kind. Both refuse a
tensor of more than 26 legs and a declared peak above 1 GiB (`2^30` bytes).

### 3.1 State tree

Gates are considered in circuit order. `MEASURE`, `RESET`, and `IF` are skipped.
The scalar sweep ignores those gates, so a `RESET` on a scalar circuit does not
change the amplitude. The body of an `IF` is not pulled out.

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

### 3.2 Network tree

**Network.** Wire `w` starts at a `ket0(w)` leaf, `[1, 0]`, and ends at a
`bra0(w)` leaf, `[1, 0]`. A unitary on `k` wires is a leaf with `2k` legs:
its inputs in argument order, then its outputs in argument order. `MEASURE`,
`RESET`, and `IF` are skipped as in §3.1. Edges are numbered as follows: edge
`w` leaves `ket0(w)`; each unitary, in circuit order, numbers its outputs next,
in argument order; `bra0(w)` holds the last edge of wire `w`. A wire no gate
touches is `ket0(w)` against `bra0(w)`, a factor of 1. The tree names leaves
only. Core numbers the edges the same way.

**Layout.** Leg `p` of a tensor is bit `p` of its index. A gate leaf's entry is
`input | output << k`, where `input` and `output` are `k`-bit indices in
argument order. Before a contraction, each operand is reordered so the shared
edges come first, in the left operand's order, then its own free legs. The
result keeps the right operand's free legs, then the left's.

**Peak.** A leaf is built when a node takes it. A reordered operand is a copy
made while the original is still allocated. At each node, the planner counts
the live node results, both operands, and the larger of the result and each
operand that needs reordering. The declared peak is the largest such sum. A
result above 26 legs, or a sum above 1 GiB, ends that order.

**Plain greedy.** Leaves take ids in this order: `ket0` by wire, unitary gates
by circuit index, then `bra0` by wire. Node `i` takes id `leaves + i`. Among
pairs of live tensors that share an edge, the plan contracts the pair with the
smallest `2^|result| − 2^|left| − 2^|right|`, then the smaller ids. The smaller
id is the left operand. When no pair shares an edge, every live tensor is a
scalar, and the two smallest ids join until one is left.

**Search.** After the plain greedy, up to 256 seeded passes weigh the operands
differently, `8·2^|result| − w·(2^|left| + 2^|right|)` with `w` in 0–16, and
scale each pair's cost by a factor drawn from `[1, 1 + noise)`. The seed is the
SHA3-256 of every leaf's leg count and legs, so angles do not change the tree.
Among the orders that fit, the plan keeps the fewest flops
(`Σ 2^|legs of the union of both operands|`, shared edges counted once), then
the smaller peak, then the earlier pass. Every bound is a count, never the
clock: a pass stops once its flops pass the best so far; the search stops when
the best tree's flops fall below 10^4 per leaf searched so far; and the passes
together see at most 600000 leaves. Quote, submit, and `Start` therefore build
the same tree. When no order fits, there is no network tree.

The orchestrator keeps up to 64 results in memory (at most 2^18 tree nodes in
all) and drops the least recently used. The cache key hashes each leaf's kind
and index as well as its legs: two circuits whose skipped gates sit in
different places have the same legs, and so the same tree shape, but their
trees name different gate indices.

Measured on nearest-neighbour RY+RZ+CNOT circuits (the search time is the
orchestrator's):

| Circuit | Plain greedy peak | Searched peak | Search |
|---------|------------------:|--------------:|-------:|
| 1D 50q depth-8 RY+RZ+CNOT | 95488 | same tree | 1 ms |
| 1D 50q depth-16 RY+RZ+CNOT | 71.3 MB | 9.0 MB | 26 ms |
| 1D 30q depth-24 RY+RZ+CNOT | does not fit | 326 MB | 0.85 s |
| 2D 7×7 depth-8 RY+RZ+CNOT | does not fit | 306 MB | 0.39 s |
| 1D 30q depth-32 RY+RZ+CNOT | does not fit | does not fit | 1.1 s |

## 4. Executor

Core contracts the tree once. For a state tree, the amplitude is `⟨0…0\|ψ⟩`: the
product of the `\|0…0⟩` entry of each live state tensor. For a network tree it
is the root scalar. Core then runs the ordinary MPS sweep so the prover still
has rows (§7).

Validation, before any tensor is allocated, checks the circuit, an identity
site order, and that a peak is declared and at most 1 GiB. It then walks the
tree without data. The walk checks leg count and measures the live peak. For a
state tree it checks that each gate is consumed in circuit order. For a network
tree it builds the network as in §3.2, checks that each leaf is used once and
the root has no legs, and measures the peak by the rule in §3.2. The declared
peak must equal that measurement. The contraction checks it again. A declaration of 32 bytes on a walk that measures
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

A node that predates the network tree decodes it without `kind` and `bra0`,
re-encodes different bytes, and rejects the signature of every network tree
task. Network trees therefore ship after the node (no capability bit: there are
no external miners yet).

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

- Slicing a network tree's edges when no order fits in 26 legs or 1 GiB. Such
  a circuit stays on the MPS path (§1).
- Any cotengra-shaped planner (hypergraph partitioning, simulated annealing
  over trees).
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
