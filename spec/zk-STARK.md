# Zero-Knowledge STARKs for Trustless Distributed Quantum Simulation

**A Formal Protocol Specification for the World Quantum Computer (WQC) Cryptographic Proof Engine**

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
* Binary recursive composition trees, including v4 `AggregationAir` and v6 `RecursiveAggregationAir` with in-circuit out-of-domain (OOD) PCS verification.
* `security_level` → FRI query ladder for leaf unitary / Born / trajectory prove/verify and outer AggregationAir / RecAgg / leaf PCS certificates (§5.1). Nested FriFold/DeepRo/Mmcs sub-STARKs keep a fixed 40-query config.
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
| `statevector_scalar` | Unitary contraction of a target amplitude scalar. | None. |
| `sample_counts` (Terminal) | Unitary state evolution of the measured sub-circuit. | Born rule distribution commitment + deterministic PRNG sampling. |
| `sample_counts` (Mid-Circuit) | Unitary segment traces bounded by measurement gates. | Sequential trajectory event stream + zk marginal/shot proofs. |
| `expectation` | Algebraic expectation calculation over contracted state. | Result payload digest binding. |

---

## 3. Mathematical Preliminaries

### 3.1 Algebraic Intermediate Representation (AIR)

Computational logic is framed as an execution trace matrix $T \in \mathbb{F}^{T_{\mathrm{rows}} \times T_{\mathrm{cols}}}$. Valid state transitions are expressed as a set of multivariate transition polynomials $P_j(X_0, \dots, X_{W-1}, Y_0, \dots, Y_{W-1})$ such that $P_j(T_{i, \star}, T_{i+1, \star}) = 0$ for all valid row transitions $i$. The quotient polynomial $Q(X) = \frac{C(T(X))}{Z_H(X)}$ is committed via Circle PCS and evaluated at randomized out-of-domain challenge points using FRI.

### 3.2 Field & Polynomial Commitment Scheme

* **Base Field:** Mersenne31 ($\mathbb{F}_p$, where $p = 2^{31} - 1$).
* **Commitment Scheme:** Circle PCS implemented via Polygon Plonky3.
* **Serialization:** Postcard serialization format encoding `p3_uni_stark::Proof` structures.
* **FRI queries:** Circle config `num_queries` is selected from the Orchestrator `security_level` for leaf unitary / Born / trajectory STARKs and for outer AggregationAir / RecAgg proofs (see §5.1). Leaf and aggregation PCS certificates use runtime `n = proof.query_proofs.len()` (capped at 40). Nested FriFold / DeepRo / Mmcs uni-STARKs keep fixed 40-query configs. Empty / unknown level defaults to $40$ (`DEVNET_FRI_NUM_QUERIES`). This ladder is an **operational cost/throughput control**, not a claim of calibrated soundness bits.

Legacy transcript profile v1 embeds uncompressed floating-point traces evaluated via explicit verifier sumchecks, whereas production profile v2 commits traces via Circle PCS.

### 3.3 Notation

Let $\pi$ denote a proof artifact, $\mathsf{PI}$ the public-input vector, and $H(x)$ the SHA3-256 cryptographic digest function. Binary strings are represented as NUL-terminated C-strings, and digest values are represented either as raw 32-byte arrays or 64-character ASCII hexadecimal strings.

---

## 4. Architecture Overview

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
| `circuit_id` | Mandatory | SHA3-256 hash of the canonical pruned circuit specification. |
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

Client `security_level` already drives quorum (`required_votes`) and bid policy. The same tier is copied onto each signed `SubTask` dispatch and threaded orch → node → `wqc-core` for leaf prove/verify, then through compose / RecAgg for the whole task tree (CGO FFI passes the level into leaf and root verifiers).

| `security_level` | FRI `num_queries` |
| --- | ---: |
| `low` | 8 |
| `normal` | 16 |
| `high` | 32 |
| `ultra` (or empty / unknown) | 40 |

**Binding and authority:**

* When non-empty, unitary prove appends `SEC1<security_level>\0` after optional `MSH1…` in the leaf PI binding (Appendix B.1 / B.2). Born / trajectory inherit the parent context level without a separate `SEC1` tag.
* Orchestrator verify uses `SubTask.security_level` as authoritative. If a unitary proof binds a different `SEC1` value, verification fails.
* Prove and verify must use the **same** query count; mismatched ladders reject the Plonky3 proof.
* PCS certificates take `n` from `proof.query_proofs.len()` and optionally cross-check against `fri_num_queries_for_security_level(level)`. Wire vectors are length-prefixed with `1 <= n <= 40`.

**Scope:** Outer Circle STARKs (unitary, Born, trajectory, AggregationAir, RecAgg) and leaf/agg PCS query slots follow this ladder. Nested FriFold / DeepRo / Mmcs **internal** uni-STARKs remain on fixed 40-query Circle/Keccak configs; only the count of outer FRI query slots varies.

**Why nested sub-STARKs stay at 40:** Outer `n` is the number of FRI query *slots* that PCS / RecAgg materialize (Mmcs paths, FriFold chains, DeepRo steps per query). That slot count dominates prove time and certificate size, so binding it to `security_level` is the operational lever. Each nested FriFold / DeepRo / Mmcs proof is a *separate* small uni-STARK that attests one path or fold step; its own Circle/Keccak `num_queries` is an implementation parameter of that sub-proof, not “how many outer queries the parent opened.” Keeping nested configs fixed at the ladder ceiling avoids resizing nested AIR public inputs, soft caps, and prove/verify pairing for every sub-STARK while still cutting the dominant outer work for `low` / `normal` / `high`. Making nested `num_queries` follow the ladder is intentionally out of scope.

