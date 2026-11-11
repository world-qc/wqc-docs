# Swarm P2P protocols

- **Status:** Working spec — wire contract
- **Tier:** B (implementation snapshot)
- **Verified:** 2026-11-12
- **Verified against:** `wqc-node@56dca9a` `wqc-core@5a2f2ce` on `feature/sv-stark-v2-prover` (node `sv_max_rows` from core `/sysinfo`, bit 5, refusing `sv_leaf_rows` over it, `sv_digest` kept; core proves v2 leaves) and `wqc-orchestrator@3eb0331` on `feature/sv-stark-v2-leaf` (bid `sv_max_rows`, bit 5, dispatch `sv_leaf_rows`, result `sv_digest`). Prior snapshot: `wqc-orchestrator@33d91be` `wqc-node@4be0d4d` on `feature/work-budget` (announcement `work`, `deadline_secs`, `signature_v2`, bit 4); `wqc-orchestrator@e7685ef` `wqc-node@881f684` on `feature/gate-split` (gate-half keys `control` and `target`, `supported_features` bit 3); `wqc-orchestrator@6662024` `wqc-node@e7bd9f6` on `feature/network-contraction` (network tree keys); `wqc-orchestrator@206493a` `wqc-node@e81930c` on `feature/contraction-tree` (`contraction_tree` suffix); `wqc-orchestrator@8cf0f2d` `wqc-node@2718da4` `wqc-p2p-proxy@7898c96`
- **Audience:** Implementers of a worker node, an orchestrator, or a libp2p proxy
- **Related:** [`spec/architecture-current.md`](architecture-current.md), [`spec/circuit-payload.md`](circuit-payload.md), [`spec/economics.md`](economics.md)

## Scope

This document is the source of truth for the **libp2p wire contract** between the
orchestrator and worker nodes: protocol IDs, framing, signature payload layouts, and
message shapes.

Three repositories implement it and must agree:

| Repository | Role |
|------------|------|
| `wqc-orchestrator` | Signs announcements and dispatch; consumes bids, results, PCS bundles |
| `wqc-node` | Verifies orchestrator signatures; signs bids and PCS bids |
| `wqc-p2p-proxy` | rust-libp2p sidecar that terminates libp2p on the orchestrator's behalf |

The orchestrator has two host backends selected at startup. Setting
`WQC_P2P_PROXY_SOCKET` routes all P2P through `wqc-p2p-proxy` over a Unix socket;
leaving it unset falls back to an in-process go-libp2p host bound to `0.0.0.0:4001`.
Both speak the same wire contract, so this document does not distinguish them.

Client-facing HTTP is out of scope — see `wqc-orchestrator/openapi/openapi.yaml`. The
only node-facing HTTP call is `GET /api/v1/p2p/bootstrap`, which pins the orchestrator
PeerID and Ed25519 public key before any P2P traffic.

## 1. Protocol inventory

Default bootstrap port is `4001`.

| Protocol ID | Direction | Ack | Purpose |
|-------------|-----------|-----|---------|
| gossipsub topic `wqc-global-announcements` | Orchestrator → mesh | — | Broadcast `TaskAnnouncement` |
| `/wqc/task-announce/1.0.0` | Orchestrator → Node | none | Announce fallback to directly connected peers when the mesh has not formed |
| `/wqc/tensor-net/1.0.0` | Node → Orchestrator | none | Signed lottery bid |
| `/wqc/tensor-dispatch/1.0.0` | Orchestrator → Node | none | Signed `SubTask` |
| `/wqc/tensor-result/1.0.0` | Node → Orchestrator | none | Slice result with leaf STARK |
| `/wqc/tensor-pcs-req/1.0.0` | Orchestrator → Node | none | Nominate a leaf PCS builder |
| `/wqc/tensor-pcs/1.0.0` | Node → Orchestrator | **yes** | Deliver leaf PCS bundle or refuse |
| `/wqc/tensor-pcs-open/1.0.0` | Orchestrator → Nodes | none | CAS-backed PCS open call |
| `/wqc/tensor-pcs-bid/1.0.0` | Node → Orchestrator | none | Spill-policy bid on an open call |

