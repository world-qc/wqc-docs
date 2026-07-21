# Zero-Knowledge STARKs for Trustless Distributed Quantum Simulation

**A protocol specification for the World Quantum Computer (WQC) cryptographic proof engine**

---

## Abstract

The World Quantum Computer (WQC) replaces energy-intensive, nondeterministic hash mining with *Deterministic Proof of Useful Work* (D-PoUW): workers contract slices of quantum circuits and produce cryptographically verifiable proofs of correct execution. This document specifies the zero-knowledge STARK (zk-STARK) subsystem that makes that claim enforceable. We describe the public-input binding that anchors each proof to a dispatched task, the Algebraic Intermediate Representation (AIR) for unitary execution traces, auxiliary proofs that bind Born-rule sampling and mid-circuit measurement trajectories, and a binary composition tree with an aggregation STARK that reduces root verification to effectively constant cost. The design is transparency-first (no trusted setup), field-native over Mersenne31 with Circle polynomial commitment, and engineered so that verification cost grows slowly while proving cost—and therefore useful quantum work—absorbs the economic load of consensus.

---

## 1. Introduction

### 1.1 Background: from Fortress Computing to a Neural Swarm

Quantum computation is presently concentrated in facilities that resemble digital fortresses: scarce machines, closed APIs, and institutional gatekeepers. That concentration is not only an access problem; it is a *trust* problem. A client who outsources a molecular energy estimate or an optimization landscape to a third party has, in the classical model, almost no way to know whether the returned histogram was simulated honestly, truncated early, or fabricated to fit a preferred narrative.

At the same time, blockchain systems have demonstrated that global consensus without a central arbiter is possible—but at the price of *Proof of Work* (PoW) whose useful output is often zero. Conventional PoW converts energy into entropy for the sake of Sybil resistance. From a thermodynamic and social perspective, that bargain is increasingly indefensible: the planet pays for hash collisions while scientific and industrial workloads remain hungry for cycles.

WQC’s premise is that those two crises share a solution. If the work that secures a ledger is *itself* quantum-circuit simulation—partitioned across commodity GPUs and unified-memory devices, and accompanied by succinct mathematical proofs—then security spend becomes scientific throughput. Tens of thousands of worker nodes form a *Neural Swarm* that cooperatively contracts tensor-network representations of circuits too large for any single machine’s statevector, yet each contribution remains independently checkable.

### 1.2 The verification bottleneck

Distributed simulation alone is not enough. An orchestrator that re-executes every slice would recreate the very centralization WQC seeks to abolish; an on-chain verifier that inspects gigabyte traces would never settle. The classical cryptographic answer is an *argument of knowledge*: a short string $\pi$ that convinces a verifier that a claim is true without replaying the computation.

For quantum simulation specifically, three additional difficulties arise:

1. **Scale.** Statevectors grow as $2^n$. WQC therefore *slices* circuits (tensor-network cut / idle-wire assignment) and proves per-slice contractions rather than full amplitudes wherever possible.
2. **Polymorphism of results.** Clients need amplitudes (`statevector_scalar`), shot histograms (`sample_counts`), or Pauli expectations (`expectation`). Sampling appears stochastic; without a bound seed and Born-rule commitment, remote histograms cannot be reconciled across dishonest workers.
3. **Dynamic circuits.** Mid-circuit `MEASURE`, `RESET`, and classically controlled gates destroy the purely unitary model assumed by naive execution STARKs. Unitary segments and measurement trajectories must be proved separately and cryptographically linked.

### 1.3 Why zk-STARKs

Among succinct proof systems, STARKs (*Scalable Transparent Arguments of Knowledge*) are particularly well matched to WQC’s threat and deployment model:

| Property | Relevance to WQC |
| --- | --- |
| **Transparency** | No ceremony, no toxic waste. Anyone can verify proofs produced by anonymous workers. |
| **Hash-based security** | Avoids elliptic-curve pairings and long-term pairing assumptions; FRI relies on collision-resistant hashing and coding theory. |
| **Scalability** | Proving is quasi-linear in the trace; verification is polylogarithmic—exactly the asymmetry needed for D-PoUW. |
| **Air-native circuits** | Quantum gate transitions map naturally onto Algebraic Intermediate Representations over finite fields. |
| **Post-quantum trajectory** | Hash-based proof systems are among the leading candidates for quantum-safe arguments. |

WQC implements STARKs over the **Mersenne31** field using Polygon **Plonky3** with **Circle PCS**, with an earlier embedded-trace profile retained for auditing. Zero-knowledge extensions (`DistributionAir`, trajectory marginal / per-shot Bernoulli AIRs) further hide dense probability tables and event streams while still binding claimed sample counts to a deterministic seed.

### 1.4 Contributions of this specification

This document consolidates the WQC STARK specification into a single narrative. It covers:

