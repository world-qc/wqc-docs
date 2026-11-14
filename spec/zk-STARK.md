# Zero-Knowledge STARKs for Trustless Distributed Quantum Simulation

**A Formal Protocol Specification for the World Quantum Computer (WQC) Cryptographic Proof Engine**

- **Tier:** A (canonical protocol spec)

---

## Abstract

The World Quantum Computer (WQC) architecture replaces traditional energy-intensive, non-deterministic hash-based Proof-of-Work (PoW) with *Deterministic Proof of Useful Work* (D-PoUW). Under this paradigm, distributed worker nodes contract tensor-network or statevector slices of quantum circuits and generate succinct, cryptographically verifiable proofs of correct execution. This document presents the formal technical specification for WQC's zero-knowledge Scalable Transparent Argument of Knowledge (zk-STARK) proof system. We define the public-input binding mechanism anchoring proofs to dispatched sub-tasks, the Algebraic Intermediate Representation (AIR) for unitary gate execution traces, auxiliary proof extensions for Born-rule sampling and mid-circuit measurement trajectories, and a recursive binary composition tree driven by an aggregation STARK that achieves $\mathcal{O}(1)$ verification time. Designed for post-quantum transparency (requiring no trusted setup), the engine operates natively over the Mersenne31 field using Circle Polynomial Commitment Schemes (PCS). The protocol ensures that proving costs track useful quantum simulation while verification costs remain polylogarithmic to support light-client and on-chain consensus settlement.

---

## 1. Introduction

### 1.1 Background: From Fortress Computing to a Neural Swarm

High-performance quantum computation has historically been centralized within monolithic, closed-access physical infrastructure. This concentration introduces significant trust boundaries. A client delegating quantum state vector evolution or variational algorithm evaluation to an unverified third party cannot independently validate whether the returned probability distribution was computed honestly, truncated early, or entirely fabricated.

Conversely, public blockchain networks establish decentralized consensus at the expense of computational utility. Conventional PoW mechanisms convert massive electrical power into thermodynamic entropy solely for Sybil resistance. WQC unifies these two paradigms by redirecting consensus work toward useful quantum circuit execution. By partitioning complex quantum circuits across a heterogeneous network of worker nodes—termed the *Neural Swarm*—computational energy spent securing the consensus layer directly translates into scientific simulation throughput. Each worker contracts assigned sub-circuits, emitting verifiable cryptographic arguments of correct execution.

### 1.2 The Verification Bottleneck

Centralized re-execution of distributed simulation slices eliminates the performance and decentralization benefits of the network. Furthermore, verifying full $2^n$-dimensional state vectors on-chain is computationally intractable. Succinct arguments of knowledge ($\pi$) address this bottleneck by allowing a verifier to validate execution integrity in time polylogarithmic to the trace length.

Applying STARKs to quantum circuit simulation requires addressing three distinct technical hurdles:

1. **Dimensional Scaling:** Quantum state spaces grow exponentially as $2^n$. WQC resolves this by applying tensor-network cuts and idle-wire assignments to create smaller circuit slices, proving per-slice contractions rather than global state vectors.
2. **Result Polymorphism:** Client execution requests vary by output mode, including scalar amplitudes (`statevector_scalar`), shot counts (`sample_counts`), or Pauli operator expectation values (`expectation`). Non-deterministic quantum sampling requires deterministic pseudorandom generator (PRNG) binding and Born-rule state commitments to prevent output manipulation.
3. **Dynamic Circuit Execution:** Mid-circuit operations (`MEASURE`, `RESET`, and conditional gate execution) break pure unitary evolution. WQC bifurcates proofs into unitary sub-segments and measurement trajectory segments, cryptographically chaining them through state commitments.

### 1.3 Cryptographic Foundation: zk-STARKs

STARKs provide specific structural properties tailored for distributed quantum proof generation:

| Property | Protocol Relevance |
| --- | --- |
| **Transparency** | Eliminates trusted setup ceremonies and toxic waste, enabling anonymous worker participation. |
| **Hash-Based Security** | Relies on collision-resistant hash functions and the Fast Reed-Solomon Interactive Proof of Proximity (FRI), avoiding pairing assumptions. |
| **Asymmetric Scalability** | Prover time is quasi-linear in trace length $\mathcal{O}(N \log N)$, whereas verifier time is polylogarithmic $\mathcal{O}(\log^2 N)$. |
| **AIR Compatibility** | Transition polynomials naturally model discrete statevector gate transitions across field registers. |
| **Post-Quantum Security** | Symmetric cryptographic foundations provide resilience against quantum cryptanalytic attacks. |

Production proof generation is configured over the Mersenne31 prime field using Polygon Plonky3 with Circle PCS. Zero-knowledge extensions (`DistributionAir`, trajectory marginals, and per-shot Bernoulli AIRs) preserve privacy over dense probability tables while strictly enforcing Born-rule compliance.

### 1.4 Specification Scope

This document specifies the complete cryptographic proof architecture of WQC:

* Public-input binding schema linking task assignments to proof artifacts (including optional `MSH1` / `SEC1` fields).
* Algebraic Intermediate Representation (AIR) specifications for unitary execution.
* Auxiliary probability distribution and measurement trajectory constraints.
* Binary recursive composition trees, including v4 `AggregationAir` and v6 `RecursiveAggregationAir` with PCS certificates (host-bound Mmcs/FriFold/OOD digests; optional nested group STARKs).
* `security_level` → FRI query ladder for leaf unitary / Born / trajectory prove/verify and outer AggregationAir / RecAgg / leaf PCS certificates (§5.1). Nested Mmcs / FriFold group STARKs **default to the same outer query count**; an optional `WQC_PCS_NESTED_FRI_QUERIES` ≤ outer is a size lever (shrink profile), not the production default.
* Operational bounds, memory gating policies, and P2P Leaf PCS delivery workflows.

---

## 2. System Model

### 2.1 Network Actors

* **Client:** Formulates quantum circuit requests, specifies the target output mode, funds execution escrow, and receives final output results alongside a verified root proof $\pi_{\mathrm{Root}}$.
* **Orchestrator:** Performs circuit decomposition (slicing), manages task bidding and quorum assignment, dispatches execution tasks to workers, validates leaf/composition proofs, and seals the final proof manifest.
* **Worker Node:** Executes local slice contractions via `wqc-core`, generates corresponding leaf STARK proofs bound to public task parameters, and transmits results over P2P.
* **Aggregator / Finalizer:** Constructs binary composition trees, executes recursive aggregation STARKs, and registers `proof_root_hash` and `root.bin` artifacts.

### 2.2 Adversarial Threat Model

The STARK subsystem guards against malicious worker behaviors, specifically targeting:

1. Sub-task or circuit slice substitution.
2. Fabrication of state vector scalar amplitudes or shot measurement histograms.
3. Front-running or replaying proof artifacts from peer nodes.
4. Generating non-deterministic sample outputs inconsistent with the assigned seed and Born distribution.
5. Forging mid-circuit measurement outcomes.

### 2.3 Proof Obligations by Output Mode

| Output Mode | Primary Leaf Claim | Auxiliary Binding Obligation |
| --- | --- | --- |
| `statevector_scalar` | State-vector unitary leaf (§6.6) when the circuit has one: the final state's digest; the node publishes the state and the verifier reads the `\|0…0⟩` amplitude from it. Otherwise (v1): unitary contraction of a target amplitude scalar. | v2: none (the state hashes to the proved digest). v1: none; an exact contraction tree adds no segment, and the amplitude stays outside the AIR ([`contraction-tree.md`](contraction-tree.md) §7). |
| `sample_counts` (Terminal) | State-vector leaf (sv-stark, §6.4): the final state's digest and the counts of the dispatched seed's shots, in one proof. Unmeasured qubits are marginalized by the sampler. | None; the counts are in the statement. |
| `sample_counts` (Mid-Circuit) | State-vector leaf over the circuit rewritten by deferring its measurements (§6.5). v1 (when the rewritten circuit has no leaf): unitary segment traces bounded by measurement gates. | None for the state-vector leaf. v1: sequential trajectory event stream + zk marginal/shot proofs. |
| `expectation` | State-vector unitary leaf (§6.6) when the circuit has one; the verifier computes each observable from the published state. Otherwise (v1): algebraic expectation calculation over contracted state. | v2: none (the state hashes to the proved digest). v1: result payload digest binding. |

