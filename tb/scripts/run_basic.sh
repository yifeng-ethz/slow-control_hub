#!/usr/bin/env bash
# ============================================================================
# run_basic.sh — Run currently implemented basic directed tests
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_TOP="$SCRIPT_DIR/../sim/sc_hub_tb_top.sv"
DEFAULT_MAX_TEST="${SC_HUB_MAX_BASIC:-0}"

collect_tests() {
  awk -v bus="${BUS_TYPE:-AVALON}" '
    BEGIN {
      depth = 0;
      active[0] = 1;
      in_dispatch = 0;
    }

    /^[[:space:]]*case[[:space:]]*\(test_name\)/ {
      in_dispatch = 1;
      next;
    }

    in_dispatch && /^[[:space:]]*endcase/ {
      in_dispatch = 0;
      next;
    }

    /^`ifdef[[:space:]]+SC_HUB_BUS_AXI4/ {
      depth++;
      cond[depth] = (bus == "AXI4");
      active[depth] = (active[depth - 1] && cond[depth]);
      next;
    }

    /^`else/ {
      if (depth > 0) {
        active[depth] = (active[depth - 1] && !cond[depth]);
      }
      next;
    }

    /^`endif/ {
      if (depth > 0) {
        depth--;
      }
      next;
    }

    in_dispatch && active[depth] && match($0, /"T[0-9][0-9][0-9]"/) {
      print substr($0, RSTART + 1, 4);
    }
  ' "$TB_TOP"
}

if [ "$DEFAULT_MAX_TEST" -lt 0 ]; then
  echo "SC_HUB_MAX_BASIC must be >= 0 (got: $DEFAULT_MAX_TEST)"
  exit 1
fi

if [ "${1-}" != "" ]; then
  TESTS=("$@")
else
  mapfile -t TESTS < <(collect_tests)
  if [ "$DEFAULT_MAX_TEST" -gt 0 ] && [ "${#TESTS[@]}" -gt "$DEFAULT_MAX_TEST" ]; then
    TESTS=("${TESTS[@]:0:$DEFAULT_MAX_TEST}")
  fi
fi

if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "No directed basic tests are mapped for BUS_TYPE=${BUS_TYPE:-AVALON}"
  exit 1
fi

"$SCRIPT_DIR/run_directed.sh" "${TESTS[@]}"
