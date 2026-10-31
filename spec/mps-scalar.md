# MPS scalar execution

- **Status:** Working spec — scalar slice contract
- **Tier:** B (implementation snapshot)
- **Verified:** 2026-11-01
- **Verified against:** uncommitted `feature/contraction-tree` in `wqc-orchestrator`, `wqc-node`, and `wqc-core` (tree handoff). MPS path prior snapshot: `wqc-orchestrator@220d17f` `wqc-core@7c721e2` `wqc-node@096dcf4` `wqc-stark-engine@12bfb3c`
- **Audience:** Implementers of the scheduler, node and core; reviewers of quorum and proof claims
- **Related:** [`circuit-payload.md`](circuit-payload.md) (output modes, determinism), [`contraction-tree.md`](contraction-tree.md) (scalar with an exact tree), [`p2p-protocols.md`](p2p-protocols.md) (wire layouts), [`economics.md`](economics.md) (fees and escrow), [`zk-STARK.md`](zk-STARK.md) (proof format), `wqc-core/doc/tn-engine.md` (module layout, WebGPU, env vars)

## Scope

This document is the contract for **how a `statevector_scalar` slice is executed as a
matrix-product-state (MPS) contraction**, and what each party may rely on:

- which slices the orchestrator accepts, branches, splits in time, or rejects (§3–§5),
  including quote ceilings and `Start` abort on a saturated estimate;
- what a node must return so that quorum can compare results (§6);
- what the proof does and does not certify (§7).

It does **not** describe the module layout, environment variables, or the WebGPU backend of
`wqc-core`; those are implementation notes in `wqc-core/doc/tn-engine.md`. Fee formulas
live in [`economics.md`](economics.md); the signed dispatch bytes live in
[`p2p-protocols.md`](p2p-protocols.md).

## 1. Execution paths by output mode

| Output mode | Path | Width limit |
|-------------|------|-------------|
| `statevector_scalar` whose exact tree fits (empty `output_mode` is normalized to this mode) | Exact contraction, `⟨0…0\|ψ⟩` ([`contraction-tree.md`](contraction-tree.md)) | Core: 26 open legs and a live peak of at most 1 GiB. Node acceptance stays `max_mps_qubits`. One full-register slice |
| `statevector_scalar` with no tree | MPS contraction, `⟨0…0\|ψ⟩` | memory budget `N · χ² · 32` bytes (§2) |
| `expectation`, `sample_counts` | MPS sweep, then projection to a dense statevector | host `contract_to_statevector` requires `N ≤ 20`; the Born STARK path stops at 16 qubits |

Submit normalizes an empty `output_mode` to `statevector_scalar` before the task
is stored. Quote already treats that empty mode as `statevector_scalar`, so a
circuit there can carry a tree. No dispatch carries an empty mode: a trap
sub-task copies the parent's mode. A trap is still built from a different
circuit, so it does not carry the parent's tree. The sections below are the
no-tree scalar. Expectation and sample slicing keep the dense compact width, and
keep branching down to the 20-qubit limit.

## 2. Memory and bond dimension

- **Workspace.** An MPS of `N` sites at bond dimension `χ` takes about `N · χ² · 32` bytes
  (vs `2^N · 16` dense). At the default `χ = 128`, 1 GiB holds about 2048 sites.
- **Effective χ** is `min(WQC_MPS_MAX_BOND_DIM of the core, mps_max_bond_dim of the task)`.
  The orchestrator sends `mps_max_bond_dim`; `0` means the default (128).
- **Two-site matrix.** A 2-qubit gate contracts two sites into a `2χ × 2χ` matrix; at
  `χ = 128` the side is 256. This bound is why the time-split budget in §5 is chosen as
  `16 × 16`.
- **Bid field.** A node advertises `max_mps_qubits`, the compact width that fits a `χ = 128`
  MPS in its memory budget. It travels as an unsigned JSON field next to the signed bid
  ([`p2p-protocols.md`](p2p-protocols.md)). A bid without it falls back to
  `max_qubit_capability`.
- **`max_qubit_capability` keeps its dense meaning.** It is used to stop expectation and
  sample slicing, to pick idle capable nodes, and to recover the dense memory budget in
  `RecommendMpsMaxBondDim`. Do not read the MPS width into it.
