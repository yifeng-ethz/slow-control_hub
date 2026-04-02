#!/usr/bin/env bash
# ============================================================================
# run_edge.sh — EDGE category harness runner
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AVALON_EDGE_CASES=(
  T400 T401 T402 T403 T404 T405 T406 T410 T411 T412 T413 T414
  T415 T416 T417 T418 T419 T420 T421 T422 T423 T424 T425 T426
  T427 T428 T429 T432 T434 T435 T436 T437 T438 T439 T440 T441
  T442 T443 T444 T445 T446 T447 T448 T449
)

AXI4_EDGE_CASES=(
  T407 T408 T409 T430 T431 T433
)

BUS_TYPE=AVALON "$SCRIPT_DIR/run_directed.sh" "${AVALON_EDGE_CASES[@]}"
BUS_TYPE=AXI4   "$SCRIPT_DIR/run_directed.sh" "${AXI4_EDGE_CASES[@]}"
