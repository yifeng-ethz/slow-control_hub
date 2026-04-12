#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  run_vcd_case.sh --mode directed --case smoke_basic [--bus AVALON] [--out waves/generated/smoke_basic.vcd]
  run_vcd_case.sh --mode uvm --case T300 [--bus AVALON] [--uvm-test sc_hub_case_test] [--vsim-plusargs '+SC_HUB_PROFILE=perf_stream']
EOF
}

MODE=""
CASE_ID=""
BUS_TYPE="AVALON"
UVM_TESTNAME="sc_hub_case_test"
OUT=""
WORK="work_wave_capture"
VSIM_PLUSARGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --case) CASE_ID="$2"; shift 2 ;;
    --bus) BUS_TYPE="$2"; shift 2 ;;
    --uvm-test) UVM_TESTNAME="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --vsim-plusargs) VSIM_PLUSARGS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$MODE" ] || [ -z "$CASE_ID" ]; then
  usage
  exit 2
fi

mkdir -p "$TB_DIR/waves/generated"
if [ -z "$OUT" ]; then
  OUT="$TB_DIR/waves/generated/${CASE_ID}_${BUS_TYPE}.vcd"
fi

case "$MODE" in
  directed)
    make -C "$TB_DIR" run_vcd WORK="$WORK" BUS_TYPE="$BUS_TYPE" TEST_NAME="$CASE_ID" VCD_FILE="$OUT"
    ;;
  uvm)
    if [ -z "$VSIM_PLUSARGS" ]; then
      VSIM_PLUSARGS="+SC_HUB_CASE_ID=${CASE_ID}"
    else
      VSIM_PLUSARGS="+SC_HUB_CASE_ID=${CASE_ID} ${VSIM_PLUSARGS}"
    fi
    make -C "$TB_DIR" run_uvm_vcd WORK="$WORK" BUS_TYPE="$BUS_TYPE" UVM_TESTNAME="$UVM_TESTNAME" UVM_VCD_FILE="$OUT" SIM_PLUSARGS="$VSIM_PLUSARGS"
    ;;
  *)
    echo "unsupported mode: $MODE" >&2
    exit 2
    ;;
 esac

echo "$OUT"