- A node that overstates `max_mps_qubits` is still bounded by the core's own memory check.

## 3. Site order and cut width

A scalar MPS is a chain, and the order of qubits along that chain decides its bond
dimensions.

- **Parent order.** The orchestrator computes `ComputeMpsSiteOrder` once for the parent
  circuit. Its width is measured on that order.
- **Compact order.** After qubits are fixed by slicing, the survivors keep the parent order
  and are renumbered (the same renumbering as the pruned circuit). The orchestrator sends
  that order as `mps_site_order`; the node does **not** recompute one. An empty order means
  identity.
- **Cut width.** For one cut in the order, let `w` be the number of two-qubit gates that
  cross it and `m` the number of sites on its smaller side. The cut's width is
  `2^min(w, m)`. A one-site side stays at width 2 however many gates touch that qubit. The
  circuit's width is the maximum over cuts.
- **Non-adjacent gates.** A two-qubit gate on sites that are not neighbours is applied by
  sliding one site next to the other with swaps, applying the gate, and undoing the swaps.
  The site order is restored afterwards. A `CCNOT` is decomposed into such gates.

## 4. Scheduling a scalar parent

A non-empty scalar whose greedy exact tree fits is one slice and is not branched,
including when the walk below would hit a ceiling
([`contraction-tree.md`](contraction-tree.md)). This section is the schedule when
that plan returns no tree, and when the circuit is empty.

A scalar slice is dispatched as one slice when both hold:

1. its compact width does not exceed the pool's allowed MPS width (derived from the bids'
   `max_mps_qubits`, §2); and
2. its cut width is at most `χ`, or a time split fits (§5).

Otherwise the orchestrator branches by fixing one qubit (two child slices, `e_<k> ∈ {0,1}`):

- **Bond stop.** While the cut width exceeds `χ`, the branch qubit is chosen on the smaller
  side of the widest cut.
- **Memory stop.** When only memory is short, the lowest free wire is fixed. No min-cut is
  run.
- **Time split before a bond stop.** When the cut width exceeds `χ` and no qubit is fixed
  yet, the orchestrator tries a time split (§5). If a plan exists, the parent is one slice;
  otherwise it branches as above.

Quote and submit estimate the slice count with the same rules:

| Case | Estimated slices |
|------|------------------|
| Cut width ≤ χ and compact width ≤ pool width | 1 |
| Cut width ≤ χ, width above the pool width | `2^(q − pool width)` |
| Cut width > χ and a time split fits (§5) | 1 |
| Cut width > χ and no time split fits | 2 (and more as the walk continues) |

The estimate is **rejected** (quote and submit) when any of these ceilings is reached:

| Ceiling | Value |
|---------|-------|
| Estimated slices | `2^30` |
| Branch-walk nodes | 4096 |
| Gates | 100000 |
| Qubits | 4096 |

**Quote.** `POST /api/v1/economy/quote` accepts optional `circuit` and `output_mode`
(same shapes as submit). Empty `output_mode` is `statevector_scalar`. With no circuit,
the stand-in width for a scalar is 2048 qubits (one `χ = 128` MPS in 1 GiB). With a
circuit whose exact tree fits, the estimate is one slice
([`contraction-tree.md`](contraction-tree.md)). Otherwise the estimate follows the
table above. A walk that hits a ceiling returns HTTP
400 ([`economics.md`](economics.md) §3.1).

**Submit / Start.** Submit rejects a saturated scalar before locking quorum. If the
scheduler still sees a saturated estimate at `Start`, it returns false and the submit
path calls `abortTask` (failed task meta + escrow finalize) so the client is not left
hanging.

## 5. Time split

A circuit whose cut width exceeds `χ` can still be exact if its depth is cut in half.
A nearest-neighbour brickwork of depth 16 has width 256 at its middle cut, but each half
(depth 8) has width 16.

### 5.1 Computation

Let `U = U₂ · U₁` with the gate list split at index `s` (`U₁` = gates `[0, s)`, `U₂` = gates
`[s, n)`).

- **Ket** `|ψ⟩ = U₁ |0…0⟩` is built by a normal MPS sweep.
- **Bra** `|φ⟩ = U₂† |0…0⟩` is built by sweeping the adjoints of `U₂` in reverse order.
  `S† = S·Z` and `T† = T³·Z` are written as existing gates.
