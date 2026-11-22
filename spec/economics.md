# WQC D-PoUW economics

- **Status:** Draft
- **Tier:** A (canonical protocol spec)
- **Audience:** Protocol designers, contract authors, and implementers who need the normative fee and settlement rules
- **Related:** [`architecture.md`](architecture.md), [`architecture-current.md`](architecture-current.md), [`zk-SNARK.md`](zk-SNARK.md), [`../whitepaper/WHITEPAPER_0.5_en.md`](../whitepaper/WHITEPAPER_0.5_en.md)

This document is the **normative** economics specification: units, gas, reward splits, escrow, economics receipts, and on-chain settlement. It does not define Redis keys, environment variables, or HTTP paths — those live in [`architecture-current.md`](architecture-current.md) §4.

Supply curve, foundation allocation narrative, and vesting story remain in the whitepaper. A dedicated `/tokenomics` package (fair-launch ops, vesting contract surface) may still be added later; it must not contradict this file.

---

## 1. Token units

| Unit | Symbol | Scale | Usage |
| --- | --- | --- | --- |
| **WQC** | \$WQC | $10^{0}$ | Human-facing token (max supply **210,000,000 WQC**) |
| **Shannon** | sWQC | $10^{-9}$ WQC | **BaseFee** — price per gas unit |
| **Planck** | pWQC | $10^{-18}$ WQC | All ledger and settlement integers |

All fee, reward, burn, and escrow amounts are **Planck integers**. No floating-point settlement math.

---

## 2. Billing unit and gas

The atomic billing unit is one **sub-task** (one slice execution + one leaf STARK). An exact-tree scalar slice is the full parent register ([`contraction-tree.md`](contraction-tree.md)). Every other slice is a compact register.

```
Gas_quantum = α·VRAM_MiB + β·GateCount + γ·TraceRows
fri_bps     = tier table (below): low 5000, normal 10000, high 20000, ultra 25000
TotalFee    = Gas_quantum × BaseFee × 10^9 × fri_bps / 10000
              (pWQC; BaseFee in sWQC / gas; normal tier is fri_bps = 10000)
R_compute   = TotalFee × 40 / 100             (pWQC, per quorum majority node)
R_pcs       = TotalFee × 40 / 100             (pWQC, once per slice PCS delivery)
Burn        = TotalFee × 20 / 100             (pWQC)
R_net       = R_compute + R_pcs               (80%, worker budget)
```

| Symbol | Meaning | Normative source |
| --- | --- | --- |
| `VRAM_MiB` | Peak workspace size | Scalar with an exact tree ([`contraction-tree.md`](contraction-tree.md)): $\lceil \mathrm{peak\_bytes} / 2^{20} \rceil$. Other scalar (`statevector_scalar`, or an empty `output_mode`) with no tree: $\lceil N \chi^{2} \times 32 / 2^{20} \rceil$ with $\chi = \min(\mathrm{task}, 128)$ (task χ 0 means 128). `sample_counts` and `expectation`: $\lceil 2^{q} \times 16 / 2^{20} \rceil$ for compact width $q$ |
| `GateCount` | Pruned gate list length | Length of the dispatched circuit |
| `TraceRows` | STARK execution trace rows | Attested in the work report (fallback: $\max(4, \mathrm{GateCount}+1)$) |
| `BaseFee` | WQC per gas, stored as sWQC | Locked per parent task at submit; may adjust globally between tasks |
| `fri_bps` | TotalFee scale vs `normal`, per tier | `low` 5000, `normal` 10000, `high` 20000, `ultra` / empty / unknown 25000 |

`fri_bps` prices prove and verify work. It is a table per tier, not a function of a proof system's query count: the fee is quoted before a sub-task is sent as a v1 or a v2 leaf, and the two ladders differ (v1 8 / 16 / 32 / 40 queries, sv-stark v2 22 / 32 / 37 / 42; [`zk-STARK.md`](zk-STARK.md) §5.1). Quorum size is a separate multiplier in the escrow bound (§3.1): `normal` and `high` both use `required_votes = 2`, so their price gap is the FRI factor alone (`high` = 2× `normal`). Quote and settlement apply the same `fri_bps` to `TotalFee` before the 40/40/20 split. Integer division is in Planck.

VRAM is measured in **MiB**, not KiB, so default coefficients keep per-slice rewards compatible with the 210M supply.

Default coefficient intent: $\alpha = \beta = \gamma = 1$. Implementations may expose overrides; changing defaults is a Tier A substantive change.

### 2.1 Roles paid from `TotalFee`

| Role | Count | Earns |
| --- | --- | --- |
| **Quorum majority** | up to `required_votes` | `R_compute` each |
| **PCS delivery** | exactly one successful delivery per slice | `R_pcs` once |
| **Burn reserve** | per slice | `Burn` (may fund stragglers; remainder burned) |