### 2.4 Implementation Status (2026-11)

A terminal `sample_counts` task (only unitary gates before its `MEASURE`s, whether or not every qubit is measured) is proved by the state-vector leaf (§6.4) and its root (§8.5): the statement commits the dispatch context, the final state's digest, the seed and the counts, and the orchestrator verifies the proof against the statement it builds from the dispatch it signed, the digest and counts the node reported, and the seed it dispatched. That is the first path on which the proof, not the quorum, carries the result. A `statevector_scalar` or `expectation` task with a state-vector leaf is proved the same way, the node publishing its final state so the verifier can read the values off the proved digest (§6.6). A terminal task whose circuit needs no rounding step (X, Z, CNOT, CZ and the like only) has no state-vector leaf and stays on the v1 Born path of §7, as does every task when the orchestrator runs with v2 off or under validity-proof settlement ([`p2p-protocols.md`](p2p-protocols.md) §6.1).

The other leaf STARKs (§6.1–§6.3, §7) do not yet meet §5–§7. They are proved with empty public inputs, so the §5 context is carried beside the proof rather than committed by it, and the unitary AIR does not yet enforce the §6.3 constraint sets soundly. Until they do, unitary results rest on quorum and trap tasks, Born / marginal / shot-sampling results on the verifier's native recomputation from the published segment, and composition on `verify_root_proof` verifying every child (§8.2). A mid-circuit `sample_counts` task is proved by the state-vector leaf too, over its circuit rewritten with measurements deferred (§6.5, capability bit 6), when that rewritten circuit has a leaf; the trajectory proof (§7.4) remains for the rest.

---

## 3. Mathematical Preliminaries

### 3.1 Algebraic Intermediate Representation (AIR)

Computational logic is framed as an execution trace matrix $T \in \mathbb{F}^{T_{\mathrm{rows}} \times T_{\mathrm{cols}}}$. Valid state transitions are expressed as a set of multivariate transition polynomials $P_j(X_0, \dots, X_{W-1}, Y_0, \dots, Y_{W-1})$ such that $P_j(T_{i, \star}, T_{i+1, \star}) = 0$ for all valid row transitions $i$. The quotient polynomial $Q(X) = \frac{C(T(X))}{Z_H(X)}$ is committed via Circle PCS and evaluated at randomized out-of-domain challenge points using FRI.

### 3.2 Field & Polynomial Commitment Scheme

* **Base Field:** Mersenne31 ($\mathbb{F}_p$, where $p = 2^{31} - 1$).
* **Commitment Scheme:** Circle PCS implemented via Polygon Plonky3.
* **Serialization:** Postcard serialization format encoding `p3_uni_stark::Proof` structures.
* **FRI queries:** Circle config `num_queries` is selected from the Orchestrator `security_level` for leaf unitary / Born / trajectory STARKs and for outer AggregationAir / RecAgg proofs (see §5.1). Leaf and aggregation PCS certificates use runtime `n = proof.query_proofs.len()` (capped at 40). Nested Mmcs / FriFold group STARKs default to that same outer `n`; they may use a smaller nested count via `WQC_PCS_NESTED_FRI_QUERIES` (§5.1). Nested DeepRo uni-STARKs on leaf PCS bundles (single-chunk quotients only) use the same nested count; aggregation certificates carry their DeepRo steps host-only, with no nested STARK. Empty / unknown level defaults to $40$ (`DEVNET_FRI_NUM_QUERIES`). This ladder is an **operational cost/throughput control**, not a claim of calibrated soundness bits.

Legacy transcript profile v1 embeds uncompressed floating-point traces evaluated via explicit verifier sumchecks, whereas production profile v2 commits traces via Circle PCS.

### 3.3 Notation

Let $\pi$ denote a proof artifact, $\mathsf{PI}$ the public-input vector, and $H(x)$ the SHA3-256 cryptographic digest function. Binary strings are represented as NUL-terminated C-strings, and digest values are represented either as raw 32-byte arrays or 64-character ASCII hexadecimal strings.

---

## 4. Architecture Overview

The cryptographic proof pipeline below is the worker–compose–root path. The live process map (HTTP client, orchestrator, p2p-proxy, node, core, composer, CAS) is [`architecture-current.md`](architecture-current.md); the target-state system is specified in [`architecture.md`](architecture.md).

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

### Transcript Version Specification

| Version | Header Marker | Protocol Mechanism |
| --- | --- | --- |
| **v1** | `_M31_QUANTUM_AIR_V1_` | Embedded trace with host-side re-expanded AIR sum validation. |
| **v2** | `_M31_PLONKY3_STARK_V2_` | Production Plonky3 FRI STARK over Circle PCS. |
| **v3** | `_WQC_COMPOSE_V3_` | Binary child composition container supporting v4/v6 aggregation tails. |

---

## 5. Public Input Binding Schema

To prevent proof-swapping attacks, every leaf proof commits to a rigid `StarkContext` public input structure $\mathsf{PI}$:

| Field Identifier | Enforcement | Functional Description |
| --- | --- | --- |
| `circuit_id` | Mandatory | SHA3-256 of the canonical circuit JSON. A branched slice hashes the pruned compact circuit. An exact-tree dispatch has empty assignments, so the prune is the identity and the hash is of the parent circuit ([`contraction-tree.md`](contraction-tree.md)). |
| `sub_task_id` | Mandatory | Unique task dispatch identifier assigned by the Orchestrator. |
| `node_id` | Mandatory | Cryptographic identifier of the worker node generating the proof. |
| `slice_id` | Mandatory | Binary tree path designating tensor cut / idle-wire partition. |
| `output_hash` | Mandatory | SHA3-256 hash of the computed output payload (scalar or counts JSON). |
| `terminal_statevector_digest` | Optional | SHA3-256 digest linking unitary state vector to Born / trajectory claims. |
| `measurement_spec_hash` | Optional | SHA3-256 digest of measurement specification (`MSH1` prefix). |
| `security_level` | Optional | Orchestrator security tier (`low` \| `normal` \| `high` \| `ultra`); bound with `SEC1` prefix when non-empty on unitary leaves. Selects FRI `num_queries` for unitary / Born / trajectory / AggregationAir / RecAgg outer STARKs (§5.1). |

Formally, the mandatory public input tuple is defined as:

$$\mathsf{PI} = \{\,\texttt{circuit\_id},\ \texttt{sub\_task\_id},\ \texttt{node\_id},\ \texttt{slice\_id},\ \texttt{output\_hash}\,\} \quad \text{}$$

### 5.1 SecurityLevel → FRI Query Ladder

Client `security_level` drives quorum (`required_votes`), bid policy, and the fee multiplier on `TotalFee` (a table per tier, `normal` = 1× and `high` = 2×; normative values in [`economics.md`](economics.md) §2). The same tier is copied onto each signed `SubTask` dispatch and threaded orch → node → `wqc-core` for leaf prove/verify, then through compose / RecAgg for the whole task tree (CGO FFI passes the level into leaf and root verifiers).

| `security_level` | v1 leaf FRI `num_queries` | sv-stark (v2) leaf FRI `num_queries` |
| --- | ---: | ---: |
| `low` | 8 | 22 |
| `normal` | 16 | 32 |
| `high` | 32 | 37 |
| `ultra` (or empty / unknown) | 40 | 42 |

The sv-stark leaf ([`p2p-protocols.md`](p2p-protocols.md) §6.1, `wqc-sv-stark` on Goldilocks²) uses blowup 4 and a 16-bit query PoW at every tier; only the query count changes (`FriParams::leaf`). Its "v2" is the leaf generation, not the `_M31_PLONKY3_STARK_V2_` proof format (§10, Appendix A). The fee does not follow either column ([`economics.md`](economics.md) §2).

