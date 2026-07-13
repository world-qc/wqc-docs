# Proof Aggregation

Multiple leaf proofs can be aggregated into a single verifiable proof tree, reducing the verification cost from O(N) to O(1).

## Tree model

```
Leaf proofs (one per slice partition)
  → compose (pairwise binary tree)
    → each node re-verifies children natively
    → optionally appends R2 aggregation STARK tail
  → root verification (fast O(1) or audit O(N))
```

Each leaf is verified individually at ingest. Compose nodes re-verify their children before constructing the parent.

## v3 compose

A v3 compose node wraps two child proofs with structural metadata:

```
<_WQC_COMPOSE_V3_>
<compose_label\0>
<manifest_root_hash\0>
<left_child_hash: 32 bytes (SHA3-256 of left child)>
<right_child_hash: 32 bytes (SHA3-256 of right child)>
<left_child_bytes>
<right_child_bytes>
[optional R2 aggregation tail]
```

The verifier:

1. Checks that `SHA3-256(left_child_bytes) == left_child_hash` (and similarly for right).
2. Routes to the appropriate child verifier based on `compose_label` or child marker.
3. If an R2 tail is present, verifies the aggregation STARK as a fast path.

## R2 aggregation STARK

The R2 tail is an `AggregationAir` STARK that cryptographically attests the digest binding of both children without re-verifying their internal proofs.

Format:

```
<_WQC_AGG_TAIL_V4_>
<agg_len: u32 LE>
<agg_transcript>:
  <_WQC_AGG_STARK_V4_>
  <compose_label\0>
  <manifest_root_hash\0>
  <left_hash: 32 bytes>
  <right_hash: 32 bytes>
  <proof_len: u32 LE>
  <proof: postcard-encoded p3_uni_stark::Proof>
```

### AggregationAir constraints

The aggregation AIR:

- Binds left and right child SHA3-256 digests directly in the trace.
- Constrains both child verification flags to 1 (children were verified natively before prove time).
- Uses the same Circle STARK configuration as unitary leaf proofs.

### Limitation

Child STARK verification is performed **outside** the circuit at compose time. The aggregation STARK attests only that:
- The child digests match the header metadata.
- The children were verified (natively) at compose time.

It does not perform in-circuit STARK verification of the children themselves. True in-circuit recursion would require embedding a STARK verifier as an AIR constraint.

## Verification paths

| Path | Cost | Condition |
|------|------|-----------|
| Fast (R2) | O(1) | Root has `_WQC_AGG_TAIL_V4_`; verify single AggregationAir STARK |
| Audit (R1) | O(N) | Recursively walk v3 tree and re-verify every leaf STARK |