PCS delivery may be: the nominated leaf-proof winner, an open-call spill builder, or a composer-operator fallback when the swarm does not deliver. Prebuilt PCS is paid once; composer fallback is not double-paid.

| Kind | Payout | Burn interaction |
| --- | --- | --- |
| Quorum majority | `R_compute` | 20% reserved; settled at task finalize |
| PCS delivery | `R_pcs` | none |
| Straggler (correct late result) | 5% of the slice's canonical `R_compute` | paid from deferred burn |
| Trapdoor pass | 50% of `R_compute` | none |
| Slash | confiscate as specified by governance | — |

Straggler bonuses use the **canonical** slice `R_compute`, not the straggler's own heavier work report. Effective burn may be **below 20%** when stragglers are paid from the reserve; the client is still charged the 20% portion exactly once (as payout or burn).

### 2.2 Accrual vs chain settlement

Off-chain ledgers (testnet Redis) may **accrue** rewards at quorum / PCS / straggler time for operator UX. That accrual is an implementation detail.

**Normative on-chain settlement** finalizes a parent task in **one atomic settlement** after the economics receipt is determined (see §5). Partial on-chain transfers per slice are not required.

---

## 3. Escrow and BaseFee

1. Client obtains a quote from compact-register bounds and current BaseFee.
2. At submit, escrow is locked and **BaseFee for that task is fixed**.
3. Global BaseFee may move with queue depth between tasks (supply/demand signal).
4. After work completes (and any straggler grace), burns settle and unused escrow is refunded.

### 3.1 Quote bound

```
estimated_slices = 1                  (2^30, and rejected, for a scalar that cannot run as one leaf)
TotalFee         = Gas_quantum × BaseFee × 10^9 × fri_bps / 10000
per_slice        = TotalFee × (0.40×required_votes + 0.40 + 0.20)
escrow           = estimated_slices × per_slice × safety_factor
```

