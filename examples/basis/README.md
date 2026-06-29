# Phase B B2 — X/Y basis examples

WQC `MEASURE` is always Z-basis. Use these patterns for X/Y readouts.

| File | Mode | Expected result |
| --- | --- | --- |
| `x_sample_counts.json` | `sample_counts` | `counts: {"0": 1024}` on `\|+⟩` with X-basis pre-`H` |
| `y_sample_counts.json` | `sample_counts` | `counts: {"0": 1024}` on `\|+i⟩` (`RX(π/2)` prep + `RX(-π/2)` pre-`MEASURE`) |
| `xy_expectation.json` | `expectation` | `X → 1.0`, `Z → 0.0` on `\|+⟩` |

Submit:

```bash
curl -s -X POST http://localhost:9001/api/v1/submit \
  -H "Content-Type: application/json" \
  -d @x_sample_counts.json
```

See WHITEPAPER §3.4.2b and `wqc-core/src/basis.rs`.