- **Amplitude** `⟨0…0|U|0…0⟩ = ⟨φ|ψ⟩`, computed as an overlap contracted along the site
  order. The environment is the product of the two boundary bonds, at most `16 × 16 = 256`.

No tensor travels between nodes. Both MPS live in one core process.

### 5.2 Budget

| Constant | Value | Meaning |
|----------|-------|---------|
| `ScalarTimeSplitBond` | 16 | Largest final bond on either side |
| `ScalarTimeSplitSwapMargin` | 8 | Final-width cap when a half has a non-adjacent two-qubit gate or any `CCNOT` (swap slides can briefly need about twice the final cut) |
| Overlap environment | 256 | `ket_right × bra_right` per site |
| Run χ | the larger half width, raised to 16 when a half needs the margin | sent as `mps_max_bond_dim` |

A split is planned (`TimeSplitPlan`) only when:

- both halves' cut widths are at most the limit above;
- the slice has no fixed qubits (the split index is into the **unpruned** gate list, so a
  slice that already fixed a qubit stays on the width walk); and
- the circuit has at least two gates.

**Planner (`TimeSplitPlan`).** Left cutwidth is non-decreasing and right cutwidth is
non-increasing in the split index. The planner:

1. sets the active limit to 16, or to 8 if any gate in the **whole** circuit needs swap
   margin (a margin gate lands in exactly one half of every split);
2. binary-searches the smallest index whose right half is ≤ limit and the largest whose
   left half is ≤ limit (`O(n log n)` graph work — not an `O(n²)` scan of all indices);
3. if that window is empty, returns no plan; otherwise picks the index in the window
   nearest the midpoint (`n / 2`), clamped into the window;
4. evaluates run χ at that index (`timeSplitAt`).

It does **not** minimise χ inside the window. A depth-200 nearest-neighbour brickwork
(~4900 gates) that cannot fit must refuse well under a second on ordinary hardware.

### 5.3 Rejection, not truncation

For a split task the core **never truncates**. If a sweep needs a bond above `χ`
(a singular value above `1e-12` would be dropped), or the overlap environment would exceed
256, it returns an error (`mps bond exceeded chi`, or an environment error) with HTTP 500.
A single-sweep scalar still truncates at `χ`; it is exact only when its true bond stays
within `χ`.

### 5.4 Wire

`mps_time_split` is a `uint32` gate index appended to the dispatch signature **only when it
is non-zero** ([`p2p-protocols.md`](p2p-protocols.md)). An older node therefore verifies
ordinary dispatches, and rejects only time-split tasks. Ship order: stark-engine, then core
and node, then the orchestrator.

The node forwards the value to the core's `/compute` as `mps_time_split` (absent when 0).
The core accepts it only for `statevector_scalar`, with no `slice_assignments`, and
`0 < split ≤ gates`.

### 5.5 Cost

Fees follow [`economics.md`](economics.md): the scalar `VRAM_MiB` uses the **boundary** MPS
bond (the larger half), and the gate count is that of the whole circuit. A tree-carrying
scalar uses the tree peak instead ([`contraction-tree.md`](contraction-tree.md) §6).
Coefficients are unchanged.

## 6. Determinism and quorum

All nodes on a slice must return the same scalar after quantisation.

- **Snap.** The core snaps `real` and `imag` to a 1e-6 grid before hashing
  ([`circuit-payload.md`](circuit-payload.md) §4). Quorum compares the snapped values and
  `output_result_hash`, the SHA3-256 of the canonical amplitude JSON.
- **Same inputs.** Same `mps_site_order`, same effective χ, same `mps_time_split`, and the
  same adjoint construction. The orchestrator is the only party that chooses them.
- **Failure is an answer.** A task the plan should not have produced (bond or environment
  overflow) fails identically on every honest node: same HTTP 500 and message. Triage it as
  a **planning bug**, not an infrastructure fault.
- **Floating point.** Tensors are IEEE-754 `f64`. Agreement relies on the 1e-6 snap
  absorbing platform differences in rounding order.

## 7. What the proof certifies

A time-split scalar returns a normal leaf STARK plus an **overlap tail**.

### 7.1 Unitary AIR

The 11-column execution trace is unchanged ([`zk-STARK.md`](zk-STARK.md)). For a split task
the trace covers the ket sweep and, when its gates have Gate-level adjoints, the bra sweep.
The core reports which in `work_report.proof_scope`:

| Value | Meaning |
|-------|---------|
| `mps_time_split_halves` | Both sweeps are in the trace |
| `mps_time_split_first_half` | Only the ket sweep is traced |

This field is a hint from the node. **The orchestrator overwrites it** with
`proof_scope = mps_time_split` whenever it dispatched `MpsTimeSplit ≠ 0`, and never trusts
the node's value.

As for any scalar, the trace's STARK shadows 2 amplitudes. It does not bind the whole MPS.

### 7.2 Overlap tail

The proof transcript ends with:

```
_M31_OVERLAP_V1_  u32_le(payload_len)  OverlapSegment
```

`OverlapSegment` carries the qubit count (1…2048), the claimed amplitude, its digest, and
the ket and bra site tensors (`[left × 2 × right]`, `f64` complex pairs, bond ≤ 16).

The verifier:

1. rejects malformed counts and shapes before allocating (site counts must equal
   `qubit_count`; each tensor's value count must equal `left × 2 × right` and fit in the
   remaining bytes);
2. checks that the digest equals the digest of the claimed amplitude and, through the proof
   context, equals `output_result_hash`;
3. contracts the claimed sites in host `f64` (no fixed-point snap) and requires the result
   to match the claimed amplitude within `5e-6` (the published amplitude is on a 1e-6 grid);
4. requires open bonds to start and end at 1, and the environment to stay within 256.

The orchestrator requires the overlap tail whenever `MpsTimeSplit ≠ 0`, and runs the
verification inside `VerifyProof` (FFI).

### 7.3 What is **not** certified

The overlap tail checks that the **claimed MPS tensors are consistent with the claimed
amplitude**. It does **not** bind those tensors to the circuit, and the unitary AIR does
not bind the amplitude to the trace's end state. A dishonest prover can choose tensors that
contract to any amplitude of modulus at most 1.

Therefore, for a time-split scalar, **the amplitude is protected by quorum agreement, not
by the proof alone**. Do not describe it as a verified general-circuit result. Binding the
circuit to the full MPS is an open gap.

### 7.4 Size and verification cost

Each site adds up to `2 × (16 · 2 · 16) × 16 = 16 KiB` (ket and bra) to the proof. Measured
tails: 0.54 MB at 50 qubits and 4.84 MB at 400 qubits (depth-16 brickwork, `χ = 16`). The
orchestrator's verifier accepts proofs up to 32 MiB.

## 8. Failure modes

| Symptom | Cause | Class |
|---------|-------|-------|
| `mps bond exceeded chi` (HTTP 500, all nodes) | The sweep needs a bond above effective χ | Planning bug if the plan allowed it |
| Overlap environment above 256 | Boundary bonds above 16 on both sides | Planning bug |
| `overlap segment failed AIR verification before prove` | The claimed amplitude does not match the claimed tensors | Core bug |
| Orchestrator: `overlap tail required for mps_time_split subtask` | The node omitted the tail | Misbehaving or old node |
| Older node rejects dispatch signature | `mps_time_split` set, or a contraction tree is attached, and the node does not know that suffix | Rollout order |
| Quote / submit: work-ceiling rejection | Estimate hit `2^30` / walk / gate / qubit caps (§4) | Client or circuit too large |
| Task failed: `scalar slice estimate exceeded the work ceiling` | `Start` refused a saturated estimate | Same as above; escrow finalized |

## 9. Open gaps

A scalar whose greedy tree fits is specified in [`contraction-tree.md`](contraction-tree.md).
This document is the scalar that has no tree. The following remain out of scope:

- **Circuit-to-MPS binding.** See §7.3. Amplitude for a time-split scalar stays quorum-backed.
- **Leaf-compose proofs.** A Born or trajectory leaf-composition proof is verified on its
  own path and does not reach the overlap check. The orchestrator's tail requirement only
  tests that the marker is present.
- **Proof size.** At 2048 sites with every bond at 16, the tail is just over the 32 MiB
  verifier limit.
- **Non-scalar modes.** Expectation and sample counts still go through a dense statevector
  (≤ 20 qubits); Born on MPS is not implemented.
- **Planner scope.** No search over contraction orders, and WebGPU is not the default.