**Binding and authority:**

* When non-empty, unitary prove appends `SEC1<security_level>\0` after optional `MSH1…` in the leaf PI binding (Appendix B.1 / B.2). Born / trajectory inherit the parent context level without a separate `SEC1` tag.
* Orchestrator verify uses `SubTask.security_level` as authoritative. If a unitary proof binds a different `SEC1` value, verification fails.
* Prove and verify must use the **same** query count; mismatched ladders reject the Plonky3 proof.
* PCS certificates take `n` from `proof.query_proofs.len()` and optionally cross-check against `fri_num_queries_for_security_level(level)`. Wire vectors are length-prefixed with `1 <= n <= 40`.

**Scope:** Outer Circle STARKs (unitary, Born, trajectory, AggregationAir, RecAgg) and leaf/agg PCS query slots follow this ladder. Nested Mmcs / FriFold **group** uni-STARKs are separate attestation proofs (Merkle path / fold equation); their FRI `num_queries` is an implementation parameter of that sub-proof, not the number of outer FRI slots the parent opened.

**Production default (nested = outer):** Nested Mmcs / FriFold group STARKs use the **same** FRI query count as the outer leaf/agg proof (`n` from `proof.query_proofs.len()`). Prove and verify pair on that count (the nested proof carries its own query vector; verify rebuilds Circle config from the nested proof). This keeps the weakest attestation link aligned with the task’s outer operational tier.

**Optional size lever (`WQC_PCS_NESTED_FRI_QUERIES`):** Operators may set nested Mmcs / FriFold `num_queries` to any integer in `1..=n_outer`. Unset or out-of-range values fall back to `n_outer`. This is an **explicit shrink / experiment profile**, not a silent downgrade of `security_level`:

| Profile (idle two-leaf Poseidon, illustrative) | Outer | Nested | Role |
| --- | ---: | ---: | --- |
| Production / `security_level` default | ladder `n` | `n` | Weakest FRI link matches the task tier |
| Shrink tracking `chunk40/nested8q` | 40 | 8 | Historical size lever when nested group STARKs were on the wire |
| Shrink tracking `chunk40/nested4q` | 40 | 4 | Smaller nested residual (same historical knobs) |

Measured reference (Poseidon compose, `WQC_PCS_MMCS_GROUP_CHUNK=40`, host-only Mmcs/FriFold/OOD + prior merges): nested=outer ≈ 169 KiB root (`173_483` B). **Pre-wrap size KPI signed off (2026-09-04):** this profile meets the ≤500 KB idle two-leaf gate (see `wqc-contracts` `on-chain_settlement_scope.md` §7). Nested group STARKs are empty on this path (`mmcs_groups=0`, `fri_fold=0`, `ood=0`); siblings + digests remain on the wire. When nested group STARKs are proven, they follow `WQC_PCS_NESTED_FRI_QUERIES` (default = outer). Idle leaves currently ship `deep_ro=0` (multi-chunk quot).

**Aggregation children (host-only DeepRo):** When a child is itself a compose node (a `leaf:unitary_born` / `leaf:unitary_traj` leaf, or an inner node of a multi-level tree), the parent carries an `AggPcsCertificate` for it instead of a leaf bundle. Its DeepRo / DeepRoTrace steps (one pair per proven query) are host-only like Mmcs / FriFold / OOD: `deep_stark` is empty, the verifier recomputes every public value of a step from its inputs, and those inputs are bound to the child's FRI openings and FriFoldY leaves. A step that still carries a STARK (certificates from earlier composers) is verified with it. The AIR of these steps constrains public values only, so the nested STARK added no check; it did add one STARK per query, each with as many queries again under the default nested count (`WQC_PCS_NESTED_FRI_QUERIES` unset), so certificate size grew with the square of `n`. Measured on a single-leaf Born root (Bell circuit; the leaf is paired with itself). The first two columns are from 2026-11-07, when the root still carried the leaf and its certificate twice; the last is after the right side became a back-reference (§8.2). `wqc-stark-core` test `single_leaf_born_root_sizes` (ignored; run with `--features plonky3-stark -- --ignored --nocapture`) prints the right-hand column:

| `security_level` | Root with DeepRo STARKs | Root, host-only DeepRo | Leaf sent once |
| --- | ---: | ---: | ---: |
| `low` | 264 KB | 143 KB | 79 KB |
| `normal` | 734 KB | 262 KB | 145 KB |
| `high` | 2.37 MB | 504 KB | 277 KB |
| `ultra` | — | 624 KB | 344 KB |

At `normal` the remaining bytes are the embedded leaf (74 KB), its certificate (about 44 KB), and the RecAgg and AggregationAir STARKs (about 26 KB); all grow linearly with `n`.

**Multi-slice roots:** Every compose node embeds its children whole (§8.1), so a root holds every leaf, every inner node's certificate and every node's STARK tails, and grows linearly with the slice count. Measured 2026-11-08 with the composer's pairing (pairs per level, odd tail carried up); `wqc-stark-core` test `multislice_root_sizes` (ignored) prints these:

| Leaves | `security_level` | 2 slices | 3 slices | 4 slices | 8 slices |
| --- | --- | ---: | ---: | ---: | ---: |
| Born (Bell) | `low` | 143 KB | 245 KB | 347 KB | 757 KB |
| Born (Bell) | `normal` | 263 KB | 452 KB | 642 KB | 1.40 MB |
| Unitary (Bell prefix) | `low` | 33 KB | 85 KB | 128 KB | 319 KB |
| Unitary (Bell prefix) | `normal` | 60 KB | 156 KB | 236 KB | 589 KB |

An inner node over two Born leaves is 263 KB at `normal`, the same as a two-slice root. Each further Born slice adds about 190 KB at `normal`, most of it the leaf (74 KB), its certificate and the inner nodes' certificates and tails. Born roots stay under 500 KB up to 3 slices at `normal` (452 KB) and at least 4 at `low` (347 KB). Keeping larger trees under that bound needs nodes that do not embed their children.

**Why nested is not forced to 40 forever:** Outer `n` still dominates *how many* Mmcs paths / FriFold steps PCS materializes. When nested group STARKs are on the wire, each group’s own FRI query count dominates *group_stark* bytes; lowering nested remains a soft size lever. Host-only idle Poseidon compose no longer pays that residual.

**Risk of fewer queries (outer or nested):** FRI soundness error decreases as more random queries are checked. Lowering outer `n` (e.g. `ultra` $40$ → `low` $8$) or nested `n` below outer increases residual risk that a malicious or buggy *parent* proof or *attestation* sub-proof escapes detection for a given hash/FRI parameter set. In this stack both knobs are **operational cost/throughput controls**, not calibrated bit-security claims. Clients and operators must not infer cryptographic security levels from the tables above. Prove and verify must still use the same counts for each proof surface; a mismatch is a hard reject, not a soft downgrade. Do **not** ship production with nested below outer unless the deployment docs state that the nested residual is accepted independently of `security_level`.

---

## 6. Unitary Execution Proof Engine

### 6.1 Trace Geometry

The unitary execution trace consists of $\texttt{TRACE\_WIDTH} = 11$ double-precision columns per row (v2 multi-target AIR):

| Col | Field | Functional Role |
| --- | --- | --- |
| 0 | $\texttt{gate\_id}$ | Numeric gate opcode (see §6.2). |
| 1 | $\texttt{ctrl\_active}$ | Primary control activation: discrete `0.0` or `1.0` (marginal control probability thresholded at `0.5`). |
| 2 | $\texttt{ctrl\_active\_2}$ | Secondary control for CCNOT (same discretization). |
| 3 | $\texttt{p\_cos}$ | Rotation parameter cosine. |
| 4 | $\texttt{p\_sin}$ | Rotation parameter sine. |
| 5–6 | $v_0^{\mathrm{re}}, v_0^{\mathrm{im}}$ | Target-qubit $\vert{}0\rangle$ amplitude (real, imaginary). |
| 7–8 | $v_1^{\mathrm{re}}, v_1^{\mathrm{im}}$ | Target-qubit $\vert{}1\rangle$ amplitude (real, imaginary). |
| 9 | $\texttt{target\_qubit}$ | Logical wire index sampled in columns 5–8. |
| 10 | $\texttt{transition\_link}$ | `1.0` if the **next** row continues the same target wire; `0.0` otherwise. |