The proxy enforces direction with two whitelists. `/wqc/tensor-pcs-open/1.0.0` is
outbound-only and `/wqc/tensor-pcs-bid/1.0.0` is inbound-only; mixing them is a
configuration error, not a fallback path.

## 2. Framing

Every stream carries **exactly one JSON message**, and the message is delimited by
**end of stream**, not by a length prefix:

1. The sender opens a stream on the protocol ID.
2. The sender writes the full JSON body.
3. The sender half-closes the write side.
4. The receiver reads to EOF and parses the whole buffer as one JSON value.

Do not attempt to pipeline several messages on one stream.

### 2.1 Acknowledgement

Only `/wqc/tensor-pcs/1.0.0` produces a reply. After half-closing, the sender reads the
response to EOF and parses it as JSON:

```json
{ "ok": true }
```

```json
{ "ok": false, "error": "reason" }
```

Anything that is not `ok: true` must be treated as rejection. Every other protocol is
fire-and-forget: a successful write means delivered, not accepted.

Note that the length-prefixed JSON control frames used between the orchestrator and
`wqc-p2p-proxy` are a **different** protocol on a Unix socket. They are an internal
detail of that pair and are not part of the swarm wire contract.

## 3. Authentication

Both directions authenticate with **Ed25519 detached signatures over a deterministic
binary payload**, carried as base64 in the JSON envelope. The JSON itself is never the
signed input — do not re-serialize and sign the JSON.

| Direction | Key | Where the verifier gets it |
|-----------|-----|----------------------------|
| Orchestrator → Node | Orchestrator identity key | `public_key_b64` from `GET /api/v1/p2p/bootstrap` |
| Node → Orchestrator | Node identity key | The libp2p peer ID of the stream |
| Node → Orchestrator (economic) | Operator key | Payout registry, keyed by `operator_id` |

For every inbound stream the orchestrator additionally requires that the **stream peer
ID equals the `node_id` in the message body**. All four node-to-orchestrator protocols
enforce this, and a mismatch is rejected before any economic check. A node therefore
cannot bid, deliver, or claim payment as another node even with a valid signature.

### 3.1 Serialization rules for signed payloads

These rules are shared by all payload layouts in §3.2:

- Every fixed-width numeric field is **big-endian** (network order). Rust implementations
  must use `to_be_bytes()`; Go uses `binary.BigEndian`.
- Strings are raw UTF-8 concatenated **without length prefixes**, except where a layout
  explicitly specifies a length prefix.
- `int64` fields are two's complement.
- Field order is exactly as listed. There is no separator between fields, so the layouts
  are only unambiguous because the field set is fixed.

### 3.2 Signed payload layouts

**`TaskAnnouncement`** — signed by the orchestrator, verified before bidding:

```
task_id            []byte
global_qubit_count uint32 BE
required_features  uint32 BE
bid_difficulty     uint32 BE
required_votes     uint32 BE
nonce              uint64 BE
```

**`TaskAnnouncement` v2** — an announcement with `work` is also signed over the
v1 layout followed by its budget, in `signature_v2`
([`work-budget.md`](work-budget.md) §3):

```
(v1 layout)
deadline_secs      uint32 BE
traffic_bytes      uint64 BE
flops              uint64 BE
```

A node that reads `work` verifies `signature_v2` and drops the announcement
when it is missing or wrong, or when `required_features` has bit 4 but `work`
or `deadline_secs` is missing (stripping them leaves `signature` valid). An
older node ignores the new keys and verifies `signature`.

**`Bid`** — signed by the node identity key:

```
task_id              []byte
node_id              []byte
max_qubit_capability uint32 BE
current_load_factors uint32 BE
timestamp            int64 BE
lottery_attempt      uint64 BE
lottery_proof        []byte (opaque)
supported_features   uint32 BE
```

