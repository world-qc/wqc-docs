# WQC D-PoUW economics

- **Status:** Draft
- **Tier:** A (canonical protocol spec)
- **Audience:** Protocol designers, contract authors, and implementers who need the normative fee and settlement rules
- **Related:** [`architecture.md`](architecture.md), [`architecture-current.md`](architecture-current.md), [`../whitepaper/WHITEPAPER_0.3_en.md`](../whitepaper/WHITEPAPER_0.3_en.md)

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

The atomic billing unit is one **sub-task** (one compact-register slice execution + one leaf STARK).

```
Gas_quantum = α·VRAM_MiB + β·GateCount + γ·TraceRows
TotalFee    = Gas_quantum × BaseFee × 10^9     (pWQC; BaseFee in sWQC / gas)
R_compute   = TotalFee × 40 / 100             (pWQC, per quorum majority node)
R_pcs       = TotalFee × 40 / 100             (pWQC, once per slice PCS delivery)
Burn        = TotalFee × 20 / 100             (pWQC)
R_net       = R_compute + R_pcs               (80%, worker budget)
```

| Symbol | Meaning | Normative source |
| --- | --- | --- |
| `VRAM_MiB` | Peak workspace size | $\lceil 2^{q} \times 16 / 2^{20} \rceil$ for compact width $q$ |
| `GateCount` | Pruned gate list length | Length of the dispatched circuit |
| `TraceRows` | STARK execution trace rows | Attested in the work report (fallback: $\max(4, \mathrm{GateCount}+1)$) |
| `BaseFee` | WQC per gas, stored as sWQC | Locked per parent task at submit; may adjust globally between tasks |

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
estimated_slices = max(1, 2^(qubits - target_width))
per_slice        = TotalFee × (0.40×required_votes + 0.40 + 0.20)
escrow           = estimated_slices × per_slice × safety_factor
```

`target_width` is the compact-register BFS threshold used by the slice scheduler (implementation default 26). Stragglers do not increase the escrow bound; they draw from deferred burn.

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

After finalize, an economics receipt commits to escrow locked / debited / refunded, burns, rewards, and per-slice breakdown, hashed (SHA3-256) separately from the compute manifest. Implementations publish it to CAS; the hash is what later settlement references.

### 5.2 On-chain settlement (decided)

Phase 3 keeps a **single orchestrator** for routing. Settlement moves on-chain as follows:

1. **Atomic finalize.** After off-chain work and the economics receipt, one settlement transaction (or one logical settlement action) applies: verify commitment, pay recipients, burn, refund remainder. No mandatory per-slice on-chain debits.
2. **Optimistic root commitment.** The chain stores `task_id`, `root_hash`, `manifest_digest` / receipt commitment, and the payout vector. Full in-EVM verification of $\pi_{\text{Root}}$ is **out of scope for the initial on-chain design** (current root artifacts are multi-MiB). A challenge window allows dispute via re-verification with the off-chain verifier; unresolved fraud proofs escalate per governance. Full on-chain STARK/SNARK verify is a later track (proof footprint reduction or wrapping).
3. **Signed payout registration.** Operators bind an `0x` payout address with an Ed25519 signature before they can receive on-chain rewards.
4. **Relayer.** Phase 3 may use the orchestrator (or a designated relayer) to submit settle transactions. Permissionless settle using the same commitments is a compatible extension.

Escrow lock / client deposit UX, token contract, burn address, and challenge duration are deployment parameters; they must preserve Planck integer accounting and the 40/40/20 intent above.

Out of scope for on-chain settlement: DHT multi-orchestrator, replacing libp2p PeerID with an EVM address, or requiring testnet to issue `0x` balances before mainnet.

---

## 6. Worked examples

### Small circuit

2 qubits, 1 gate, 4 trace rows, BaseFee $= 0.001$ WQC/gas:

```
Gas        = 6
TotalFee   = 0.006 WQC
R_compute  = 0.0024 WQC (per majority node)
R_pcs      = 0.0024 WQC
Burn       = 0.0012 WQC
```

### ~26-qubit slice

```
VRAM_MiB ≈ 1024, GateCount ≈ 50, TraceRows ≈ 100
Gas      ≈ 1174
TotalFee ≈ 1.174 WQC
```

---

## 7. See also

- [`architecture.md`](architecture.md) §6–8 — trust, settlement contract, migration
- [`architecture-current.md`](architecture-current.md) §4 — live Redis / env / HTTP / receipt wiring
- [`../whitepaper/WHITEPAPER_0.3_en.md`](../whitepaper/WHITEPAPER_0.3_en.md) §4 — supply, burn narrative, vesting