Each gate emits **two rows** on the gate's target qubit:

1. **Pre-gate row** — active $\texttt{gate\_id}$; amplitudes sampled before applying the gate.
2. **Post-gate row** — $\texttt{gate\_id} = 0$; amplitudes sampled after applying the gate (same target wire).

After all gates, a **terminal boundary row** ($\texttt{gate\_id} = 0$) samples the last gate's target qubit with $\texttt{transition\_link} = 0$. An empty circuit emits a single terminal boundary row.

`transition_link` is set after the full trace is built: pre → post for the same gate uses `link = 1`; post → next gate's pre uses `link = 1` when targets match and `link = 0` on the post row when they differ. AIR transition constraints apply only when $\texttt{transition\_link} = 1$ on the current row.

Executors may **fold** consecutive unary gates before emission (e.g. even-length `H(t)^n` or net-zero `RX` runs emit no rows). Physics always applies the full gate list; folding is an AIR-encoding detail only.

### 6.2 Supported Gate Alphabet

| `gate_id` | Opcode | Operational Semantics |
| --- | --- | --- |
| 0 | *(padding)* | Post-gate row or terminal boundary row. |
| 1 | `X` | Pauli-X. |
| 2 | `Y` | Pauli-Y. |
| 3 | `Z` | Pauli-Z. |
| 4 | `H` | Hadamard transformation. |
| 5 | `S` | Phase gate. |
| 6 | `T` | $\pi/8$ gate. |
| 7 | `CNOT` | Controlled-NOT. |
| 8 | `CZ` | Controlled-Z. |
| 9 | `CCNOT` | Toffoli (CCNOT). |
| 10–12 | `RX`, `RY`, `RZ` | Single-qubit parameterized rotations. |

`MEASURE`, `RESET`, and classically controlled `IF` gates do **not** appear in the unitary trace; mid-circuit measurement is handled by trajectory segmentation (§7.4).

### 6.3 Expanded AIR and Constraint Algebra

During proof generation, each 11-column trace row is expanded into 21 AIR columns: `gate_id`, ten one-hot gate selectors, then payload columns (`ctrl_active`×2, rotation params, amplitudes×4, `target_qubit`, `transition_link`). The AIR enforces five core constraint sets:

1. **Amplitude Continuity:** When $\texttt{transition\_link} = 1.0$, adjacent row registers sharing target wires must satisfy identity constraints.
2. **Linear Gate Semantics:** Enforces unitary transformations over $(v_0, v_1)$, e.g., Hadamard operations enforce:

$$\vert{}0\rangle \mapsto \frac{\vert{}0\rangle + \vert{}1\rangle}{\sqrt{2}}, \quad \vert{}1\rangle \mapsto \frac{\vert{}0\rangle - \vert{}1\rangle}{\sqrt{2}} \quad \text{}$$

3. **Selector Mutex:** Validates that exactly one gate selector column is active ($1.0$) per row, matching $\texttt{gate\_id}$.
4. **Control and Rotation Payload:** Validates $\texttt{ctrl\_active}$ / $\texttt{ctrl\_active\_2}$ discretization and rotation parameters ($\texttt{p\_cos}$, $\texttt{p\_sin}$) for controlled and parameterized gates.
5. **Boundary Identity:** Verifies that terminal row amplitudes match committed boundary values within $2^{30}$ fixed-point precision ($\texttt{FIXED\_POINT\_SCALE} = 10{,}000$).

### 6.4 State-Vector Leaf (sv-stark, v2)

The state-vector leaf proves a whole sub-task at once: applying the dispatched circuit to $\vert 0\ldots0\rangle$ yields a final state with a given digest, and, for `sample_counts`, the reported counts are that state's sampling under the dispatched seed. It is a Plonky3 STARK over Goldilocks² (not the Mersenne31 Circle PCS of §3.2 and §6.1–§6.3), with blowup 4, a 16-bit query proof of work, and the query count of §5.1's v2 column. The normative description of its arithmetic, gate fusion, digest, sampler and statement is `wqc-sv-stark`'s README in `wqc-stark-engine`; this section fixes what the protocol relies on.

* **Circuit as verifier.** The fused gate list and qubit count are preprocessed columns, so a proof verifies only against the verifier of the circuit it was built for. The orchestrator builds that verifier from the circuit it signed (`wqc_sv_leaf_new`, cached per circuit, shots, classical bits and tier) and never from anything the prover sends. The tier is part of the verifier too.
* **Statement.** `[context(4), digest(4), seed_lo, seed_hi, shots, counts_digest(4)]`, fifteen Goldilocks elements. `context` is SHA3-256 of `WQC_SV_CTX_V1` and the length-prefixed `circuit_id`, `sub_task_id`, `node_id`, `slice_id` of the dispatch, as four words reduced modulo the prime; `digest` is a Poseidon2 sponge over the final amplitudes; `counts_digest` is a Poseidon2 sponge over the counts vector indexed by register value. The verifier computes the expected statement from the dispatch it signed, the digest the node reported in its public inputs (for the root, the digest of the accepted result), the dispatched seed and the reported counts (which must be canonical: `counts_len` entries, each at most `shots`, summing to `shots`), and verifies the proof against it. The prover's own statement is never used.
* **Arithmetic.** Amplitudes are integers in units of $2^{-28}$; every gate output is rounded to nearest, ties up, and the rounding is proved by a range-checked identity. Execution is integer-only and bit-exact on any hardware; gate matrices are rounded once at build, after fusion, with rotation `sin`/`cos` from a pinned pure-Rust `libm`. The counts derive from that integer state, so honest nodes report the same counts and the same digest bit for bit; the quorum compares the counts.
* **Sampling.** Draws are words of a Poseidon2 permutation of the seed and a counter, rejected when at or above the total weight, so each shot picks basis state $b$ with probability $p_b / T$ exactly. This is not v1's `StdRng` sampler: the same seed gives different counts, from the same distribution.
* **Size.** $1 \le n \le 16$ qubits, $W \le 2^{22}$ gate rows ($W$ = rounding steps $\times\ 2^{n-1}$; monomial gates such as X, Z, CNOT, CZ add no rows), $1 \le$ `shots` $\le 2^{16}$, $1 \le$ `cbits` $\le 16$. A node advertises the $W$ it proves (`sv_max_rows`); the orchestrator dispatches a leaf only to nodes that cover it ([`p2p-protocols.md`](p2p-protocols.md) §6.1).
* **Gate fusion.** Runs of single-qubit gates on a qubit are multiplied in `f64` by one fixed rule and rounded once, and monomial gates are folded into a permutation-and-phase frame. The rule is part of the leaf format: changing it changes digests, so a new rule needs a new capability bit.

### 6.5 Mid-Circuit Circuits on the State-Vector Leaf

A `sample_counts` circuit with mid-circuit semantics (`RESET`, `IF`, or a unitary gate after a `MEASURE`) is proved by the state-vector leaf of §6.4 over the circuit `wqc-sv-stark`'s `wire::parse_leaf` rewrites it into, which defers every measurement to the end. The orchestrator, the node and the composer all derive the leaf from the signed circuit through that function; its README is normative. The rewriting is part of the leaf format (capability bit 6, [`p2p-protocols.md`](p2p-protocols.md) §4).

* `MEASURE q → c` emits nothing; `c` is now held by `q`.
* `IF(c == v) U` emits `U` with the qubit holding `c` added to its controls, between two X on that qubit when `v == 0`. A cbit never measured is 0, so `U` is kept for `v == 0` and dropped for `v == 1`. `U` is a one-qubit gate, CNOT or CZ; an IF of CCNOT has no state-vector leaf.
* `RESET q` emits nothing when `q` is untouched since the start or its last `RESET`; otherwise it swaps `q` into a fresh ancilla (two CNOTs), which keeps every cbit `q` held. No gate targets the ancilla again; it can only be the control an IF on one of those cbits adds. "Untouched" is conservative: a qubit used only as a control counts as touched.
* Each measured cbit is measured at the end from the qubit holding it.

