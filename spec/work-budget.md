# Work budget

- **Status:** Working spec — work budget (first version)
- **Tier:** B (implementation snapshot)
- **Verified:** 2026-11-07
- **Verified against:** `wqc-core@41dbd9d` on `feature/compute-cancel`; `wqc-node@fc38705` `wqc-orchestrator@84f320c` on main
- **Audience:** Implementers of the orchestrator, node, and core
- **Related:** [`p2p-protocols.md`](p2p-protocols.md) (announcement and bid), [`contraction-tree.md`](contraction-tree.md) (trees and their cost), [`mps-scalar.md`](mps-scalar.md) (the path with no tree)

## Problem

A node gives up on `/compute` after its own timeout (`WQC_COMPUTE_TIMEOUT_SECS`,
300 s by default). The orchestrator does not know that value or how fast a node
is, yet it decides which tree to dispatch. Today it caps its sub-task deadline at
a copy of the node default (`NodeComputeTimeout`), and nothing stops it from
dispatching a tree no bidder can finish.

On testnet (2026-11-06) a 10×10 depth-8 network tree took about 60 s on a laptop
and 636–1159 s on a miner Pod (about one e2-medium core). All three nodes timed
out, the task failed, and the nodes kept computing after giving up, so a keepalive
queued behind them timed out too and two nodes were penalized.

A fixed time limit in the orchestrator would fix that one swarm, but it would
encode one node's speed and timeout in the orchestrator. Nodes differ, and only
a node knows its own speed, its timeout, and what it is already running.

## Principle

The orchestrator states how much work a task is and when it must finish. Each
node decides for itself whether it can, and bids only if so. The orchestrator
keeps no node-side timeout or speed.

## 1. Work

`work` describes one sub-task of the task in units that do not depend on the
node:

| Field | Meaning |
|-------|---------|
| `traffic_bytes` | Bytes core reads and writes over the tree: per join, both operands and the result, plus twice an operand that must be reordered first ([`contraction-tree.md`](contraction-tree.md) §3.2) |
| `flops` | `Σ 2^|legs of the union of both operands|` over the joins ([`contraction-tree.md`](contraction-tree.md) §3.2) |

Both are counts from the planner, not times. A core that moves less than the
count (for example, one that absorbs a gate half in place) only finishes early.

In the first version, `work` is present only when the orchestrator attaches a
network tree. Tasks with a state tree, on the MPS path, in `expectation`, or
in `sample_counts` omit it, and nodes bid on them as today. A network tree is
attached where its peak is below the state tree's: on an RY+CNOT brickwork,

| Qubits | Depth 2 | Depth 4 | Depth 8 | Depth 16 |
|-------:|---------|---------|---------|----------|
| 1–4 | state | state | state | state |
| 5–6 | network | state | state | state |
| 7–8 | network | network | state | state |
| 12 | network | network | network | state |
| 16, 20 | network | network | network | network |

So most 1–8-qubit keepalives carry no `work`, and wider scalar tasks usually
do.

## 2. Deadline

The orchestrator times a sub-task out after its TTL: a table by qubits and
gates, scaled by security level, capped at `WQC_SUBTASK_MAX_TTL_SECS` (330 s
by default). That cap is the orchestrator's own policy. It no longer copies a
node's timeout.

`deadline_secs` is that TTL minus `WQC_ORCHESTRATOR_SLACK_SECS` (30 s), at
least 1 s. A node that gives up at `deadline_secs` reports the failure before
the watcher times it out. A tree sub-task keeps the parent's qubits and
circuit, so the TTL at dispatch is the one announced. A trap sub-task (about
one in ten scalar dispatches) has its own small circuit and a TTL of its own;
the node still applies the parent's `deadline_secs`, which only matters if the
trap's TTL is shorter, and a trap finishes in well under a second.

## 3. Announcement

`work` and `deadline_secs` join the announcement:

```json
{
  "announcement": {
    "task_id": "…",
    "global_qubit_count": 100,
    "required_features": 27,
    "bid_difficulty": 1,
    "required_votes": 2,
    "nonce": 18446744073709551615,
    "deadline_secs": 300,
    "work": { "traffic_bytes": 1100000000000, "flops": 38000000000 }
  },
  "signature": "<base64 ed25519, v1 layout>",
  "signature_v2": "<base64 ed25519, v2 layout>"
}
```