* Public-input binding and the roles of prover (worker), verifier (orchestrator), and compose nodes;
* Unitary execution traces and AIR constraints over a gate alphabet including mid-circuit measurement;
* Distribution and trajectory binding for deterministic sampling;
* Recursive binary composition with aggregation STARKs (native verification tree, v4 `AggregationAir` digest attestation, and v6 `RecursiveAggregationAir` with leaf/agg PCS bundles and in-circuit out-of-domain checks);
* Soft resource caps that delimit the present noiseless `sample_counts` regime;
* Operational boundaries and ongoing protocol optimization (host verification parameters, multi-chunk quotient structures, and proof footprint optimization).

Appendices B and C retain binary-level layouts for implementers; the present paper is the conceptual and protocol SSOT. See also the WQC whitepaper (§3.3–3.4) for economic motivation and recursive-aggregation vision.

---

## 2. System model

### 2.1 Actors

* **Client.** Submits a circuit under an output mode, funds escrow when billing is enabled, and receives a result plus a root proof.
* **Orchestrator.** Cuts the circuit into slices, runs a bid / quorum session, dispatches work, verifies leaf and compose proofs, and seals a manifest root.
* **Worker node.** Contracts a slice (via a local `wqc-core` instance), emits a STARK proof bound to the assigned public inputs, and returns the result over P2P.
* **Aggregator / finalizer.** Builds the compose tree, optionally appends an aggregation STARK tail, and publishes `proof_root_hash` / `root.bin`.

### 2.2 Assets to protect

A malicious worker may attempt: (i) substituting a different circuit or slice; (ii) returning a fabricated amplitude or histogram; (iii) front-running another node’s result; (iv) claiming Born-rule consistency without respecting the seed; (v) forging mid-circuit measurement outcomes. Public-input binding plus AIR / FRI checks are designed to make each of (i)–(v) detectable at verification time (subject to the resource caps in §9).

### 2.3 Output modes and proof obligations

| Mode | Primary leaf claim | Auxiliary binding |
| --- | --- | --- |
| `statevector_scalar` | Unitary contraction of a scalar amplitude | — |
| `sample_counts` (terminal) | Unitary execution of the measured subcircuit | Born distribution + deterministic sampling |
| `sample_counts` (mid-circuit) | Unitary segments between measures | Trajectory events + optional zk marginals / shots |
| `expectation` | Algebraic expectation over the post-contraction state | (outside distribution STARKs; result hash still bound) |

---

## 3. Preliminaries

### 3.1 Algebraic Intermediate Representation (AIR)

An AIR expresses computational integrity as polynomial constraints over a rectangular *execution trace*. Rows index time; columns hold registers (amplitudes, gate selectors, control flags). A valid proof attests that there exists a low-degree trace satisfying all constraints at every row (outside a quotient vanishing set), committed via a polynomial commitment scheme and opened with FRI.

### 3.2 Field and PCS

Production leaf proofs (transcript v2) use:

* **Base field:** Mersenne31 ($\mathbb{F}_p$, $p = 2^{31}-1$).
* **Commitment:** Circle PCS inside Plonky3.
* **Encoding:** postcard serialization of `p3_uni_stark::Proof`.

An earlier profile (v1) embeds the floating-point trace and asks the verifier to re-expand AIR columns and recompute a global constraint sum—useful for debugging, but not the scalability path.

### 3.3 Notation

Let $\pi$ denote a proof artifact, $\mathsf{PI}$ the public-input vector, and $H$ the SHA3-256 digest function. Digests appear either as raw 32-byte hashes or as 64-character ASCII hex strings inside transcripts. String fields in binary formats are NUL-terminated.

---

## 4. Architecture overview

```
                    ┌─────────────────────────┐
  Client submit ──► │       Orchestrator      │
                    │  cut · bid · verify ·   │
                    │  compose · seal root    │
                    └───────────┬─────────────┘
                                │ dispatch (P2P)
           ┌────────────────────┼────────────────────┐
           ▼                    ▼                    ▼
      Worker / Core        Worker / Core        Worker / Core
      π_slice (v2)         π_slice (v2)         π_slice (v2)
           │                    │                    │
           └───────── compose tree (v3) ─────────────┘
                                │
                     RecursiveAggregationAir (v6)
                     + AggregationAir (v4)
                                │
                           π_Root (O(1) verify)

```

**Transcript versions.**

| Version | Marker | Mechanism |
| --- | --- | --- |
| v1 | `_M31_QUANTUM_AIR_V1_` | Embedded trace; recomputed AIR sum |
| v2 | `_M31_PLONKY3_STARK_V2_` | Plonky3 FRI STARK over Circle PCS |
| v3 | `_WQC_COMPOSE_V3_` | Binary child proofs + optional aggregation tail (v4 / v6) |