The rewriting is exact because no gate may touch a measured qubit before its `RESET` ([`circuit-payload.md`](circuit-payload.md) §2.1): a measured qubit stays frozen in the Z basis, so measuring it at the end or using it as a quantum control gives the register the distribution the per-shot simulation samples, and an ancilla left unmeasured is traced out as `RESET` discards the old value. The counts are the leaf's sampling of that distribution, so they differ from the per-shot simulator's for the same seed. Each ancilla doubles the gate rows, and the qubit and row limits of §6.4 count the ancillas. A circuit without mid-circuit semantics is read exactly as before, so its leaf and digest are unchanged.


### 6.6 Scalar and Expectation Results on the State-Vector Leaf

A `statevector_scalar` or `expectation` task with a state-vector leaf is proved by the unitary leaf of §6.4 (no sampling), whose statement is `[context(4), digest(4)]`. The digest binds the final state but not the value the task reports, so the node also publishes the final integer state ([`p2p-protocols.md`](p2p-protocols.md) §7). The verifier checks that the state hashes to the proved digest and computes the values from it with `wqc-sv-stark`'s `outputs` (its README is normative):

* the `|0…0⟩` amplitude, the state's first amplitude divided by $2^{28}$;
* for each observable, $\sum_k c_k \langle\psi|P_k|\psi\rangle$ with $\langle\psi|P|\psi\rangle = \sum_i \overline{\psi_{P(i)}}\,\varphi_i\,\psi_i$ ([`circuit-payload.md`](circuit-payload.md) §7), summed exactly in integers and scaled once;
* every value rounded onto the $10^{-6}$ grid.

A node's reported values must equal these exactly. The leaf, its root (§8.5) and its format are unchanged; the published state is the only addition, gated by capability bit 7. The state is revealed, which WQC's results never hid.
---

## 7. Distribution and Trajectory Subsystems

### 7.1 Deterministic Sampling Pipeline

For `sample_counts` tasks, sample output histograms are validated by binding execution to a deterministic sampling pipeline:

```
Unitary STARK
  → Born / marginal probabilities (deterministic function of state)
    → PRNG(sample_seed) + inverse-CDF / Bernoulli draws (deterministic)
      → counts → output_hash

```

### 7.2 Probability Table Commitment

Distribution segments commit directly to `sample_seed`, target shot counts, `measurement_spec_hash`, a 32-byte `probability_digest`, and the explicit probability table.

The `probability_digest` is constructed as:

$$\texttt{probability\_digest} = \mathrm{SHA3\text{-}256}\left( \mathop{\parallel}_{i=0}^{2^n-1} \mathrm{LE\_f64}(P_i) \right)$$

### 7.3 Born Zero-Knowledge Proofs (`DistributionAir`)

`DistributionAir` constructs a streaming row trace over basis outcomes. Constraints enforce probability normalization ($\sum P_i = 1$), fixed-point conversion bounds, digest matching, and link consistency with the unitary execution proof. Soft limits cap streaming Born zk proofs to 16 qubits and 64 active table outcomes.

### 7.4 Mid-Circuit Trajectory Proofs

Non-unitary dynamic circuits split execution into state trajectory segments containing ordered measurement events:

$$\text{Event}_k = \left\{ \text{qubit}_k,\, \text{outcome}_k,\, \text{state\_digest}_k,\, p_0,\, p_1 \right\} \quad \text{}$$

Trajectory zk extensions evaluate Z-basis marginals per event and enforce $u \sim U[0, 1)$ Bernoulli draws driven by $\texttt{StdRng}(\texttt{shot\_seed})$ via gap-bit decomposition AIRs. Caps enforce $\le 16$ qubits for trajectory marginals and $\le 2048$ measurement events per path.

This is the v1 path. A mid-circuit circuit whose rewritten form has a state-vector leaf (§6.5) is proved by that leaf instead; the trajectory proof remains for the rest: noisy circuits, an IF of CCNOT, more than 16 qubits with ancillas, more than $2^{22}$ gate rows, no rounding step, and orchestrators running with v2 off.

---

## 8. Composition, Aggregation, and Recursive Verification

### 8.1 Binary Composition Structure (v3)

Multi-slice proofs are structured into a binary tree using v3 composition containers:

```
parent_task_id\0
<_WQC_COMPOSE_V3_>
compose_label\0; manifest_root_hash\0;
left_child_hash:32; right_child_hash:32;
left_len; left_bytes; right_len; right_bytes;   (right_len 0xFFFFFFFF: same bytes as left, none follow)
[AggregationAir tail (v4)]
[RecursiveAggregationAir tail (v6)]

```

Verifiers assert $\mathrm{SHA3\text{-}256}(\mathrm{child\_bytes}) == \mathrm{child\_hash}$ prior to dispatching child verification. Canonical leaf labels structure child dependencies:

| Composition Label | Left Child Target | Right Child Target |
| --- | --- | --- |
| `leaf:unitary_born` | Unitary STARK v2 + digests. | Born Leaf (`_M31_BORN_LEAF_V1_`). |
| `leaf:unitary_traj` | Unitary STARK v2 + link digest. | Trajectory Leaf (`_M31_TRAJ_LEAF_V1_`). |

### 8.2 Aggregation Modes and Soundness

| Aggregation Mode | Protocol Mechanism | Verifier Complexity | Soundness & Verification Bounds |
| --- | --- | --- | --- |
| **Direct Walk** | Structural binary traversal of v3 tree. | $\mathcal{O}(N)$ | Evaluates every child leaf natively. |
| **Digest Attestation** | `AggregationAir` (v4) tail. | $\mathcal{O}(1)$ | Asserts child digest integrity and host flags in-circuit. |
| **Recursive Aggregation** | `RecursiveAggregationAir` (v6) tail. | $\mathcal{O}(N)$ at the root: children are verified in full (§8.2 below) | RecAgg AIR asserts child digests / `pcs_ok`; PCS openings verified at compose/root via host digest + native FriFold/OOD (optional nested group STARKs when present). |

#### RecursiveAggregationAir (v6 Architecture)

The v6 recursive engine operates over an AIR width of 330. It validates left and right child proofs via side flags:

* `0`: Legacy composition (no PCS bundle).
* `1`: `AggPcsCertificate` (child aggregation node).
* `2`: `LeafPcsBundle` (leaf node: unitary, Born, or trajectory).
* `3`: right side only — same certificate or bundle as the left side, which is not repeated.

**Leaf DeepRo:** A `LeafPcsBundle` carries no DeepRo / DeepRoLeafTrace steps. The FriFold bind rebuilds each proven query's reduced opening the way `CirclePcs::verify` does: the DEEP quotient of the trace at $\zeta$ and $\zeta g$ and of every quotient chunk at $\zeta$, the $\lambda$ correction, and the first-layer `fold_y`, then folds it to `final_poly`; the opened rows are bound to the commitments by the Val Mmcs paths. A DeepRo step's AIR constrains only values that this recomputation already fixes. Leaf quotients in production are multi-chunk (16 chunks for a unitary leaf), and no leaf DeepRo STARK was produced before this change either; earlier builders proved them only for single-chunk quotients, and such bundles still verify with their steps. `wqc-stark-core` test `host_only_deep_ro_leaf_rejects_tampered_openings` changes a trace or quotient opening and expects the FriFold bind to reject it.

**Root fast path and aggregation children:** An `AggPcsCertificate` opens the child's `AggregationAir` proof, which attests the child's digests and nothing it proves. So when `verify_root_proof` takes the RecAgg path, it first checks each embedded child against its header digest and verifies every child in full, as the audit walk would. Aggregation children (an inner node, or a `leaf:unitary_born` / `leaf:unitary_traj` leaf) need it because their certificate attests digests only; leaf children are verified too, because a `LeafPcsBundle` checks PCS openings rather than the whole leaf STARK. Before this check, a root whose inner node embedded bytes that are no proof verified on the fast path. Verifying a Born root at `normal` takes 32 ms for one slice and 254 ms for eight (local, release build).