`max_mps_qubits` is **not** in this layout. The concatenation has no length prefix, so
appending a field would make older bids fail verification. It travels as an unsigned
JSON field (omitted when 0), the same way `metrics_summary` does. The orchestrator
uses it only to decide whether a scalar slice fits the node's χ=128 MPS workspace.
A missing field falls back to `max_qubit_capability`. `sv_max_rows` is not in this
layout either: like `max_mps_qubits`, it is an unsigned JSON field omitted when 0,
and a missing field means the node proves no v2 leaf (§5).

**Operator signature on a bid** — a second, independent signature by the operator key,
binding the economic identity that will be paid:

```
operator_id
node_id
task_id
stake_amount  (decimal string, Planck integer)
```

**`SubTask` dispatch** — signed by the orchestrator. This is the only layout that uses
length prefixes, because it embeds variable-length JSON:

```
parent_task_id       []byte
circuit_id           []byte
slice_id             []byte
qubit_count          uint32 BE
original_qubit_count uint32 BE
required_votes       uint32 BE
assignments_count    uint32 BE
  for each assignment:
    edge_id          []byte
    value            uint8
circuit_json_len     uint32 BE
circuit_json         []byte   (json.Marshal of the circuit array)
mps_max_bond_dim     uint32 BE
output_mode_len      uint32 BE
output_mode          []byte
shots                uint64 BE
classical_bit_count  uint32 BE
sample_seed          uint64 BE
observables_json_len uint32 BE
observables_json     []byte
mps_site_order_len   uint32 BE
mps_site_order       count x uint32 BE
security_level_len   uint32 BE
security_level       []byte
mps_time_split       uint32 BE   (omitted when 0)
contraction_tree_len uint32 BE   (omitted when the task has no tree)
contraction_tree     []byte      (JSON; omitted together with the length)
sv_leaf_rows         uint64 BE   (omitted when 0)
```

Scalar tasks carry `statevector_scalar` for `output_mode`; `shots`,
`classical_bit_count`, and `sample_seed` are unused and normally zero. The
orchestrator stores an empty client mode as `statevector_scalar` before
dispatch. An empty `mps_site_order` means identity. An empty `security_level`
means the FRI default. `mps_time_split` is the gate index that splits a scalar
into two MPS sweeps. It is omitted when zero so an older node still verifies
ordinary dispatches; a node that does not know the field rejects only
time-split tasks. `contraction_tree` is the exact-tree JSON from
[`contraction-tree.md`](contraction-tree.md). Both the length and the JSON are
omitted when the task has no tree, so those dispatches stay byte-identical. A
tree task has `mps_time_split` zero, so the suffix starts at
`contraction_tree_len`. An older node rejects only that signature. The JSON
keys are in struct order (`kind` when set, `nodes`, `peak_bytes`, then each
node's `op`, `left`, `right`, and each operand's one key out of `ket0`, `gate`,
`node`, `bra0`, `control`, `target`). One qubit of `H` as a state tree is
`{"nodes":[{"op":"contract","left":{"ket0":0},"right":{"gate":0}}],"peak_bytes":32}`,
and as a network tree is
`{"kind":"network","nodes":[{"op":"contract","left":{"ket0":0},"right":{"gate":0}},{"op":"contract","left":{"bra0":0},"right":{"node":0}}],"peak_bytes":128}`.
The node re-encodes the tree it decoded before it checks the signature, so it
must know every key: a node without `kind` and `bra0` rejects every network
tree task. A tree that takes a gate as `control` and `target` halves is sent
only to nodes whose bid carries `supported_features` bit 3 (below).

**`PcsRequest`** — signed by the orchestrator:

```
sub_task_id      []byte
parent_task_id   []byte
slice_id         []byte
node_id          []byte
issued_at_unix   int64 BE
request_kind     []byte   (empty for majority nomination)
leaf_proof_hash  []byte   (empty for majority nomination)
```

Leaving the last two empty keeps the payload byte-identical to the pre-open-call
version, so older nodes verify open-call-era majority nominations unchanged.

