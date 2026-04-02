#!/usr/bin/env bash
# ============================================================================
# run_error.sh — ERROR category harness runner
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AVALON_ERROR_CASES=(
  T500 T501 T502 T503 T509 T510 T511 T512 T513 T514 T515 T516
  T517 T518 T519 T520 T521 T522 T523 T524 T525 T526 T527 T528
  T529 T530 T531 T535 T536 T537 T538 T539 T540 T541 T542 T543
  T544 T546 T547 T548 T549
)

AXI4_ERROR_CASES=(
  T504 T505 T506 T507 T508 T532 T533 T534 T535 T536 T537 T538
  T539 T545
)

BUS_TYPE=AVALON "$SCRIPT_DIR/run_directed.sh" "${AVALON_ERROR_CASES[@]}"
BUS_TYPE=AXI4   "$SCRIPT_DIR/run_directed.sh" "${AXI4_ERROR_CASES[@]}"