A composer pairing a lone child with itself (a single-slice task) sends that child once: the v3 `right_len` is `0xFFFFFFFF` and the v6 right side flag is `3`. The verifier reads the left bytes in their place, so every hash and check is the one it would run on the repeated form, which older composers wrote and which still verifies. The encoder uses the back-reference whenever the two sides are byte-equal; a verifier that predates it rejects such a root on the fast path and in the audit walk, so verifiers ship before composers.

Certificates embed Merkle commitments, FriFold evaluations, DeepRo trace bindings (host-native on both `AggPcsCertificate` and `LeafPcsBundle`; see **Leaf DeepRo** below), Val/Challenge Mmcs openings (host digest verify by default; optional nested group STARKs), and OOD witnesses (host-native fold by default; optional `OodCheckAir` STARK).

### 8.3 Leaf PCS Workflow and Delivery Architecture

#### Leaf PCS Bundles

Leaf nodes attach specialized PCS bundles matching their computational domain:

| Leaf Domain | LeafPcsBundle Composition |
| --- | --- |
| **Unitary** | $1 \times$ `LeafPcsCertificate` (`QuantumExecutionAir` OOD). |
| **Born** | $1 \times$ `LeafPcsCertificate` (`DistributionAir` OOD). |
| **Trajectory** | $N \times$ Marginal Certificates $+ 1 \times$ Shot Sampling Certificate. |

#### P2P Delivery Protocol

To keep PCS generation off the critical path, proof creation is delegated to a single quorum majority worker node at a time:

```
Orchestrator ─── /wqc/tensor-pcs-req/1.0.0 ───► Candidate Worker Node
                     │
                     │  (internal) POST /leaf_pcs ──► wqc-core
                     │  (internal) bundle or HTTP 422 ◄── wqc-core
                     │
Orchestrator ◄─── /wqc/tensor-pcs/1.0.0 ────── Candidate Worker Node
                     { leaf_pcs_b64 }  or  { refused: true, refuse_reason }

Orchestrator ─── /wqc/tensor-pcs-open/1.0.0 ──► All connected nodes (majority exhausted)
                     │
                     │  spill nodes: GET /sysinfo (core) → bid
                     │
Orchestrator ◄─── /wqc/tensor-pcs-bid/1.0.0 ── Spill-policy nodes
                     { pcs_memory_policy: "spill", leaf_proof_hash, ... }

```

1. **Request Dispatch:** At quorum, the orchestrator records the quorum majority node list and transmits an Ed25519-signed request containing `sub_task_id` and `node_id` over `/wqc/tensor-pcs-req/1.0.0` to the first slice proof winner.
2. **Candidate Build & Response:** The nominated node calls core `POST /leaf_pcs` with its retained leaf STARK proof. On success, core returns the encoded `LeafPcsBundle`; the node streams it to the orchestrator on `/wqc/tensor-pcs/1.0.0` as `leaf_pcs_b64`. If the PCS memory gate refuses (core HTTP 422, `PCS memory: ... (policy=refuse)`), the node permanently reports `refused: true` on `/wqc/tensor-pcs/1.0.0` (no retry). Only the currently nominated node may submit PCS for a slice.
3. **Failover & Compensation:** Upon refusal, the orchestrator records the refusing node, updates the slice proof winner (`StoreFinalSliceProof`) to the next quorum majority candidate that still holds a valid pending proof, and re-sends `/wqc/tensor-pcs-req/1.0.0` to that node. Storing a valid bundle compensates the successful candidate with $R_{\mathrm{pcs}}$ (40% of the slice fee).
4. **PCS Open Call (CAS builder market):** When all quorum majority candidates are exhausted and `WQC_PCS_OPEN_CALL_ENABLED` is true (default), the orchestrator uploads the proof winner's leaf STARK bytes to S3 (CAS key = SHA-256 hex), records `Phase=open_call`, and fans out a signed announcement on `/wqc/tensor-pcs-open/1.0.0`. Spill-policy nodes probe connected `wqc-core` `GET /sysinfo` → `pcs_memory_policy` and bid on `/wqc/tensor-pcs-bid/1.0.0` with `pcs_memory_policy: "spill"`. The orchestrator nominates the first valid bidder (first-wins), sends `/wqc/tensor-pcs-req/1.0.0` with `request_kind: "open_call"` and `leaf_proof_hash`, and pays $R_{\mathrm{pcs}}$ to the builder that delivers the bundle. The builder fetches the proof from the presigned CAS URL (no local retained proof required), verifies SHA-256, and calls core `POST /leaf_pcs`. On builder refusal or timeout (`WQC_PCS_OPEN_CALL_TIMEOUT_SECS`, default 1800s), the orchestrator re-publishes the open call with updated `refused_builders` until exhausted.
5. **Finalization & Fallback:** Compose waits until PCS is **satisfied** — a bundle is stored, or all quorum majority candidates are exhausted and (if enabled) the open-call round is exhausted (`OpenCallExhausted`). While `Phase=open_call` without a bundle, `Exhausted=true` alone does **not** satisfy compose. If no bundle arrives, the orchestrator waits up to `WQC_PCS_TIMEOUT_SECS` (default 7200s) for majority nomination when open call is disabled, then triggers a local fallback build (`build_leaf_pcs_bundle_from_child`), leaving $R_{\mathrm{pcs}}$ unpaid.

#### Artifact Footprint Analysis

Default deployment profiles set `WQC_PCS_MMCS_GROUP_CHUNK` to **24** (Mmcs group batch size; smaller values reduce peak RAM at the cost of larger wire payloads):

| Proof Artifact Type | Typical Binary Footprint |
| --- | --- |
| Single Leaf PCS Certificate | $\approx \text{5 MiB}$ |
| Encoded `LeafPcsBundle` | $\approx \text{6 MiB}$ |
| Two-Leaf Composed Root Artifact | $\approx \text{16 MiB}$ |

### 8.4 PCS Memory Gating Policy

To prevent Out-Of-Memory (OOM) failures during leaf/aggregation PCS build, core evaluates peak RAM usage prior to prove when `WQC_MAX_MEMORY_GB` is set. When unset, the memory gate is **disabled** (no refuse/spill enforcement).

**Host-only PCS (production):** nested Mmcs / FriFold / OOD group STARKs and DeepRo STARKs are empty; the estimate is dominated by proof decode, sibling buffers, and native digest/fold checks (typically well under a 2 GiB devnet budget at 40q). The historical blowup-16 Keccak group-prove matrix is no longer the dominant term.

When the gate is active and estimated RAM exceeds the budget, `WQC_PCS_MEMORY_POLICY` governs execution:

| Environment Variable | Default | Role |
| --- | --- | --- |
| `WQC_MAX_MEMORY_GB` | *(unset)* | Enables the PCS memory gate when set; unset disables gating. |
| `WQC_PCS_MEMORY_POLICY` | `refuse` | `refuse` (fail prove) or `spill` (auto-lower Mmcs chunk). Set on **wqc-core**; exposed via `GET /sysinfo` → `pcs_memory_policy` for node open-call bid gating. |
| `WQC_PCS_MMCS_GROUP_CHUNK` | `24` | Mmcs group chunk size for leaf/agg PCS prove (time vs wire trade-off). |
| `WQC_PCS_MEMORY_ESTIMATE_SCALE` | *(unset)* | Optional multiplier on the peak-RAM estimate. |

* **`refuse` (Default):** Terminates bundle generation with a stable error (`PCS memory: ... (policy=refuse)`), returning HTTP 422 from core. The node maps this to P2P `refused: true`; the orchestrator tries the next quorum majority node or, when exhausted, compose fallback.
* **`spill`:** Decrements the active Mmcs group chunk size (via session override of `WQC_PCS_MMCS_GROUP_CHUNK`) toward 1 until estimated memory falls within budget. If memory still exceeds budget at chunk size 1, the engine defaults to `refuse`.