Auxiliary markers attach to unitary bodies for sampling circuits (distribution, Born zk, trajectory, trajectory zk, aggregation). A comprehensive marker table appears in Appendix A.

**Verification flow (summary).** Detect the marker; check public-input binding; run the version-specific verifier; for `sample_counts`, additionally verify that the deterministic sampling pipeline reproduces the claimed output hash.

---

## 5. Public inputs

Every leaf proof binds a *StarkContext*:

| Field | Required | Meaning |
| --- | --- | --- |
| `circuit_id` | yes | Hash of the pruned circuit subgraph |
| `sub_task_id` | yes | Unique sub-task identifier |
| `node_id` | yes | Proving worker identity |
| `slice_id` | yes | Binary path in the tensor-network / idle-wire tree |
| `output_hash` | yes | SHA3-256 of the result payload (scalar or canonical counts JSON) |
| `terminal_statevector_digest` | optional | Links unitary terminal state to Born / trajectory claims |
| `measurement_spec_hash` | optional | SHA3-256 of canonical measurement-spec JSON; transcript prefix `MSH1` |

Binding these fields prevents a proof from migrating across tasks or slices: the orchestrator rejects proofs whose $\mathsf{PI}$ disagrees with the dispatched announcement and returned payload.

Whitepaper notation often writes

$$\mathsf{PI} = \{\,\texttt{circuit\_id},\ \texttt{sub\_task\_id},\ \texttt{node\_id},\ \texttt{slice\_id},\ \texttt{output\_result\_hash}\,\}$$

with the optional digests above as Phase-C extensions for sampling and interop.

---

## 6. Unitary execution proofs

### 6.1 Trace geometry

The prover records an execution trace of width $\texttt{TRACE\_WIDTH} = 11$ floating-point columns per row:

| Index | Symbol | Role |
| --- | --- | --- |
| 0–3 | $v_0^{\mathrm{re}}, v_0^{\mathrm{im}}, v_1^{\mathrm{re}}, v_1^{\mathrm{im}}$ | Two complex amplitude registers |
| 4 | $\texttt{gate\_id}$ | Gate opcode |
| 5 | $\texttt{target\_qubit}$ | Target index |
| 6–7 | $\texttt{ctrl\_active}^{(\ast)}$ | Control activation flags |
| 8–9 | $\texttt{ctrl\_qubit}^{(\ast)}$ | Control qubit indices |
| 10 | $\texttt{transition\_link}$ | Continuity to the next linked row |

**Row pattern.** Each active gate contributes a *pre-gate* row (parameters set, amplitudes before the operator) and a *post-gate* row (`gate_id = 0`, amplitudes after). A terminal boundary row ends the segment with $\texttt{transition\_link} = 0$.

### 6.2 Gate alphabet

| `gate_id` | Gate | Notes |
| --- | --- | --- |
| 0 | NONE | Post-gate / terminal |
| 1 | H | Hadamard |
| 2–4 | X, Y, Z | Pauli |
| 5–7 | RX, RY, RZ | Parameterized rotations |
| 8–10 | CNOT, CZ, CCNOT | Controlled gates |
| 11 | MEASURE | Trajectory branch; breaks amplitude continuity |
| 12 | IDLE | Identity on amplitudes |

### 6.3 Expanded AIR and constraints

Before FRI, the prover expands the 11 columns into 21 AIR columns by adjoining one-hot gate selectors derived from `gate_id`. Constraints enforce:

1. **Amplitude continuity.** When $\texttt{transition\_link} = 1$, linked registers agree across the adjoining row boundary for the same target.
2. **Gate semantics.** Each active opcode imposes the corresponding complex-linear map on $(v_0, v_1)$ (Hadamard, Pauli / rotation action, controlled flips / phases, Toffoli, idle).
3. **Selector consistency.** Exactly one selector is active; it matches `gate_id`.
4. **Control consistency.** When a control flag is active, the indexed control wire participates in the gate law.
5. **Boundary.** Terminal amplitudes match the values committed in the proof header (v1) or the reconstructed public claim (v2).

MEASURE rows deliberately waive unitary continuity: measurement is handled by the trajectory subsystem (§7).

### 6.4 Transcript profiles

**v1 (embedded).** After $\mathsf{PI}$ strings, the transcript carries `trace_rows`, $11\times\texttt{trace\_rows}$ little-endian `f64` values, an `air_sum` that must equal zero after re-expansion, and four `u32` fixed-point boundary components ($2^{30}$ scaling).

**v2 (Plonky3).** After $\mathsf{PI}$, a `u32` length prefixes a postcard-encoded FRI proof. The verifier reconstructs the AIR from the same execution inputs rather than trusting an embedded float trace. Auxiliary distribution / trajectory segments may follow the unitary body.

---

