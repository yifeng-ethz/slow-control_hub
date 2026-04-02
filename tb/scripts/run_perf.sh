#!/usr/bin/env bash
# ============================================================================
# run_perf.sh — PERF category harness runner
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PERF_CASES=(
  T300 T301 T302 T303 T304 T305 T306 T307 T308 T309
  T310 T311 T312 T313 T314 T315 T316 T317 T318 T319
  T320 T321 T322 T323 T324 T325 T326 T327 T328 T329
  T330 T331 T332 T333 T334 T335 T336 T337 T338 T339
  T340 T341 T342 T343 T344 T345 T346 T347 T348 T349
  T350 T351 T352 T353 T354 T355
)

"$SCRIPT_DIR/run_uvm_case.sh" "${PERF_CASES[@]}"