### 8.5 State-Vector Root (v2)

A task whose leaves are state-vector leaves (§6.4) has a v2 root instead of the v3 / v6 tree above. The composer puts one recursion layer over each leaf proof, then aggregates the layers two at a time (an odd one is carried up) until one proof remains; a single leaf's root is its layer. The root's statement is the concatenation of the leaves' statements in leaf order, so it names every dispatch context, digest, seed and counts digest the leaves proved. The root bytes (`application/wqc-sv-root-v2`) are every recursion proof of the tree, layers first, root last.

The verifier rebuilds the tree from the leaves' circuits: for each leaf it derives the layer's verifier from the leaf's verifier (§6.4, never from the prover), checks the carried intermediate proof against the statement it expects, and uses the verified layer as the child of the next aggregation, up to the root. The orchestrator builds the expected statements from the results it accepted (the winning dispatch inputs and the final counts of each slice), so a leaf proof that does not carry them yields a root it rejects (`wqc_sv_verify_root`). The orchestrator also compares the estimated peak of that verification (`wqc_sv_root_peak_bytes`, about 320 MB for one leaf) with the memory it can spare before it dispatches the task.

A v2 task today has one leaf ([`p2p-protocols.md`](p2p-protocols.md) §6.1), so its root is one layer (about 195 KB at `low`), verified in about 4 s. The root is the task's proof root for the manifest and settlement like a v3 / v6 root (`wrap_root_hash` is the Keccak of its bytes), with one difference: it binds nothing beyond the leaf statements, so the manifest is matched against them by the verifier, outside the proof, where a v3 / v6 root carries `manifest_root_hash` in its statement. It has no SNARK wrap yet, so validity-proof settlement keeps tasks on v1 until [`zk-SNARK.md`](zk-SNARK.md) covers it.

---

## 9. Soft Operational Bounds

Operational caps for the noiseless simulation regime are defined as follows:

| Parameter Constraint | Soft Limit Value |
| --- | --- |
| Maximum Algebraic Born / Marginal Qubits | 16 qubits |
| Maximum Plonky3 Born zk Qubits | 16 qubits |
| Maximum Born zk Active Table Outcomes | 64 outcomes |
| Maximum Born Recursion Outcomes ($K$; RecAgg) | $K \le 21$ ($W \le 68$) |
| Maximum Trajectory Marginal zk Qubits | 16 qubits |
| Maximum Per-Shot Trajectory Events | 2048 events |
| Default / `ultra` FRI queries (outer STARKs + PCS cert slots) | 40 |
| `low` / `normal` / `high` FRI queries (outer ladder) | 8 / 16 / 32 |

Note: These constraints represent software engineering boundaries for current streaming AIR layouts and do not reflect fundamental cryptographic limits of the underlying zk-STARK protocol. FRI query counts by `security_level` are operational (see §5.1), not calibrated soundness claims.

---

## 10. End-to-End Verification Algorithm

A verifier executes the following deterministic validation pipeline upon receiving a proof artifact:

```
  ┌─────────────────────────────────────────────────────────┐
  │ Step 1: Marker Detection & Protocol Routing             │
  └────────────────────────────┬────────────────────────────┘
                               │
  ┌────────────────────────────▼────────────────────────────┐
  │ Step 2: Public Input (PI) Context Validation            │
  └────────────────────────────┬────────────────────────────┘
                               │
  ┌────────────────────────────▼────────────────────────────┐
  │ Step 3: Core STARK & Verification (v1/v2/v3 Traversal)  │
  └────────────────────────────┬────────────────────────────┘
                               │
  ┌────────────────────────────▼────────────────────────────┐
  │ Step 4: Sampling PRNG & Hash Determinism Check          │
  └────────────────────────────┬────────────────────────────┘
                               │
  ┌────────────────────────────▼────────────────────────────┐
  │ Step 5: Root Seal Registration & Digest Ledger Commit   │
  └─────────────────────────────────────────────────────────┘

```

1. **Marker Detection:** Reads protocol header markers (`_M31_QUANTUM_AIR_V1_`, `_M31_PLONKY3_STARK_V2_`, `_WQC_COMPOSE_V3_`), rejecting legacy or invalid markers.
2. **Public Input Context Binding:** Asserts equality between proof context $\mathsf{PI}$ and dispatch parameters (`circuit_id`, `sub_task_id`, `node_id`, `slice_id`, `output_hash`). When present, checks optional `MSH1` / `SEC1` bindings; Orchestrator `SubTask.security_level` must match any bound `SEC1` value (§5.1).
3. **Core STARK Verification:**
* *v1:* Re-expands execution trace, verifying $\texttt{air\_sum} == 0$ and matching boundary fixed-point constraints.
* *v2:* Reconstructs AIR from execution parameters, validating FRI proofs over Circle PCS with `num_queries` from `security_level` (unitary), alongside attached auxiliary segments.
* *v3:* Evaluates binary tree child hashes and recursively verifies child STARKs (and `AggregationAir` tails if present).
4. **Sampling Determinism Check:** Re-runs deterministic PRNG sampling over committed probability tables, asserting that calculated counts reproduce `output_hash`.
5. **Root Verification & Settlement:** Seals `proof_root_hash` and commits `root.bin` artifacts for network consensus settlement.

---

## 11. Discussion and Future Work

The WQC proof engine implements a scalable D-PoUW framework. By shifting proving overhead—including wide-memory state vector evolution, Number Theoretic Transforms (NTTs), and FRI commitments—to worker nodes, verification costs remain polylogarithmic.

Key research and optimization priorities include:

1. **Proof Footprint Reduction (pre-wrap size KPI signed off):** Idle two-leaf Poseidon compose roots are ≈ **169 KiB** (`173_483` B) under the ≤500 KB pre-wrap gate (host-only Mmcs/FriFold/OOD + Poseidon2 ValMmcs). Keccak-era documented baseline remains ≈ **10.2 MiB**.
2. **SNARK wrap of $\pi_{\text{Root}}$ (thick wrap track):** Normative wrap statement, thin vs thick guarantees, and on-chain finalize are specified in [`zk-SNARK.md`](zk-SNARK.md). Thin wrap toolchain and thin wrap KPI lock are done. Thick host gadgets (Mmcs / FriFold / OOD) are done; **thick wrap residual remains Partial** (`thick_fri_fs_auth_v0` N=40 + `thick_recagg_fri_fs_auth_v0` N=40 + OOD/AIR↔Auth + working N=1 `thick_unified_v0` ≤30M R1CS + leaf FriFsAuth + standalone child-verify / digest KPIs). Remaining for the wrap gate: Max→87KiB / deeper Auth / payload↔Auth, statement ≡ `verify_root_proof`, then audit + target-L2 gas (see `wqc-contracts` [`on-chain_settlement_scope.md`](https://github.com/world-qc/wqc-contracts/blob/main/docs/on-chain_settlement_scope.md) §7.2 / §7.6; internal gate track **E5b-3d** — glossary there). Thin wrap is not full on-L2 root validity.
3. **Recursive Protocol Refinements:** Streamlining prove-time witness extraction. The `security_level` → FRI query ladder (§5.1) covers Born / trajectory STARKs and variable-length leaf PCS / RecAgg certificates. Nested Mmcs / FriFold group STARKs default to the outer query count when proven; idle Poseidon host-only paths leave them empty (§5.1).
4. **Extended Zero-Knowledge Limits:** Expanding Born and trajectory zero-knowledge AIR capacity beyond current 16-qubit streaming bounds.
5. **Noise-Aware STARK Constraints:** Formally incorporating stochastic physical noise models (e.g., depolarizing channels and readout error operators) directly into the transition AIR.

---

## Appendix A. Protocol Transcript Markers

| Identifier Constant | Marker Byte String |
| --- | --- |
| `V1_MARKER` | `_M31_QUANTUM_AIR_V1_` |
| `V2_MARKER` | `_M31_PLONKY3_STARK_V2_` |
| `V3_COMPOSE_MARKER` | `_WQC_COMPOSE_V3_` |
| `LEGACY_MARKER` | `_M31_QUANTUM_AIR_STARK_` *(Rejected)* |
| `BORN_LEAF_MARKER` | `_M31_BORN_LEAF_V1_` |
| `TRAJ_LEAF_MARKER` | `_M31_TRAJ_LEAF_V1_` |
| `DIST_MARKER_V1` / `V2` | `_M31_DIST_V1_` / `_M31_DIST_V2_` |
| `BORN_TAIL_MARKER` | `_M31_BORN_TAIL_V1_` |
| `TRAJ_MARKER` | `_M31_TRAJ_V1_` / `_M31_TRAJ_V2_` |
| `TRAJ_STARK_MARKER` | `_M31_TRAJ_STARK_V1_` |
| `AGG_TAIL_MARKER` | `_WQC_AGG_TAIL_V4_` |
| `V4_AGG_INNER_MARKER` | `_WQC_AGG_STARK_V4_` |
| `REC_TAIL_MARKER` (v6) | `_WQC_REC_TAIL_V6_` |
| `V6_REC_AGG_INNER_MARKER` | `_WQC_REC_AGG_V6_` |
| `REC_TAIL_MARKER` (v5, legacy) | `_WQC_REC_TAIL_V5_` |
| `V5_REC_AGG_INNER_MARKER` | `_WQC_REC_AGG_V5_` |
| Measurement Spec Prefix | `MSH1` |
| Security Level Prefix | `SEC1` |

---

## Appendix B. Normative Binary Wire Layouts

All string fields are NUL-terminated UTF-8 sequence bytes. Multi-byte integers are encoded in Little-Endian (LE) format.

### B.1 v1 Unitary Proof Format (Embedded Trace)

```
<sub_task_id\0>
<_M31_QUANTUM_AIR_V1_>
<circuit_id\0><node_id\0><slice_id\0><output_hash\0>
[optional terminal_statevector_digest\0]
[optional MSH1<measurement_spec_hash>\0]
[optional SEC1<security_level>\0]
<trace_rows: u32 LE>
<trace: f64 LE array of size (trace_rows × 11)>
<air_sum: u32 LE>
<boundary_v0_re: u32 LE><boundary_v0_im: u32 LE>
<boundary_v1_re: u32 LE><boundary_v1_im: u32 LE>

```

### B.2 v2 Unitary Proof Format (Plonky3 STARK)

```
<sub_task_id\0>
<_M31_PLONKY3_STARK_V2_>
<circuit_id\0><node_id\0><slice_id\0><output_hash\0>
[optional terminal_statevector_digest\0]
[optional MSH1<measurement_spec_hash>\0]
[optional SEC1<security_level>\0]
<proof_len: u32 LE>
<proof: postcard-encoded p3_uni_stark::Proof>

```

### B.3 v3 Binary Composition Container

```
<parent_task_id\0>
<_WQC_COMPOSE_V3_>
<compose_label\0>
<manifest_root_hash\0>
<left_child_hash: 32 bytes>
<right_child_hash: 32 bytes>
<left_len: u32 LE><left_child: left_len bytes>
<right_len: u32 LE><right_child: right_len bytes>   (right_len 0xFFFFFFFF: right child = left child, no bytes follow)
[optional _WQC_AGG_TAIL_V4_ tail]
[optional _WQC_REC_TAIL_V6_ tail]

```

### B.4 Distribution Segment Format (v2)

```
<_M31_DIST_V2_>
<seed: u64 LE>
<shots: u32 LE>
<measurement_spec_hash: 64 ASCII hex chars>
<probability_digest: 32 bytes SHA3-256>
<probabilities: f64 LE array of size 2ⁿ>
[optional _M31_BORN_TAIL_V1_ tail]

```

### B.5 Trajectory Segment Format (v2)

```
<_M31_TRAJ_V2_>
[optional unitary_link_digest: 64 ASCII hex chars\0]
<event_count: u32 LE>
for each event:
  <measured_qubit: u32 LE>
  <outcome: u32 LE>
  <pre_measure_state_digest: 32 bytes>
  <p0: u32 LE fixed-point><p1: u32 LE fixed-point>
[optional _M31_TRAJ_STARK_V1_ tail]

```

### B.6 Aggregation Tail Format (v4)

```
<_WQC_AGG_TAIL_V4_>
<agg_len: u32 LE>
<_WQC_AGG_STARK_V4_>
<compose_label\0>
<manifest_root_hash\0>
<left_hash: 32 bytes><right_hash: 32 bytes>
<proof_len: u32 LE>
<proof: postcard-encoded p3_uni_stark::Proof>

```

### B.7 Recursive Aggregation STARK Format (v6)

```
<_WQC_REC_TAIL_V6_>
<rec_len: u32 LE>
  <parent_task_id\0>
  <_WQC_REC_AGG_V6_>
  <compose_label\0>
  <manifest_root_hash\0>
  <left_hash: 32 bytes><right_hash: 32 bytes>
  <left_stark_digest: 32 bytes><right_stark_digest: 32 bytes>
  <left_kind: u8><right_kind: u8>
  <left_side_bundle> <right_side_bundle>
  <proof_len: u32 LE>
  <proof: postcard-encoded RecursiveAggregationAir>

```

---

## Appendix C. Execution Trace AIR Reference

### C.1 Primary Execution Trace Columns

| Column Index | Field Name | Description |
| --- | --- | --- |
| 0 | `gate_id` | Operation opcode (§6.2). |
| 1 | `ctrl_active` | Primary control activation (`0.0` or `1.0`). |
| 2 | `ctrl_active_2` | Secondary control for CCNOT. |
| 3 | `p_cos` | Rotation parameter cosine. |
| 4 | `p_sin` | Rotation parameter sine. |
| 5 | `v0_re` | Target-qubit $\vert{}0\rangle$ amplitude (real). |
| 6 | `v0_im` | Target-qubit $\vert{}0\rangle$ amplitude (imaginary). |
| 7 | `v1_re` | Target-qubit $\vert{}1\rangle$ amplitude (real). |
| 8 | `v1_im` | Target-qubit $\vert{}1\rangle$ amplitude (imaginary). |
| 9 | `target_qubit` | Logical wire index for columns 5–8. |
| 10 | `transition_link` | `1.0` if the next row continues the same target wire. |

### C.2 Expanded AIR Column Layout

`wqc-stark-core` expands each 11-column trace row into $\texttt{AIR\_WIDTH} = 21$ columns:

| AIR Col | Source | Description |
| --- | --- | --- |
| 0 | trace col 0 | `gate_id` |
| 1–10 | `gate_id` expansion | One-hot selectors (`X`, `Y`, `Z`, `H`, `S`, `T`, `CNOT`, `CZ`, `CCNOT`, `ROT`) |
| 11–12 | trace cols 1–2 | `ctrl_active`, `ctrl_active_2` |
| 13–14 | trace cols 3–4 | `p_cos`, `p_sin` |
| 15–18 | trace cols 5–8 | `v0_re`, `v0_im`, `v1_re`, `v1_im` |
| 19 | trace col 9 | `target_qubit` |
| 20 | trace col 10 | `transition_link` |

Selector index for gate id $g$: $1..=6 \to g-1$; CNOT ($7$) $\to 6$; CZ ($8$) $\to 7$; CCNOT ($9$) $\to 8$; RX/RY/RZ ($10..=12$) $\to 9$. Padding ($g = 0$) activates no selector.

---

## References

1. World Quantum Computer Whitepaper v0.4, §3.3–3.5 — Recursive Aggregation, Polymorphic Outputs, and SNARK Wrap.
2. Polygon Plonky3 Architecture — Uni-STARK Engine, Circle PCS, and FRI over Mersenne31.
3. Eli Ben-Sasson, Iddo Bentov, Ynon Horesh, and Michael Riabzev. *Scalable, transparent, and post-quantum secure computational integrity* (STARK Foundations).
4. WQC [`zk-SNARK.md`](zk-SNARK.md) — SNARK wrap of $\pi_{\text{Root}}$ for L2 settlement.