## 7. Distribution and trajectory binding

For `sample_counts`, correctness means more than “some unitary ran.” The client’s histogram must be the *unique* deterministic consequence of (i) the proved state (or proved trajectory), (ii) a 64-bit `sample_seed` **deterministically derived from the task specification** (orchestrator-assigned; not client-supplied), and (iii) the measurement specification.

### 7.1 Sampling pipeline

```
Unitary STARK
  → Born / marginal probabilities (deterministic function of state)
    → PRNG(sample_seed) + inverse-CDF / Bernoulli draws (deterministic)
      → counts → output_hash

```

### 7.2 Algebraic distribution binding

A distribution segment commits to seed, shots, `measurement_spec_hash`, a probability digest, and the explicit probability table (or its streamable surrogate). The verifier recomputes counts from those commitments and checks `output_hash`.

**`probability_digest` construction.** SHA3-256 over the concatenated little-endian `f64` probability bytes (terminal Born table of length $2^n$), or—for trajectory algebraic binding—over the concatenated per-event marginal probability bytes. The digest is stored as 32 raw bytes in the segment.

Two encodings exist:

* **v1 (`_M31_DIST_V1_`)** — legacy: seed, shots, digest, dense `f64` probabilities.
* **v2 (`_M31_DIST_V2_`)** — adds ASCII `measurement_spec_hash` and an optional Born zk tail.

### 7.3 Born zero-knowledge (`DistributionAir`)

A streaming AIR places one row per basis outcome, avoiding an exponential column blow-up. Constraints insist on fixed-point probabilities, normalization (sum $= 1$ within rounding), digest binding, and—when composed as `leaf:unitary_born`—consistency with the unitary link digest. Soft caps currently allow algebraic / Plonky3 Born zk up to **16 qubits** and **64** distinct outcomes in the zk table.

### 7.4 Mid-circuit trajectories

Dynamic circuits detach a *trajectory segment* from the unitary body:

```
<_M31_TRAJ_V1_|_M31_TRAJ_V2_>
event_count;
for each event: measured_qubit, outcome, pre_measure_state_digest, p0, p1;
[optional _M31_TRAJ_STARK_V1_]

```

v2 optionally prefixes a `unitary_link_digest` that chains the pre-first-measure state to the unitary STARK. Trajectory zk proves each unique pre-measure Z-marginal and may attach a per-shot Bernoulli AIR: the host replays $\texttt{StdRng}(\texttt{shot\_seed})$ to supply $u\sim U[0,1)$; the AIR proves the fixed-point comparison $\texttt{outcome}=1 \Leftrightarrow u \ge p_0$ via gap-bit decomposition. Caps: trajectory marginal zk ≤ **16 qubits**; ≤ **2048** sampling events per shot path.

### 7.5 Strength without zk AIRs

When zk AIRs are disabled, algebraic segments alone still bind seed and probabilities to the output hash. That is strictly weaker (a prover could lie about Born physics while keeping a consistent table), but remains useful when the dense table is already implied by a fully verified unitary terminal digest in lighter deployments.

---

## 8. Composition and aggregation

### 8.1 Binary compose (v3)

Aggregation proceeds as a binary tree of compose nodes:

```
parent_task_id\0
<_WQC_COMPOSE_V3_>
compose_label\0; manifest_root_hash\0;
left_child_hash:32; right_child_hash:32;
left_len; left_bytes; right_len; right_bytes;
[AggregationAir tail (v4)]
[RecursiveAggregationAir tail (v6)]

```

The verifier checks $\texttt{SHA3-256}(\texttt{child\_bytes})=\texttt{child\_hash}$ and dispatches child verification by label / marker. Normative wire layout: Appendix B.3.

**Canonical leaf labels.**

| Label | Left | Right |
| --- | --- | --- |
| `leaf:unitary_born` | v2 unitary (+ optional MSH / terminal digest) | Born leaf `_M31_BORN_LEAF_V1_` |
| `leaf:unitary_traj` | v2 unitary (+ link digest) | Trajectory leaf `_M31_TRAJ_LEAF_V1_` |

Inner nodes combine verified slice winners toward the task root. Compose-time checks ensure the unitary child’s `terminal_statevector_digest` (and, when present, `measurement_spec_hash`) match the values bound in the distribution / trajectory child.

### 8.2 Aggregation protocols and soundness modes

Composition supports three verification paradigms depending on the required trade-off between prover work and verifier succinctness:

| Mode | Mechanism | Verification Cost | Guarantees |
| --- | --- | --- | --- |
| **Direct Walk** | v3 tree binary traversal | $\mathcal{O}(N)$ leaf STARKs | Re-evaluates every child leaf natively. |
| **Digest Attestation** | `AggregationAir` (v4) | $\mathcal{O}(1)$ Aggregation STARK | Constrains container digests and host verification flags in-circuit. |
| **Recursive Aggregation** | `RecursiveAggregationAir` (v6) | $\mathcal{O}(1)$ Root STARK | Complete in-circuit verification via PCS certificates and out-of-domain (OOD) checks. |