**`PcsOpenCall`** — signed by the orchestrator:

```
parent_task_id      []byte
sub_task_id         []byte
slice_id            []byte
leaf_proof_hash     []byte
leaf_proof_bytes    uint64 BE
cas_presigned_url   []byte
r_pcs_planck        []byte
deadline_unix       int64 BE
issued_at_unix      int64 BE
refused_count       uint32 BE
  for each refused builder, lexicographically sorted:
    id_len          uint32 BE
    id              []byte
```

Sorting the refused builders is required — the set is unordered in memory, and an
unsorted encoding would produce a signature the receiver cannot reproduce.

**`PcsBid`** — signed by the node:

```
sub_task_id         []byte
node_id             []byte
leaf_proof_hash     []byte
pcs_memory_policy   []byte
issued_at_unix      int64 BE
```

## 4. Task announcement

The orchestrator gossips a signed announcement so nodes can enter the permissionless
bidding lottery. When the mesh has not formed — a small swarm with a single bootstrap
peer is the common case — it also streams the same envelope to directly connected peers
over `/wqc/task-announce/1.0.0`.

```json
{
  "announcement": {
    "task_id": "uuid-v7-task-identifier",
    "global_qubit_count": 3,
    "required_features": 3,
    "bid_difficulty": 2,
    "required_votes": 2,
    "nonce": 18446744073709551615
  },
  "signature": "<base64 ed25519>"
}
```

`sv_leaf_rows` asks the node to prove the sub-task as a v2 (sv-stark) leaf and
gives the leaf's gate rows `W` (§6.1). It is omitted when zero, so a v1
dispatch stays byte-identical and a node that does not know the field rejects
only v2 dispatches. A v2 sub-task has no tree and `mps_time_split` zero, so the
suffix is these 8 bytes alone.

A task with a network tree also carries `deadline_secs`, `work`
(`traffic_bytes`, `flops`), and `signature_v2` (§3.2), and sets bit 4. A node
bids only if it expects to finish in time ([`work-budget.md`](work-budget.md)).


`required_features` is a gate-capability bitmask. A node derives its own mask from
`wqc-core` `GET /gates` at startup and skips announcements it cannot execute.

