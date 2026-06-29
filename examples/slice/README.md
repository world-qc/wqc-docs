# Multi-slice `sample_counts` examples (Phase B B3)

## `multislice_sample_counts.json`

4-qubit register with idle q0–q1 and a Bell pair on q2–q3. The orchestrator **does not fix** measured qubits (`e_2`, `e_3`) during slicing; idle qubits are fixed to branch `0` only.

Expected dispatch: compact 2-qubit circuit (`H`, `CNOT`, two `MEASURE`) with deterministic `counts` dominated by `"00"` and `"11"`.

## `multislice_expectation.json`

28-qubit register, Bell on q26–q27, `ZZ` observable on the same pair. OP1 fixes idle qubits; labels remap to `"ZZ"` on compact 2 qubit dispatch. Expected `⟨ZZ⟩ ≈ 1.0`.

See WHITEPAPER §3.4.2d and `observable_policy.go`.
