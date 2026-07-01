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
  local name="$1" manifest="$2" want_bound="$3"
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
    jq_sample_slice "$manifest" | jq -e '.distribution_scheme == "born_air_zk_linked_v1"' >/dev/null
    jq_sample_slice "$manifest" | jq -e '(.measurement_spec_hash | length) > 0' >/dev/null
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
      jq -e '.result_type == "statevector_scalar"' "$manifest" >/dev/null
      jq -e '.total_partitions == 1' "$manifest" >/dev/null
      local real
      real="$(jq_scalar_merged "$manifest" | jq -r '.real')"
      jq_abs_le "$real" "0.7071067811865476" "1e-5" || {
        echo "ASSERT [$name] expected complex_result.real ≈ 1/sqrt(2), got $real" >&2
        return 1
      }
      ;;

    sample_bell_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null
      local sample shots keys
      sample="$(jq_sample_merged "$manifest")"
      shots="$(echo "$sample" | jq -r '.shots')"
      [[ "$shots" == "512" ]] || { echo "ASSERT [$name] shots=$shots want 512" >&2; return 1; }
      keys="$(echo "$sample" | jq -r '.counts | keys | sort | join(",")')"
      [[ "$keys" == "00,11" ]] || { echo "ASSERT [$name] counts keys=$keys want 00,11" >&2; return 1; }
      echo "$sample" | jq -e '(.counts | add) == .shots' >/dev/null
      assert_distribution_bound "$name" "$manifest" true
      ;;

    expectation_xz)
      jq -e '.result_type == "expectation"' "$manifest" >/dev/null
      local exp x z
      exp="$(jq_expectation_merged "$manifest")"
      x="$(echo "$exp" | jq -r '.values.X.real')"
      z="$(echo "$exp" | jq -r '.values.Z.real')"
      jq_abs_le "$x" "1.0" "1e-5" || { echo "ASSERT [$name] X.real=$x want ≈1" >&2; return 1; }
      jq_abs_le "$z" "0.0" "1e-5" || { echo "ASSERT [$name] Z.real=$z want ≈0" >&2; return 1; }
      ;;

    multislice_4q_counts)
      jq -e '.total_partitions >= 2' "$manifest" >/dev/null
      local sample shots keys
      sample="$(jq_sample_merged "$manifest")"
      shots="$(echo "$sample" | jq -r '.shots')"
      [[ "$shots" == "512" ]] || { echo "ASSERT [$name] shots=$shots want 512" >&2; return 1; }
      keys="$(echo "$sample" | jq -r '.counts | keys | sort | join(",")')"
      [[ "$keys" == "00,11" ]] || { echo "ASSERT [$name] counts keys=$keys want 00,11" >&2; return 1; }
      assert_distribution_bound "$name" "$manifest" true
      ;;

    mid_circuit_if_measure)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 512' >/dev/null
      echo "$sample" | jq -e '(.counts | has("00")) and (.counts | has("11"))' >/dev/null || {
        echo "ASSERT [$name] expected both 00 and 11 in counts: $(echo "$sample" | jq -c '.counts')" >&2
        return 1
      }
      assert_distribution_bound "$name" "$manifest" false
      ;;

    noise_depolarizing_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 512' >/dev/null
      echo "$sample" | jq -e '(.counts | keys | all(. == "0" or . == "1"))' >/dev/null
      echo "$sample" | jq -e '(.counts | add) == .shots' >/dev/null
      assert_distribution_bound "$name" "$manifest" false
      ;;

    tn_cut_scalar_28q)
      jq -e '.result_type == "statevector_scalar"' "$manifest" >/dev/null
      jq -e '.total_partitions == 4' "$manifest" >/dev/null
      jq -e '(.slices | length) == 4' "$manifest" >/dev/null
      ;;

    x_basis_sample_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 1024' >/dev/null
      echo "$sample" | jq -e '.counts == {"0":1024}' >/dev/null || {
        echo "ASSERT [$name] counts=$(echo "$sample" | jq -c '.counts') want {\"0\":1024}" >&2
        return 1
      }
      assert_distribution_bound "$name" "$manifest" true
      ;;

    y_basis_sample_counts)
      jq -e '.result_type == "sample_counts"' "$manifest" >/dev/null
      local sample
      sample="$(jq_sample_merged "$manifest")"
      echo "$sample" | jq -e '.shots == 1024' >/dev/null
      echo "$sample" | jq -e '.counts == {"0":1024}' >/dev/null || {
        echo "ASSERT [$name] counts=$(echo "$sample" | jq -c '.counts') want {\"0\":1024}" >&2
        return 1
      }
      assert_distribution_bound "$name" "$manifest" true
      ;;

    multislice_28q_zz)
      jq -e '.result_type == "expectation"' "$manifest" >/dev/null
      jq -e '.total_partitions >= 2' "$manifest" >/dev/null
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

  jq -e '.root_hash != null and (.root_hash | length) > 0' "$manifest" >/dev/null
  echo "ASSERT [$name] ok"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  need() { command -v "$1" >/dev/null 2>&1 || { echo "assert_manifest: missing $1" >&2; exit 1; }; }
  need jq
  assert_manifest "${1:?case name}" "${2:?manifest path}"
fi