| Bit | Name | Set by the node when `/gates` lists | Required by the orchestrator when |
|-----|------|-------------------------------------|-----------------------------------|
| `1 << 0` | standard gates | `H`, `X`, `Y`, `Z`, `S`, `T`, `CNOT`, `CZ`, `CCNOT` | the circuit has one of those, `MEASURE`, `RESET`, or `IF`, or nothing else applies |
| `1 << 1` | rotations | `RX`, `RY`, `RZ` | the circuit has a rotation |
| `1 << 3` | network gate split | `NETWORK_GATE_SPLIT` | the attached network tree takes a gate as halves ([`contraction-tree.md`](contraction-tree.md) §5) |
| `1 << 4` | work budget | — (set when core `GET /sysinfo` reports `tn_seconds_per_byte` and `tn_seconds_per_flop` within bounds) | the announcement carries `work` ([`work-budget.md`](work-budget.md)) |
| `1 << 5` | sv-stark v2 leaf | — (set when core `GET /sysinfo` reports `sv_seconds_per_row` and the node's `sv_max_rows` from it is nonzero; the bid then carries `sv_max_rows`) | never in `required_features`; the orchestrator sends a sub-task as a v2 leaf only to nodes with this bit (§6.1) |

Bit 2 is reserved by the orchestrator for noise channels; no node sets it yet.

## 5. Bid

```json
{
  "task_id": "uuid-v7-task-identifier",
  "node_id": "12D3KooW...",
  "max_qubit_capability": 34,
  "max_mps_qubits": 2048,
  "sv_max_rows": 262144,
  "current_load_factors": 0,
  "timestamp": 1717776000,
  "lottery_attempt": 0,
  "signature": "<base64>",
  "lottery_proof": "<base64>",
  "stake_amount": "50000",
  "supported_features": 3,
  "location": { "latitude": 35.6, "longitude": 139.7, "country": "JP", "city": "Tokyo" },
  "operator_id": "<sha256 hex of operator pubkey>",
  "operator_sig": "<base64>",
  "metrics_summary": {
    "pending_tasks": 0,
    "outbox_pending": 0,
    "p2p_connected_peers": 3,
    "p2p_orchestrator_connected": 1,
    "core_timeouts_total": 0,
    "uptime_seconds": 3600
  }
}
```

`stake_amount` is a **decimal string**, not a number, because it is a Planck-denominated
big integer.

`location` is egress GeoIP telemetry, not device GPS. `metrics_summary` is an unsigned
health snapshot that the orchestrator re-exports as Prometheus gauges labeled by
`node_id`. `max_mps_qubits` is the χ=128 MPS compact width for scalar slices (1 GiB
holds 2048 sites). None of the three is covered by the bid signature.
`metrics_summary` must not be trusted for consensus or payment. `max_mps_qubits`
only chooses the scalar slice width; a node that overstates it is still bounded by
the core memory check on `N · χ² · 32` bytes.

`sv_max_rows` is the largest v2 leaf, in gate rows `W`, the node proves. The node
sets it from its own memory and speed, so that the leaf fits and finishes within
the v2 timeout (§6.1). It is at most 2^22 (`wqc_sv_max_rows`, the protocol limit
on `W`); a larger value selects nothing more. It is unsigned and omitted when 0.
The reference node takes the smaller of two bounds, both from core
`GET /sysinfo`. Core measures `sv_seconds_per_row` at startup by proving a
small leaf (n = 12, 8 rounding steps, 1024 shots), and reports
`sv_bytes_per_row` and `sv_base_bytes`:

- Memory: `sv_base_bytes + sv_bytes_per_row · W` fits 80% of the node's RAM
  budget.
- Time: `1.5 · sv_seconds_per_row · W` fits both the v2 timeout
  (`90 s + 50 µs · W`, at most 330 s) and the node's own compute timeout.

A node that overstates it runs out of memory or time and is slashed like any
other failure. Because the field is unsigned, a node also refuses a dispatch
whose `sv_leaf_rows` is over its own limit rather than trust the advertised
value.

`operator_id` and `operator_sig` carry the economic identity separately from the node
identity, so one operator can run many nodes. Without them a bid is still valid for
compute but has no payout binding.

## 6. SubTask dispatch

```json
{
  "sub_task": {
    "task_id": "encoded-sub-task-id",
    "parent_task_id": "uuid-v7-task-identifier",
    "circuit_id": "sha3-256-of-pruned-circuit",
    "qubit_count": 2,
    "original_qubit_count": 3,
    "slice_id": "01",
    "slice_assignments": [{ "edge_id": "e_0", "value": 1 }],
    "circuit": [{ "type": "H", "params": 0 }],
    "required_votes": 2,
    "mps_max_bond_dim": 128,
    "mps_site_order": [],
    "mps_time_split": 0,
    "output_mode": "sample_counts",
    "classical_bit_count": 2,
    "shots": 1024,
    "sample_seed": 123456789,
    "measurement_spec_hash": "<sha3-256 hex>",
    "observables": [],
    "noise_model": null,
    "security_level": "low"
  },
  "signature": "<base64 ed25519>"
}
```

Circuit indices on a branched slice are **local to the compact register**, already pruned and remapped
from the client's global indices. An exact-tree dispatch keeps parent wire numbers and
carries `contraction_tree` ([`contraction-tree.md`](contraction-tree.md)). Gate grammar is in
[`circuit-payload.md`](circuit-payload.md). Single-operand gates are always the bare form
on the dispatch wire (§1.1 there), the form `wqc-core` reads, so a node passes the circuit
through unchanged.

### 6.1 v2 leaves

A v2 (sv-stark) leaf proves that the dispatched circuit, applied to `|0…0⟩`, ends
in a state with the reported digest, and that the reported counts are the leaf's
sampling of that state with `sample_seed`. The proof binds `circuit_id`,
`sub_task_id`, `node_id`, and `slice_id` too.

The orchestrator sends a sub-task as a v2 leaf when all of these hold:

- The task is `sample_counts`, unsliced (no assignments), without noise, with 1
  to 2^16 shots and 1 to 16 classical bits.
- The circuit has a v2 leaf: only unitary gates followed by terminal `MEASURE`s,
  with `W` (gate rows: rounding steps × 2^(n−1), from `libwqc_stark_verifier`'s
  `wqc_sv_leaf_rows`) at most 2^22.
- Every node of the quorum group has bit 5 and `sv_max_rows ≥ W`. The
  orchestrator first looks for such a group, then takes any group and sends v1.
- The orchestrator can build the leaf's verifier now: its estimated peak
  (`wqc_sv_verifier_peak_bytes`) fits the memory it can spare.

The orchestrator builds the verifier before it dispatches, one build at a time,
and caches it per circuit, shots, classical bits, and tier. A build blocks that
dispatch (up to about 16 s at `W` = 2^22). If the verifier is gone when a result
arrives (evicted, or the orchestrator restarted), it is built again; if that
build fails for lack of memory, the result is rejected and the sub-task is
redispatched without a slash.

Otherwise the sub-task goes out as a v1 leaf. Traps stay v1. A recovery dispatch
of a v2 sub-task goes only to a node with bit 5 and `sv_max_rows ≥ W`.

The timeout of a v2 leaf is `90 s + 50 µs × W`, with no tier multiplier, capped
like every sub-task (330 s by default).

v2 dispatch is behind the orchestrator's `WQC_SV_STARK_V2_DISPATCH` (off by
default) until the composer aggregates v2 leaves. The orchestrator verifies v2
results whenever they arrive.