#### RecursiveAggregationAir (v6 Architecture)

The primary recursive engine (`RecursiveAggregationAir`, width 330) binds child STARK digests alongside in-circuit polynomial commitment scheme (PCS) proofs. For each side of a compose node, a side flag indicates the verification bundle:

* `0`: Legacy compose without PCS bundle.
* `1`: `AggPcsCertificate` (for child aggregation nodes).
* `2`: `LeafPcsBundle` (for leaf nodes: unitary, Born, or trajectory).

Each certificate contains Merkle/Keccak sponge commitments, query-wise FriFold evaluations, DeepRo trace bindings, in-circuit FRI Validation/Challenge Mmcs proofs, and in-circuit `OodCheckAir` constraints covering both aggregation and leaf AIR types.

### 8.3 Leaf PCS integration and operational considerations

#### Leaf PCS Bundles

When a child node is a leaf (`kind=leaf`), `RecursiveAggregationAir` (v6) attaches a `LeafPcsBundle` corresponding to its domain:

| Leaf Type | Bundle Composition |
| --- | --- |
| **Unitary** | 1 $\times$ `LeafPcsCertificate` (`QuantumExecutionAir` OOD) |
| **Born** | 1 $\times$ `LeafPcsCertificate` (`DistributionAir` OOD) |
| **Trajectory** | $N \times$ Marginal Certificates + 1 $\times$ Shot Sampling Certificate |

Statement columns in `RecursiveAggregationAir` reflect the leaf bundle:

* `trace_commitment`: Set to the first certificate's commitment hash.
* `natural_row` (cols 0–32): Stores $\mathrm{SHA3}(\mathrm{concat}(\text{cert.stmt\_digest}))$ mapped as Mersenne31 field elements.
* `pcs_ok`: Evaluates to 1 when the polynomial commitment constraints hold in-circuit.

At verification time, out-of-domain quotient checks and leaf constraint evaluations execute in-circuit through `OodCheckAir`. Born recursion supports outcome dimensions up to $K \le 21$ (AIR width $W = 2 + 3K + 1 \le 68$) to fit within two Keccak rate blocks.

#### Footprint and Resource Bounds

While `RecursiveAggregationAir` achieves $\mathcal{O}(1)$ verification cost at the root, the inclusion of all-query FRI proofs and in-circuit Keccak sponges (`ValMmcs`/`ChallengeMmcs`) increases proof artifact size. In production execution profiles:

* Two idle unitary leaf proofs generate a composed root artifact of approximately **1.09 GiB**.
* Each leaf PCS side contributes approximately **587 MiB** to the total payload.

Consequently, recursive composition is cryptographically complete for active network topologies, while payload compression and query batching represent key operational priorities for deployment.

---

## 9. Soft caps and operational bounds

For the present **noiseless** `sample_counts` regime:

| Bound | Value |
| --- | --- |
| Algebraic Born / marginal qubits | 16 |
| Plonky3 Born zk qubits | 16 |
| Born zk outcomes | 64 |
| Born recursion outcomes ($K$; RecAgg leaf PCS) | 21 ($W\le 68$) |
| Trajectory marginal zk qubits | 16 |
| Per-shot sampling events | 2048 |

These caps are soft engineering limits of the current AIRs and streaming layouts; they are not intrinsic STARK barriers. Separate orchestrator / core policies (e.g. classical bit-width and mid-circuit qubit ceilings for dense simulation) further constrain what can be submitted; those client-facing limits belong in the public API documentation and are outside the algebraic scope of this paper.

Noise models (`depolarizing_p`, `readout_error`) may alter trajectory simulation for demos; they are **not** presently STARK-bound.

---

## 10. End-to-end verification protocol

1. **Marker detection.** Identify v1 / v2 / v3 (and reject the legacy `_M31_QUANTUM_AIR_STARK_` marker).
2. **Public-input check.** Compare $\mathsf{PI}$ against redispatched metadata and the result payload hash.
3. **Core proof check.**
* v1: re-expand trace; require `air_sum = 0` and matching boundaries.
* v2: verify FRI; process auxiliary segments in marker order.
* v3: hash-check children; verify children (and `AggregationAir` if present).

4. **Sampling check.** For counts tasks, recompute the deterministic sampling chain and compare `output_hash`.
5. **Root seal.** Persist `proof_root_hash` and the root artifact for clients and (eventually) L2 settlement.

A proof that fails any stage fails the task: workers are not paid for invalid or substituted work.

---

## 11. Discussion and future work

