#!/usr/bin/env bash
# Manifest golden checks — invoked by run_e2e.sh after each completed task.
# Do not enable `set -e` here; this file is sourced by run_e2e.sh.

need() { command -v "$1" >/dev/null 2>&1 || { echo "assert_manifest: missing $1" >&2; exit 1; }; }
need jq

# jq: true if |$a - $b| <= $eps
jq_abs_le() {
  local a="$1" b="$2" eps="$3"
  python3 - "$a" "$b" "$eps" <<'PY'
import sys
a, b, eps = (float(x) for x in sys.argv[1:4])
sys.exit(0 if abs(a - b) <= eps else 1)
PY
}

jq_sample_merged() {
  local manifest="$1"
  jq -c '[.slices[] | select(.sample_result != null) | .sample_result] | last' "$manifest"
}

jq_sample_slice() {
  local manifest="$1"
  jq -c '[.slices[] | select(.sample_result != null)] | last' "$manifest"
}

assert_distribution_bound() {
  local name="$1" manifest="$2" want_bound="$3" scheme="${4:-born_air_zk_composed_v1}"
  local bound
  bound="$(jq_sample_slice "$manifest" | jq -r '.distribution_bound // false')"
  if [[ "$want_bound" == "true" && "$bound" != "true" ]]; then
    echo "ASSERT [$name] distribution_bound=$bound want true" >&2
    return 1
  fi
  if [[ "$want_bound" == "false" && "$bound" == "true" ]]; then
    echo "ASSERT [$name] distribution_bound=true want false/absent" >&2
    return 1
  fi
  if [[ "$want_bound" == "true" ]]; then
    # A v2 leaf (WQC_SV_STARK_V2_DISPATCH, on by default) proves the counts as sv_stark_v2.
    jq_sample_slice "$manifest" | jq -e ".distribution_scheme == \"$scheme\" or .distribution_scheme == \"sv_stark_v2\"" >/dev/null || {
      echo "ASSERT [$name] distribution_scheme=$(jq_sample_slice "$manifest" | jq -r '.distribution_scheme') want $scheme or sv_stark_v2" >&2
      return 1
    }
    jq_sample_slice "$manifest" | jq -e '(.measurement_spec_hash | length) > 0' >/dev/null || { echo "ASSERT [$name] want (.measurement_spec_hash | length) > 0" >&2; return 1; }
  fi
}

jq_expectation_merged() {
  local manifest="$1"
  jq -c '[.slices[] | select(.expectation_result != null) | .expectation_result] | last' "$manifest"
}

jq_scalar_merged() {
  local manifest="$1"
  jq -c '[.slices[] | select(.complex_result != null) | .complex_result] | last' "$manifest"
}

