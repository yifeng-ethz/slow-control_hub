#!/usr/bin/env python3

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def check_t548() -> int:
    top_files = [
        ROOT / "sc_hub_top.vhd",
        ROOT / "sc_hub_top_axi4.vhd",
    ]
    failures = []

    for path in top_files:
        text = read_text(path)
        clock_inputs = re.findall(r"\b([A-Za-z0-9_]*clk[A-Za-z0-9_]*)\b\s*:\s*in\s+std_logic", text, flags=re.IGNORECASE)
        unique_clocks = sorted(set(clock_inputs))
        if unique_clocks != ["i_clk"]:
            failures.append(
                f"{path.name}: expected single clock input ['i_clk'], saw {unique_clocks}"
            )

        if "i_clk                      (" in text:
            failures.append(f"{path.name}: malformed source parse around i_clk port map")

    if failures:
        print("T548 static check failed:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print("T548 static check passed: single hub/bus clock input is enforced by top-level entities.")
    return 0


def check_t549() -> int:
    vhdl_files = list(ROOT.glob("*.vhd")) + list((ROOT / "fifo").glob("*.vhd"))
    async_reset_paths = []

    for path in sorted(vhdl_files):
        text = read_text(path)
        if re.search(r"process\s*\([^)]*(?:rst|reset)[^)]*\)", text, flags=re.IGNORECASE | re.MULTILINE):
            async_reset_paths.append(path.name)

    if async_reset_paths:
        print("T549 static check failed:")
        for name in async_reset_paths:
            print(f"  - {name}: reset appears in a process sensitivity list")
        return 1

    print("T549 static check passed: VHDL processes are clocked-only; reset is assumed synchronous at integration.")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_static_cases.py <T548|T549>", file=sys.stderr)
        return 2

    case_id = sys.argv[1].strip().upper()
    if case_id == "T548":
        return check_t548()
    if case_id == "T549":
        return check_t549()

    print(f"unsupported static case id: {case_id}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