**Strengths.** The pipeline realizes the essential asymmetric shape of D-PoUW: proving cost tracks useful quantum simulation (wide memory, NTTs, FRI), while orchestrators verify leaves and—via v4/v6 aggregation—roots cheaply. Transparency removes coordination ceremonies that would be untenable across a global volunteer swarm. Polymorphic outputs, including mid-circuit trajectories, bring the proof surface close to algorithms practitioners actually run (VQE sampling, dynamic QEC primitives, variational loops).

**Open challenges.**

1. **Proof Size and Memory Footprint.** Embeddings of all-query `ValMmcs` / `ChallengeMmcs` Keccak STARKs per leaf side increase root artifact size in v6 composition trees. Future revisions will explore payload compression, opening-proof batching, and alternative authenticated opening schemes to reduce memory consumption.
2. **Recursive Protocol Refinement.** Continuation of witness extraction optimizations, native multi-chunk leaf DeepRo structures, and ongoing integration across multi-slice execution topologies.
3. **Larger Born / Trajectory Zero-Knowledge.** Soft caps of 16 qubits bound the fully zk-sampled subspace; larger histograms currently rely on algebraic binding and unitary compressions (TN cut, idle wires).
4. **Noise-Aware STARKs.** Stochastic physical channels (e.g., depolarization, readout noise) remain outside the current constraint model.
5. **Machine-Readable API.** Formalization of error codes and parameter definitions within user-facing interfaces to simplify error handling on failed submissions.

**Related vision.** As aggregation deepens, Layer-2 contracts need verify only $\pi_{\mathrm{Root}}$, with verification cost scaling as $\mathcal{O}(\log^2 M)$ in proof-tree depth once recursion is complete—completing the transition from fortress supercomputers to a cryptographically accountable swarm.

---

## Acknowledgments

This specification reflects the WQC proof stack as implemented in `wqc-stark-engine`, consumed by `wqc-core` / `wqc-node`, and verified by `wqc-orchestrator`. Design lineage includes Plonky3 (Polygon) and the STARK literature on FRI and AIR.

---

## Appendix A. Transcript markers

| Constant | Marker string |
| --- | --- |
| `V1_MARKER` | `_M31_QUANTUM_AIR_V1_` |
| `V2_MARKER` | `_M31_PLONKY3_STARK_V2_` |
| `V3_COMPOSE_MARKER` | `_WQC_COMPOSE_V3_` |
| `LEGACY_MARKER` | `_M31_QUANTUM_AIR_STARK_` (rejected) |
| `BORN_LEAF_MARKER` | `_M31_BORN_LEAF_V1_` |
| `TRAJ_LEAF_MARKER` | `_M31_TRAJ_LEAF_V1_` |
| `DIST_MARKER_V1` / `V2` | `_M31_DIST_V1_` / `_M31_DIST_V2_` |
| `BORN_TAIL_MARKER` | `_M31_BORN_TAIL_V1_` |
| `TRAJ_MARKER` | `_M31_TRAJ_V1_` / `_M31_TRAJ_V2_` |
| `TRAJ_STARK_MARKER` | `_M31_TRAJ_STARK_V1_` |
| `AGG_TAIL_MARKER` | `_WQC_AGG_TAIL_V4_` |
| Aggregation body | `_WQC_AGG_STARK_V4_` |
| `REC_TAIL_MARKER` | `_WQC_REC_TAIL_V5_` (legacy) / `_WQC_REC_TAIL_V6_` |
| Recursive aggregation body | `_WQC_REC_AGG_V5_` / `_WQC_REC_AGG_V6_` |
| Measurement-spec prefix | `MSH1` |

---

## Appendix B. Binary layouts (normative)

All string fields are NUL-terminated C strings. Multibyte integers are little-endian unless stated otherwise. Hex digests are 64 ASCII hex characters (SHA3-256). Fixed-point values use $2^{30}$ scaling rounded to `u32` least-significant bits.

### B.1 v1 unitary (embedded trace)

```
<sub_task_id\0>
<_M31_QUANTUM_AIR_V1_>
<circuit_id\0><node_id\0><slice_id\0><output_hash\0>
[optional terminal_statevector_digest\0]
[optional MSH1<measurement_spec_hash>\0]
<trace_rows: u32 LE>
<trace: f64 LE repeated trace_rows × 11>
<air_sum: u32 LE>
<boundary_v0_re: u32 LE>
<boundary_v0_im: u32 LE>
<boundary_v1_re: u32 LE>
<boundary_v1_im: u32 LE>

```

`trace_rows` counts the total number of trace rows (pre-gate + post-gate pairs plus terminal). The verifier re-expands the 11 f64 columns to 21 AIR columns (see Appendix C) and recomputes the constraint sum; a valid proof has `air_sum == 0`. The four boundary values encode the real and imaginary parts of the two amplitude registers (`v0`, `v1`) from the final trace row, scaled by $2^{30}$ and rounded to `u32`.