**Risk of fewer outer queries:** FRI soundness error decreases as more random queries are checked; lowering `n` (e.g. `ultra` $40$ → `low` $8$) increases the chance that a malicious or buggy proof escapes detection for a given hash/FRI parameter set. In this stack the ladder is an **operational cost/throughput control**, not a claim that `low` / `normal` / `high` achieve calibrated bit-security targets. Clients and operators should treat lower tiers as accepting higher residual FRI soundness risk (and smaller / faster proofs) relative to `ultra`, and must not infer cryptographic security levels from the table above. Prove and verify must still use the same `n`; a mismatch is a hard reject, not a soft downgrade.

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

---

## 8. Composition, Aggregation, and Recursive Verification

### 8.1 Binary Composition Structure (v3)

Multi-slice proofs are structured into a binary tree using v3 composition containers:

```
parent_task_id\0
<_WQC_COMPOSE_V3_>
compose_label\0; manifest_root_hash\0;
left_child_hash:32; right_child_hash:32;
left_len; left_bytes; right_len; right_bytes;
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
| **Recursive Aggregation** | `RecursiveAggregationAir` (v6) tail. | $\mathcal{O}(1)$ | Complete in-circuit verification via PCS certificates and OOD checks. |

#### RecursiveAggregationAir (v6 Architecture)

The v6 recursive engine operates over an AIR width of 330. It validates left and right child proofs via side flags:

* `0`: Legacy composition (no PCS bundle).
* `1`: `AggPcsCertificate` (child aggregation node).
* `2`: `LeafPcsBundle` (leaf node: unitary, Born, or trajectory).

Certificates embed Merkle/Keccak commitments, FriFold evaluations, DeepRo trace bindings, in-circuit FRI Validation/Challenge Mmcs proofs, and `OodCheckAir` constraints.

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

To prevent Out-Of-Memory (OOM) failures during the blowup-16 Keccak Mmcs phase, core evaluates peak RAM usage prior to leaf/aggregation PCS prove when `WQC_MAX_MEMORY_GB` is set. When unset, the memory gate is **disabled** (no refuse/spill enforcement).

When the gate is active and estimated RAM exceeds the budget, `WQC_PCS_MEMORY_POLICY` governs execution:

| Environment Variable | Default | Role |
| --- | --- | --- |
| `WQC_MAX_MEMORY_GB` | *(unset)* | Enables the PCS memory gate when set; unset disables gating. |
| `WQC_PCS_MEMORY_POLICY` | `refuse` | `refuse` (fail prove) or `spill` (auto-lower Mmcs chunk). Set on **wqc-core**; exposed via `GET /sysinfo` → `pcs_memory_policy` for node open-call bid gating. |
| `WQC_PCS_MMCS_GROUP_CHUNK` | `24` | Mmcs group chunk size for leaf/agg PCS prove (time vs wire trade-off). |
| `WQC_PCS_MEMORY_ESTIMATE_SCALE` | *(unset)* | Optional multiplier on the peak-RAM estimate. |

* **`refuse` (Default):** Terminates bundle generation with a stable error (`PCS memory: ... (policy=refuse)`), returning HTTP 422 from core. The node maps this to P2P `refused: true`; the orchestrator tries the next quorum majority node or, when exhausted, compose fallback.
* **`spill`:** Decrements the active Mmcs group chunk size (via session override of `WQC_PCS_MMCS_GROUP_CHUNK`) toward 1 until estimated memory falls within budget. If memory still exceeds budget at chunk size 1, the engine defaults to `refuse`.

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

1. **Proof Footprint Reduction:** Shrinking recursive proof artifacts (currently $\approx 16\text{ MiB}$ for two-leaf composed roots) via Poseidon2 recursion-friendly hashes within Mmcs folding circuits.
2. **Recursive Protocol Refinements:** Streamlining prove-time witness extraction and expanding multi-chunk leaf DeepRo structures. The `security_level` → FRI query ladder (§5.1) now covers Born / trajectory STARKs and variable-length leaf PCS / RecAgg certificates (nested FriFold/DeepRo/Mmcs internals remain 40-query configs).
3. **Extended Zero-Knowledge Limits:** Expanding Born and trajectory zero-knowledge AIR capacity beyond current 16-qubit streaming bounds.
4. **Noise-Aware STARK Constraints:** Formally incorporating stochastic physical noise models (e.g., depolarizing channels and readout error operators) directly into the transition AIR.

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
<right_len: u32 LE><right_child: right_len bytes>
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

1. World Quantum Computer Whitepaper v0.3, §3.3–3.4 — Recursive Aggregation and Polymorphic Outputs.
2. Polygon Plonky3 Architecture — Uni-STARK Engine, Circle PCS, and FRI over Mersenne31.
3. Eli Ben-Sasson, Iddo Bentov, Ynon Horesh, and Michael Riabzev. *Scalable, transparent, and post-quantum secure computational integrity* (STARK Foundations).