## 7. Result

```json
{
  "sub_task_id": "encoded-sub-task-id",
  "node_id": "12D3KooW...",
  "result_type": "sample_counts",
  "complex_result": { "real": 0.7071, "imag": 0.0 },
  "sample_result": { "counts": { "00": 512, "11": 512 }, "shots": 1024 },
  "proof": {
    "public_inputs": {
      "circuit_id": "sha3-256-of-pruned-circuit",
      "sub_task_id": "encoded-sub-task-id",
      "node_id": "12D3KooW...",
      "slice_id": "01",
      "output_result_hash": "sha3-256-of-canonical-result-json",
      "measurement_spec_hash": "<sha3-256 hex>",
      "security_level": "low"
    },
    "stark_proof_b64": "<base64>"
  },
  "work_report": {
    "trace_rows": 42,
    "gate_count": 2,
    "compute_wall_ms": 12,
    "prove_wall_ms": 340,
    "proof_bytes": 65536,
    "tn_backend": "cpu",
    "vram_peak_bytes": 0
  }
}
```

`complex_result` is present in every mode. `sample_result` and `expectation_result`
appear only in their own mode.

A v2 leaf result (§6.1) is `sample_counts`. Its `public_inputs` add `sv_digest`, the
terminal-state digest as four Goldilocks words (`[u64; 4]`, JSON numbers), and
`stark_proof_b64` holds the v2 proof (postcard bytes). The orchestrator checks the
proof against the dispatch, `sv_digest`, `sample_seed`, and the canonical counts
JSON, `{"counts":{…},"shots":N}` with keys of exactly `classical_bit_count` bits in
order and no zero counts. It does not run the v1 unitary verifier or the
distribution binding for it. The quorum compares the counts as for v1.

`work_report` feeds gas settlement. Only `trace_rows` and `gate_count` are deterministic
and therefore settlement-relevant; the wall-clock fields are audit-only. Nodes also send
`tn_backend` and `vram_peak_bytes`, which the orchestrator currently ignores.

On compute failure the node sends **only** `sub_task_id`, `node_id`, and `error`:

```json
{ "sub_task_id": "…", "node_id": "…", "error": "reason" }
```

### 7.1 Quorum

| Mode | Comparison |
|------|------------|
| `statevector_scalar` | Epsilon match on `complex_result` |
| `expectation` | Epsilon match on each value |
| `sample_counts` | **Exact** counts match under the shared `sample_seed` |

Exact matching works because the orchestrator issues one seed per task and copies it to
every sub-task. See [`circuit-payload.md` §4](circuit-payload.md#4-determinism-and-quorum).

## 8. Leaf PCS

After quorum the orchestrator nominates one builder at a time. Two modes share
`/wqc/tensor-pcs-req/1.0.0`:

| Mode | When | Nominee |
|------|------|---------|
| Majority (default) | Proof winner first, then failover within the quorum majority | Winner or next majority candidate |
| Open call | All majority candidates exhausted | First spill-policy bidder, first-wins |

Request:

```json
{
  "request": {
    "sub_task_id": "parent_01-sub",
    "parent_task_id": "parent",
    "slice_id": "01",
    "node_id": "12D3KooW...",
    "issued_at_unix": 1717776000,
    "request_kind": "",
    "leaf_proof_hash": ""
  },
  "signature": "<base64 ed25519>"
}
```

An empty `request_kind` means majority nomination. `request_kind: "open_call"` means the
builder must fetch the leaf proof from CAS, and `leaf_proof_hash` must match that object
(SHA-256 hex).

Response on `/wqc/tensor-pcs/1.0.0` — the only acked protocol, and only the currently
nominated node may submit for a slice:

```json
{
  "sub_task_id": "parent_01-sub",
  "node_id": "12D3KooW...",
  "leaf_pcs_b64": "<base64 LeafPcsBundle>",
  "refused": false
}
```

```json
{
  "sub_task_id": "parent_01-sub",
  "node_id": "12D3KooW...",
  "refused": true,
  "refuse_reason": "PCS memory: … (policy=refuse)"
}
```

Refusal is permanent for that node and is the expected outcome when the builder's
`wqc-core` runs `WQC_PCS_MEMORY_POLICY=refuse` and the bundle exceeds the budget.

The orchestrator verifies the bundle against the stored leaf STARK before storing it or
paying. A verification failure is treated exactly like a refusal, so an invalid bundle
earns nothing and triggers failover.

## 9. PCS open call

When every majority candidate has refused or been exhausted, and open call is enabled,
the orchestrator uploads the winner's leaf STARK to CAS (key = SHA-256 hex), records the
open-call phase, and fans out:

```json
{
  "open_call": {
    "parent_task_id": "parent",
    "sub_task_id": "parent_01-sub",
    "slice_id": "01",
    "leaf_proof_hash": "<sha256 hex>",
    "leaf_proof_bytes": 5242880,
    "cas_presigned_url": "https://…/presigned-get",
    "r_pcs_planck": "2400000000000000",
    "deadline_unix": 1717777800,
    "issued_at_unix": 1717776000,
    "refused_builders": []
  },
  "signature": "<base64 ed25519>"
}
```

Only nodes whose core reports `pcs_memory_policy: "spill"` should bid; refuse-policy
nodes stay silent. A node learns this from `wqc-core` `GET /sysinfo`.

```json
{
  "bid": {
    "sub_task_id": "parent_01-sub",
    "node_id": "12D3KooW...",
    "leaf_proof_hash": "<sha256 hex>",
    "pcs_memory_policy": "spill",
    "issued_at_unix": 1717776100
  },
  "signature": "<base64 ed25519>"
}
```

The orchestrator rejects any bid that does not declare `spill`, nominates first-wins,
and re-publishes the open call with an updated `refused_builders` list on refusal or
timeout. When the open-call window expires the slice falls back to `wqc-composer`
building the missing leaf PCS during compose.

While the open-call phase is active and no bundle is stored, compose is **not**
satisfied, even when majority builders are marked exhausted.