### B.2 v2 unitary (Plonky3 FRI STARK)

```
<sub_task_id\0>
<_M31_PLONKY3_STARK_V2_>
<circuit_id\0><node_id\0><slice_id\0><output_hash\0>
[optional terminal_statevector_digest\0]
[optional MSH1<measurement_spec_hash>\0]
<proof_len: u32 LE>
<proof: postcard-encoded p3_uni_stark::Proof>

```

After the unitary proof body, zero or more auxiliary segments may follow (detected by their markers):

| Segment | Marker | Payload |
| --- | --- | --- |
| Distribution v1 | `_M31_DIST_V1_` | B.4 |
| Distribution v2 | `_M31_DIST_V2_` | B.4 |
| Trajectory v1 / v2 | `_M31_TRAJ_V1_` / `_M31_TRAJ_V2_` | B.5 |
| Born zk tail | `_M31_BORN_TAIL_V1_` | (inner distribution STARK, wrapped inside distribution segment) |
| Trajectory zk tail | `_M31_TRAJ_STARK_V1_` | (inner marginal / shot-sampling STARK, wrapped inside trajectory segment) |
| Aggregation v4 | `_WQC_AGG_TAIL_V4_` | B.6 |
| Recursive Aggregation v6 | `_WQC_REC_TAIL_V6_` | B.7 |

The v2 verifier reconstructs the AIR trace from the same execution inputs (not embedded) and evaluates constraints over the trace extension. Auxiliary segments are processed in marker order.

### B.3 v3 compose

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
[optional v4 aggregation tail (see B.6)]
[optional v6 recursive aggregation tail (see B.7)]

```

Child hashes are SHA3-256 of the corresponding child bytes. The verifier checks `SHA3-256(left_child) == left_child_hash` (and symmetrically for right) before routing to the appropriate child verifier.

Compose labels:

| Label | Left child | Right child |
| --- | --- | --- |
| `leaf:unitary_born` | v2 unitary (+ optional MSH / terminal digest) | Born leaf (`_M31_BORN_LEAF_V1_`) |
| `leaf:unitary_traj` | v2 unitary (+ link digest) | Trajectory leaf (`_M31_TRAJ_LEAF_V1_`) |
| *(task / slice tree)* | Verified slice winner | Verified slice winner |

### B.4 Distribution segment

Appended after the unitary proof body for `sample_counts` outputs.

**v1 (legacy):**

```
<_M31_DIST_V1_>
<seed: u64 LE>
<shots: u32 LE>
<probability_digest: 32 bytes (SHA3-256)>
<probabilities: f64 LE × 2ⁿ>

```

**v2:**

```
<_M31_DIST_V2_>
<seed: u64 LE>
<shots: u32 LE>
<measurement_spec_hash: 64 ASCII hex chars>
<probability_digest: 32 bytes (SHA3-256)>
<probabilities: f64 LE × 2ⁿ>
[optional _M31_BORN_TAIL_V1_ tail]

```

`seed` is the task’s deterministically derived `sample_seed` (§7). `probability_digest` is SHA3-256 of the concatenated LE `f64` probability bytes (§7.2). The Born zk tail (when present) contains an inner Plonky3 STARK over `DistributionAir` (see §7.3).

### B.5 Trajectory segment

Appended after the unitary proof body for mid-circuit measurement outputs.

```
<_M31_TRAJ_V1_> or <_M31_TRAJ_V2_>
[optional unitary_link_digest: 64 ASCII hex chars\0]   (v2 only)
<event_count: u32 LE>
for each event:
  <measured_qubit: u32 LE>
  <outcome: u32 LE>
  <pre_measure_state_digest: 32 bytes>
  <p0: u32 LE fixed-point>
  <p1: u32 LE fixed-point>
[optional _M31_TRAJ_STARK_V1_ tail]

```

`unitary_link_digest` chains the pre-first-measure unitary state to the trajectory body. The zk tail contains marginal STARK proofs for each unique pre-measure Z-marginal, plus an optional per-shot Bernoulli sampling STARK (see §7.4).

### B.6 Aggregation tail (v4)

```
<_WQC_AGG_TAIL_V4_>
<agg_len: u32 LE>
<_WQC_AGG_STARK_V4_>
<compose_label\0>
<manifest_root_hash\0>
<left_hash: 32 bytes>
<right_hash: 32 bytes>
<proof_len: u32 LE>
<proof: postcard-encoded p3_uni_stark::Proof>