The v1 layout ([`p2p-protocols.md`](p2p-protocols.md) §3.2) has no length
prefixes, so fields cannot be appended to it without breaking older nodes. The
orchestrator therefore signs twice. `signature` stays the v1 layout. `signature_v2`
covers the v1 layout followed by:

```
deadline_secs  uint32 BE
traffic_bytes  uint64 BE
flops          uint64 BE   (rounded down to an integer)
```

An announcement without `work` carries neither `deadline_secs` nor
`signature_v2`. A node that understands `work` verifies `signature_v2` when
`work` is present and drops the announcement when that fails. An older node
ignores the new keys and verifies `signature` as today.

A new capability bit, `1 << 4` (`WORK_BUDGET`), means "this node judges
`work`". The orchestrator sets it in `required_features` whenever it sends
`work`, so a node that would ignore the budget does not bid.

Bit 4 also says `work` is there. The v1 signature does not cover `work`, so a
relay could strip `work`, `deadline_secs`, and `signature_v2` and leave a
valid v1 signature. A node drops an announcement that asks for bit 4 without
`work` and `deadline_secs`.

## 4. Node: whether to bid

The node estimates its own time:

```
expected = queued + traffic_bytes · s_byte + flops · s_flop + overhead
```

- `s_byte`, `s_flop`: seconds per byte and per flop for this node's core (§5)
- `queued`: the expected time of everything ahead of it (below)
- `overhead`: proving and transfer, `WQC_WORK_OVERHEAD_SECS` (default 5)

It bids only when `expected ≤ margin · min(deadline_secs, WQC_COMPUTE_TIMEOUT_SECS)`,
with `margin` from `WQC_WORK_BUDGET_MARGIN` (default 0.5). When it skips, it
logs the task id and `expected`, so an operator can see why it did not bid.

`queued` adds up:

- every sub-task the node holds, including those restored from its database
  after a restart: one with a budget counts its estimate until it starts, then
  what is left of it, and its whole estimate again once it runs past it; one
  without `work` counts `WQC_WORK_UNKNOWN_SECS` (default 30);
- every bid it made in the last 15 s whose dispatch has not arrived. The
  orchestrator collects bids for at most 5 s, so a node that bids on several
  tasks at once counts each.

A dispatch carries the budget of the announcement with the same parent task
id, and ends that bid's reservation.

The deadline counts from when the node accepts the dispatch. When the worker
takes the sub-task, the node waits for core for `WQC_COMPUTE_TIMEOUT_SECS` or
what is left of `deadline_secs`, whichever is shorter; if nothing is left, it
reports the failure without calling core. Transfer before acceptance is not
counted; it is far below the 30 s slack.

When the node stops waiting, it closes its connection to core, and core
cancels the computation at its next contraction step
([`openapi/core.yaml`](../openapi/core.yaml) `/compute`). The next sub-task
does not queue behind one the node has given up on.

A node that bids on work it cannot finish times out and is penalized as today.
A node that understates its speed only loses work. Neither gains from a false
estimate, so the orchestrator does not check it.

## 5. Core: speed

Core measures its own rates at startup and reports them in `GET /sysinfo`:

| Field | Measured by |
|-------|-------------|
| `tn_seconds_per_byte` | Joining a 2-leg tensor into a 2^23-element tensor whose shared leg is mid-way, divided by that join's `traffic_bytes` |
| `tn_seconds_per_flop` | Joining two 2^20-element tensors over 10 shared legs, already in order (2^30 flops), divided by its `flops`. Its 48 MiB of traffic stay in the time, which errs slow |

Each join runs three times and the fastest counts. The benchmark runs before
core serves, takes about a second on a laptop, and uses about 512 MiB. It runs
with the same thread settings core computes with. When a join fails, core
reports neither rate. The node reads the rates once, after `GET /gates`, and
sets bit 4 only when both are present and within 10^-13–10^-6 s per byte and
10^-14–10^-6 s per flop.