Slicing fixes only wires no gate touches, each with its `0` branch, so every task is one leaf ([`mps-scalar.md`](mps-scalar.md) §4) and `estimated_slices` is 1. For `sample_counts` and `expectation` the leaf is priced at a compact width of at most 26 qubits (the slice scheduler's dense width, implementation default). A scalar task (`statevector_scalar`, or empty `output_mode`) is priced at a stand-in width of 2048 qubits (one χ=128 MPS in 1 GiB) when no circuit is given. With a circuit whose exact tree (state or network) fits, `estimated_slices` is 1 and `VRAM_MiB` is the tree peak ([`contraction-tree.md`](contraction-tree.md)); that quote is not saturated, including when the MPS rules would reject the circuit. Otherwise, with a circuit, `estimated_slices` follows the MPS rules of [`mps-scalar.md`](mps-scalar.md) §§4–5, and is 1 or a rejection. On the MPS path, and only on it, the node is given the parent site order: fixed qubits are removed and the survivors are packed into the compact register. It does not recompute a new order on the pruned circuit. A tree dispatch leaves `mps_site_order` empty. A cut crossed by w two-qubit gates, with m sites on its smaller side, has width `2^min(w, m)`. A one-site side stays at width 2 however many gates touch that qubit. The estimate is 1 when the wires a gate touches fit in 2048 qubits and every cut is within χ=128, for example a nearest-neighbor chain, or when the register fits and a time split keeps both halves under the overlap budget (χ≤16, or ≤8 with swap margin). Otherwise it is 2^30, and the quote or submit is rejected; fixing a touched wire would drop its gates, and fixing an idle wire does not narrow a cut. The estimate also refuses more than 100000 gates or 4096 qubits, and reports 2^30. The quote gate and qubit check applies to every output mode. Stragglers do not increase the escrow bound; they draw from deferred burn.

---

## 4. Identities (economic)

| Identity | Role |
| --- | --- |
| **peer_id / node_id** | libp2p transport and STARK public-input binding |
| **operator** | Economic subject (Ed25519 key; testnet often derived from a Node Key `nk_…`) |
| **operator_id** | `sha256(operator Ed25519 pubkey)` — off-chain ledger key on testnet |
| **payout address** | EVM `0x` address that receives on-chain rewards |

Testnet may keep balances under `operator_id` without a chain address. Mainnet payouts require a registered **payout address**.

**Payout registration (mainnet):** the operator Ed25519 key signs a binding of the payout address (and chain id / nonce). The orchestrator (Phase 3) stores the binding and uses it when building the settlement payout list. An on-chain registry is optional later; Phase 3 does not require PeerID bytes on-chain if settle calldata already lists `0x` recipients.

---

## 5. Settlement lifecycle

Testnet may **accrue** the fee, escrow, and ledger rules from §§2–4 off-chain. Mainnet adds **atomic on-chain settlement** (§5.2) after an economics receipt (§5.1). The rules are the same; only the settlement layer changes.

### 5.1 Economics receipt

After finalize, an economics receipt commits to escrow locked / debited / refunded, burns, rewards, per-slice breakdown, and the **payees** (each rewarded operator once, with its total reward, ordered by `operator_id`), hashed (SHA3-256) separately from the compute manifest. The receipt is published with its `receipt_hash` field empty, and the hash is over exactly the published bytes, so a checker hashes the file as downloaded. With on-chain settlement each payee carries its payout binding on the settle chain as it is at finalize (address, nonce, the operator's public key and signature), and settlement pays exactly the payees at those addresses; a later change of address does not apply to the task. The reward of an operator without a binding at finalize is refunded to the client: that operator is not a payee, and the receipt lists it with its amount (`unbound_payees`) and the total (`unbound_refund_pwqc`, included in the refund). The hash is what settlement references.

### 5.2 On-chain settlement (decided)

Phase 3 keeps a **single orchestrator** for routing. Settlement moves on-chain as follows:

1. **Atomic finalize.** After off-chain work and the economics receipt, one settlement transaction (or one logical settlement action) applies: verify commitment, pay recipients, burn, refund remainder. No mandatory per-slice on-chain debits.
2. **Optimistic root commitment.** The chain stores `task_id`, `root_hash`, `manifest_digest` / receipt commitment, and the payout vector. Full in-EVM verification of $\pi_{\text{Root}}$ is **out of scope for the initial on-chain design** (current root artifacts are multi-MiB). A challenge window allows dispute via re-verification with the off-chain verifier; unresolved fraud proofs escalate per governance.
3. **SNARK-wrap validity path.** Mainnet validity finalize verifies a succinct Groth16 wrap $\pi_{\text{snark}}$ of $\pi_{\text{Root}}$ (thin wrap as an intermediate statement; the v2 wrap re-runs the v2 root's verifier). Normative wrap protocol: [`zk-SNARK.md`](zk-SNARK.md).
4. **Signed payout registration.** Operators bind an `0x` payout address with an Ed25519 signature before they can receive on-chain rewards. The orchestrator publishes each binding with the operator's public key and signature, so anyone can check that a settled payout address is the operator's own.
5. **Relayer.** Phase 3 may use the orchestrator (or a designated relayer) to submit settle transactions. Permissionless settle using the same commitments is a compatible extension.

Escrow lock / client deposit UX, token contract, burn address, and challenge duration are deployment parameters; they must preserve Planck integer accounting and the 40/40/20 intent above.

Out of scope for on-chain settlement: DHT multi-orchestrator, replacing libp2p PeerID with an EVM address, or requiring testnet to issue `0x` balances before mainnet.

---

## 6. Worked examples

### Small circuit

2 qubits, 1 gate, 4 trace rows, BaseFee $= 0.001$ WQC/gas, `security_level = normal` (`fri_bps = 10000`):

```
Gas        = 6
TotalFee   = 0.006 WQC
R_compute  = 0.0024 WQC (per majority node)
R_pcs      = 0.0024 WQC
Burn       = 0.0012 WQC
```

The same circuit at `high` (`fri_bps = 20000`) has TotalFee $= 0.012$ WQC. At `low` it is $0.003$ WQC. At `ultra` it is $0.015$ WQC.

### ~26-qubit slice (`sample_counts` / `expectation`)

Dense workspace. `security_level = normal`:

```
VRAM_MiB ≈ 1024, GateCount ≈ 50, TraceRows ≈ 100
Gas      ≈ 1174
TotalFee ≈ 1.174 WQC
```

`high` on the same slice is $\approx 2.348$ WQC before the quorum coefficient. With `required_votes = 2` the client per-slice bound is $1.4\times$ that TotalFee for both tiers, so `high` escrow is twice `normal`.

A 50-qubit scalar slice at χ = 128 has workspace $\lceil 50 \times 128^{2} \times 32 / 2^{20} \rceil = 25$ MiB. A scalar parent whose circuit is a chain, and which fits in 2048 qubits, is one slice. A 50-qubit scalar whose widest site-order cut has width above 128 is still one slice when a time split fits; it becomes two (or more) only when that cutwidth exceeds χ and no time split fits — not `2^(50-26)`. Dispatch still uses each bid's `max_mps_qubits` for the memory stop; the bond stop is that cutwidth / time-split plan ([`mps-scalar.md`](mps-scalar.md) §5).

---

## 7. See also

- [`architecture.md`](architecture.md) §6–8 — trust, settlement contract, migration
- [`architecture-current.md`](architecture-current.md) §4 — live Redis / env / HTTP / receipt wiring
- [`contraction-tree.md`](contraction-tree.md) — scalar whose `VRAM_MiB` is the tree peak and whose `estimated_slices` is 1
- [`zk-SNARK.md`](zk-SNARK.md) — SNARK wrap for on-chain validity finalize
- [`../whitepaper/WHITEPAPER_0.5_en.md`](../whitepaper/WHITEPAPER_0.5_en.md) §4 — supply, burn narrative, vesting