assert_manifest() {
  local name="$1" manifest="$2"
  [[ -f "$manifest" ]] || { echo "ASSERT [$name] missing manifest: $manifest" >&2; return 1; }

  case "$name" in
    scalar_h2_amplitude)
      jq -e '.result_type == "statevector_scalar"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == statevector_scalar" >&2; return 1; }
      jq -e '.total_partitions == 1' "$manifest" >/dev/null || { echo "ASSERT [$name] want .total_partitions == 1" >&2; return 1; }
      local real
      real="$(jq_scalar_merged "$manifest" | jq -r '.real')"
      jq_abs_le "$real" "0.7071067811865476" "1e-5" || {
        echo "ASSERT [$name] expected complex_result.real ≈ 1/sqrt(2), got $real" >&2
        return 1
      }
      ;;

    sample_bell_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == sample_counts" >&2; return 1; }
      local sample shots keys
      sample="$(jq_sample_merged "$manifest")"
      shots="$(echo "$sample" | jq -r '.shots')"
      [[ "$shots" == "512" ]] || { echo "ASSERT [$name] shots=$shots want 512" >&2; return 1; }
      keys="$(echo "$sample" | jq -r '.counts | keys | sort | join(",")')"
      [[ "$keys" == "00,11" ]] || { echo "ASSERT [$name] counts keys=$keys want 00,11" >&2; return 1; }
      echo "$sample" | jq -e '(.counts | add) == .shots' >/dev/null || { echo "ASSERT [$name] want (.counts | add) == .shots" >&2; return 1; }
      assert_distribution_bound "$name" "$manifest" true || return 1
      ;;

    expectation_xz)
      jq -e '.result_type == "expectation"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == expectation" >&2; return 1; }
      local exp x z
      exp="$(jq_expectation_merged "$manifest")"
      x="$(echo "$exp" | jq -r '.values.X.real')"
      z="$(echo "$exp" | jq -r '.values.Z.real')"
      jq_abs_le "$x" "1.0" "1e-5" || { echo "ASSERT [$name] X.real=$x want ≈1" >&2; return 1; }
      jq_abs_le "$z" "0.0" "1e-5" || { echo "ASSERT [$name] Z.real=$z want ≈0" >&2; return 1; }
      ;;

    multislice_4q_counts)
      # MP1 fixes the idle q0 and q1 with one branch each, and a v2 leaf drops them: one partition.
      jq -e '.total_partitions == 1' "$manifest" >/dev/null || { echo "ASSERT [$name] want .total_partitions == 1" >&2; return 1; }
      local sample shots keys
      sample="$(jq_sample_merged "$manifest")"
      shots="$(echo "$sample" | jq -r '.shots')"
      [[ "$shots" == "512" ]] || { echo "ASSERT [$name] shots=$shots want 512" >&2; return 1; }
      keys="$(echo "$sample" | jq -r '.counts | keys | sort | join(",")')"
      [[ "$keys" == "00,11" ]] || { echo "ASSERT [$name] counts keys=$keys want 00,11" >&2; return 1; }
      assert_distribution_bound "$name" "$manifest" true || return 1
      ;;

    mid_circuit_if_measure)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == sample_counts" >&2; return 1; }
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 512' >/dev/null || { echo "ASSERT [$name] want .shots == 512" >&2; return 1; }
      echo "$sample" | jq -e '(.counts | has("00")) and (.counts | has("11"))' >/dev/null || {
        echo "ASSERT [$name] expected both 00 and 11 in counts: $(echo "$sample" | jq -c '.counts')" >&2
        return 1
      }
      assert_distribution_bound "$name" "$manifest" true trajectory_air_zk_composed_shot_v1 || return 1
      ;;

    multislice_4q_mid_circuit_if)
      # MP1 idle-wire contraction of a mid-circuit IF demo (parent 4q → compact 2q leaf).
      # Idle-only MP1 dispatches a single leaf (total_partitions==1) after fixing e_0/e_1.
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == sample_counts" >&2; return 1; }
      jq -e '.total_qubits == 4' "$manifest" >/dev/null || {
        echo "ASSERT [$name] total_qubits want 4" >&2
        return 1
      }
      jq -e '.total_partitions >= 1' "$manifest" >/dev/null || { echo "ASSERT [$name] want .total_partitions >= 1" >&2; return 1; }
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 512' >/dev/null || { echo "ASSERT [$name] want .shots == 512" >&2; return 1; }
      echo "$sample" | jq -e '(.counts | has("00")) and (.counts | has("11"))' >/dev/null || {
        echo "ASSERT [$name] expected both 00 and 11 in counts: $(echo "$sample" | jq -c '.counts')" >&2
        return 1
      }
      echo "$sample" | jq -e '(.counts | add) == .shots' >/dev/null || { echo "ASSERT [$name] want (.counts | add) == .shots" >&2; return 1; }
      assert_distribution_bound "$name" "$manifest" true trajectory_air_zk_composed_shot_v1 || return 1
      ;;

    noise_depolarizing_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == sample_counts" >&2; return 1; }
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 512' >/dev/null || { echo "ASSERT [$name] want .shots == 512" >&2; return 1; }
      echo "$sample" | jq -e '(.counts | keys | all(. == "0" or . == "1"))' >/dev/null || { echo "ASSERT [$name] want (.counts | keys | all(. == 0 or . == 1))" >&2; return 1; }
      echo "$sample" | jq -e '(.counts | add) == .shots' >/dev/null || { echo "ASSERT [$name] want (.counts | add) == .shots" >&2; return 1; }
      assert_distribution_bound "$name" "$manifest" false || return 1
      ;;

    tn_cut_scalar_28q)
      jq -e '.result_type == "statevector_scalar"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == statevector_scalar" >&2; return 1; }
      # v1 cuts 28q into 4 slices; a v2 leaf runs the touched wires as one. The amplitude
      # <0|CNOT CNOT|0> = 1 is the sum over the slices either way.
      jq -e '(.slices | length) == .total_partitions' "$manifest" >/dev/null || { echo "ASSERT [$name] want (.slices | length) == .total_partitions" >&2; return 1; }
      local real
      real="$(jq -r '[.slices[] | .complex_result.real // 0] | add' "$manifest")"
      jq_abs_le "$real" "1.0" "1e-5" || { echo "ASSERT [$name] sum of complex_result.real=$real want ≈1" >&2; return 1; }
      ;;

    x_basis_sample_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == sample_counts" >&2; return 1; }
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 1024' >/dev/null || { echo "ASSERT [$name] want .shots == 1024" >&2; return 1; }
      echo "$sample" | jq -e '.counts == {"0":1024}' >/dev/null || {
        echo "ASSERT [$name] counts=$(echo "$sample" | jq -c '.counts') want {\"0\":1024}" >&2
        return 1
      }
      assert_distribution_bound "$name" "$manifest" true || return 1
      ;;

    y_basis_sample_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == sample_counts" >&2; return 1; }
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 1024' >/dev/null || { echo "ASSERT [$name] want .shots == 1024" >&2; return 1; }
      echo "$sample" | jq -e '.counts == {"0":1024}' >/dev/null || {
        echo "ASSERT [$name] counts=$(echo "$sample" | jq -c '.counts') want {\"0\":1024}" >&2
        return 1
      }
      assert_distribution_bound "$name" "$manifest" true || return 1
      ;;

    sample_unmeasured_control)
      # q0 controls q1 but is not measured: fixing it to 0 gave {"0":1024}.
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == sample_counts" >&2; return 1; }
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.counts == {"1":1024}' >/dev/null || {
        echo "ASSERT [$name] counts=$(echo "$sample" | jq -c '.counts') want {\"1\":1024}" >&2
        return 1
      }
      ;;

    expectation_unobserved_cz)
      # H0 H1 CZ H1 is a Bell pair; fixing the unobserved q0 gave ⟨Z1⟩ = 1.
      jq -e '.result_type == "expectation"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == expectation" >&2; return 1; }
      local exp z1 zz
      exp="$(jq_expectation_merged "$manifest")"
      z1="$(echo "$exp" | jq -r '.values.Z1.real')"
      zz="$(echo "$exp" | jq -r '.values.ZZ.real')"
      jq_abs_le "$z1" "0.0" "1e-5" || { echo "ASSERT [$name] Z1.real=$z1 want ≈0" >&2; return 1; }
      jq_abs_le "$zz" "1.0" "1e-5" || { echo "ASSERT [$name] ZZ.real=$zz want ≈1" >&2; return 1; }
      ;;

    multislice_28q_zz)
      jq -e '.result_type == "expectation"' "$manifest" >/dev/null || { echo "ASSERT [$name] want .result_type == expectation" >&2; return 1; }
      # OP1 fixes the 26 idle wires with one branch each, and a v2 leaf drops them: one partition.
      jq -e '.total_partitions == 1' "$manifest" >/dev/null || { echo "ASSERT [$name] want .total_partitions == 1" >&2; return 1; }
      local zz
      zz="$(jq_expectation_merged "$manifest" | jq -r '.values.ZZ.real // .values.zz.real // empty')"
      [[ -n "$zz" ]] || {
        echo "ASSERT [$name] missing ZZ expectation value" >&2
        return 1
      }
      jq_abs_le "$zz" "1.0" "0.05" || {
        echo "ASSERT [$name] ZZ.real=$zz want ≈1" >&2
        return 1
      }
      ;;

    *)
      echo "ASSERT [$name] no golden checks defined (skipped)" >&2
      return 0
      ;;
  esac

  jq -e '.root_hash != null and (.root_hash | length) > 0' "$manifest" >/dev/null || { echo "ASSERT [$name] want .root_hash != null and (.root_hash | length) > 0" >&2; return 1; }
  echo "ASSERT [$name] ok"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  need() { command -v "$1" >/dev/null 2>&1 || { echo "assert_manifest: missing $1" >&2; exit 1; }; }
  need jq
  assert_manifest "${1:?case name}" "${2:?manifest path}"
fi