The byte join is the shape a sweep tree is made of: a gate half absorbed into
a state. `traffic_bytes` counts the state reordered, but core absorbs a tensor
of at most 6 legs into a larger one in place when the larger one's free bits
below its lowest shared leg form a run of at least 64 elements, so it never
moves those bytes. `tn_seconds_per_byte` is therefore seconds per *counted*
byte of such a join, about 2.4 times lower than for a join that is reordered.
A join of two large tensors that must be reordered is underestimated by that
factor. Bisection trees spend almost all their time in flops, so this changes
their estimate by well under a second; a tree whose time is mostly reordered
large joins would be underestimated (§8).

On an Apple M-series laptop (release build, `wqc-core` with the in-place
absorb, GEMM on one thread) core measures 48.9 GB/s and 2.97 Gflop/s.
Without `overhead`, the estimate against the measured time:

| Tree | `traffic_bytes` | `flops` | Estimate | Measured |
|------|----------------:|--------:|---------:|---------:|
| 8×8 depth 11, bisection | 1.66·10^9 | 2.76·10^9 | 0.96 s | 1.35 s |
| 6×6 depth 14, bisection | 3.28·10^9 | 8.55·10^9 | 2.95 s | 3.23 s |
| 7×7 depth 12, bisection | 5.63·10^9 | 3.59·10^10 | 12.2 s | 12.6 s |
| 6×6 depth 16, bisection | 7.34·10^9 | 1.74·10^11 | 58.6 s | 59.2 s |
| 10×10 depth 8, sweep | 1.10·10^12 | 3.77·10^10 | 35.2 s | 30.0 s |

Trees of a second or two come out at about a quarter to three quarters of their
time (a 7×7 depth-10 bisection at 0.07 s against 0.25 s); `overhead` covers
that.

## 6. Orchestrator

- Plan the tree as today (fewest flops among the trees that fit). Record
  `traffic_bytes` and `flops` with a network tree.
- Announce `work`, `deadline_secs`, `signature_v2`, and bit 4 when the task
  gets a network tree.
- Cap the TTL at `WQC_SUBTASK_MAX_TTL_SECS`, which replaces the orchestrator's
  copy of the node's `WQC_COMPUTE_TIMEOUT_SECS`.
- When too few nodes bid, the task fails as it does today when bidders are
  short (§8).

## 7. Rollout

The wire grows, so receivers ship first: core (§5) → node (§3, §4) → docs →
orchestrator → a miner release. An orchestrator that sends bit 4 before the
nodes have it gets no bids on network tree tasks (§1): the wider scalar tasks
and the shallow 5–8-qubit keepalives.

## 8. Not in the first version

1. **Fallback.** When too few nodes bid on a tree, the task fails as it does
   today when bidders are short. Re-announcing with the fallback plan (state
   tree or MPS) would change the slice count the quote and escrow assume (1).
2. **MPS work.** MPS slices carry no `work`. They are bounded by
   `max_mps_qubits`, not by time.
3. **Quote.** The quote does not warn about work no node may take; it cannot
   see bidders.
4. **Learning rates.** The node does not refine its rates from its own
   `work_report.compute_wall_ms`; it uses the startup measurement.
5. **Counting the absorb.** The planner counts a reorder that core skips when
   it absorbs a small tensor (§5). Counting those joins as core runs them would
   take one byte rate for every join, but changes `traffic_bytes` in the
   orchestrator and in core's benchmark together.

## Appendix: testnet measurements (2026-11-06)

Miner Pod, about one e2-medium core, `wqc-core` with `RAYON_NUM_THREADS=1`.
The 8×8 row ran on a core with GEMM on one thread; the other two on a core
with multithreaded GEMM, as does the laptop column (8 cores).

| Tree | `traffic_bytes` | `flops` | Pod | Laptop |
|------|----------------:|--------:|----:|-------:|
| 8×8 depth 11, bisection | 1.66·10^9 | 2.8·10^9 | 3.5 s | 0.74 s |
| 7×7 depth 12, bisection | 5.63·10^9 | 3.6·10^10 | 19–24 s | 3.9 s |
| 10×10 depth 8, sweep | 1.1·10^12 | 3.8·10^10 | 636 s, 1159 s | 58 s |

From these, the Pod runs at about 1.7·10^9 bytes/s and 2·10^9 flops/s. A
sweep's time is mostly traffic, which flops barely count.