```

The `AggregationAir` uses the same Circle PCS / Plonky3 uni-STARK configuration as unitary leaf proofs. It binds left and right child SHA3-256 digests directly in the trace and constrains both child verification flags to 1. Child STARK verification is performed natively at compose time, not in-circuit; the aggregation STARK attests digest binding and compose metadata only.

### B.7 Recursive aggregation STARK (v6)

Appended after the v3 compose body and the V4 `AggregationAir` tail:

```
<_WQC_REC_TAIL_V6_>
<rec_len: u32 LE>
  <parent_task_id\0>
  <_WQC_REC_AGG_V6_>
  <compose_label\0>
  <manifest_root_hash\0>
  <left_hash: 32><right_hash: 32>
  <left_stark_digest: 32><right_stark_digest: 32>
  <left_kind: u8><right_kind: u8>
  <left_side?> <right_side?>   # Per side: 0=none, 1=AggPcsCertificate, 2=LeafPcsBundle
                                 # Certificate payload: MerkleFold + Keccak + FriFold + DeepRo
                                 #                      + FRI Val/Challenge Mmcs + OodCheckAir
  <proof_len: u32 LE>
  <proof: postcard-encoded RecursiveAggregationAir>

```

`RecursiveAggregationAir` (width 330) binds child STARK digests and, for each side, either an `AggregationAir` natural row + PCS commitment (`AggPcsCertificate`) or a leaf PCS statement digest derived from the leaf bundle (`LeafPcsBundle`: unitary / Born / trajectory). Each certificate carries Merkle/Keccak sponges, all-query FriFold, DeepRo, in-circuit FRI Val/Challenge Mmcs, and in-circuit `OodCheckAir`.

---

## Appendix C. AIR column reference

### C.1 Trace columns

The execution trace has 11 f64 columns per row (`TRACE_WIDTH`):

| Index | Name | Description |
| --- | --- | --- |
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

**Row pattern.** Each active gate contributes a *pre-gate* row (parameters set, amplitudes before the operator) and a *post-gate* row (`gate_id = 0`, amplitudes after). A terminal boundary row ends the segment with `transition_link = 0`.

### C.2 Gate encoding

| `gate_id` | Gate | Description |
| --- | --- | --- |
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

### C.3 Expanded AIR columns

The prover expands the 11-column trace to 21 AIR columns before constraint evaluation:

| AIR columns | Source | Purpose |
| --- | --- | --- |
| 0–3 | `v0_re`, `v0_im`, `v1_re`, `v1_im` | Amplitude registers |
| 4 | `gate_id` | Gate selector |
| 5 | `target_qubit` | Target qubit |
| 6 | `ctrl_active` | Control flag selector |
| 7 | `ctrl_active_2` | Second control flag selector |
| 8 | `ctrl_qubit` | Control qubit |
| 9 | `ctrl_qubit_2` | Second control qubit |
| 10 | `transition_link` | Link continuity |
| 11–20 | selector expansion | Gate-specific one-hot selectors derived from `gate_id` |

### C.4 Constraints

1. **Amplitude continuity.** When `transition_link = 1.0`, adjacent rows in the same amplitude register must be equal. This links post-gate rows to the next pre-gate row when the next gate operates on the same target qubit.
2. **Gate semantics.** Each active gate enforces a specific complex-linear map on $(v_0, v_1)$:
* **H** (Hadamard): $\vert{}0\rangle \mapsto (\vert{}0\rangle + \vert{}1\rangle)/\sqrt{2}$, $\vert{}1\rangle \mapsto (\vert{}0\rangle - \vert{}1\rangle)/\sqrt{2}$.
* **X, Y, Z**: standard Pauli rotations.
* **RX, RY, RZ**: rotation gates by a fixed angle.
* **CNOT**: flips target when control is $\vert{}1\rangle$.
* **CZ**: phase-flips target when control is $\vert{}1\rangle$.
* **CCNOT** (Toffoli): flips target when both controls are $\vert{}1\rangle$.
* **MEASURE**: collapses to $\vert{}0\rangle$ or $\vert{}1\rangle$; no amplitude continuity constraint.
* **IDLE**: amplitudes unchanged.


3. **Selector consistency.** `gate_id` must decode bijectively to the one-hot selector columns (columns 11–20). Exactly one selector is 1.0 and the remainder are 0.0.
4. **Control consistency.** When `ctrl_active = 1.0`, the control qubit index must be valid and the gate behaviour must depend on the control amplitude.
5. **Boundary condition.** The terminal row amplitudes must match the boundary values committed in the v1 proof header ($2^{30}$ fixed-point).

---

## References (project)

1. World Quantum Computer Whitepaper v0.3, §3.3–3.4 — recursive aggregation and polymorphic outputs.
2. Appendices B (binary layouts) and C (AIR column reference) in this document.
3. Polygon Plonky3 — uni-STARK, Circle PCS, FRI over Mersenne31.
4. Ben-Sasson et al., *Scalable, transparent, and post-quantum secure computational integrity* (STARK foundations).
