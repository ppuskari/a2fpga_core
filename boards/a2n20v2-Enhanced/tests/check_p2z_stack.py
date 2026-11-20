#!/usr/bin/env python3
"""P2Z BL616 Sensei call-path stack regression (portable GCC .su evidence).

The BL616 worker used 3072 bytes in P2Y and is raised to 4096 in P2Z.
NTP file load is a nested worker -> runtime load -> importer chain.
No attempt is made to infer full FreeRTOS/BL616 runtime stack from x86 GCC:
the purpose is to fail if these 3 specific frames grow back to KBs.
"""
import pathlib
import sys

TARGETS = {
    "sensei_tracker_task": 640,
    "sensei_runtime_load": 640,
    "sensei_ntp_import": 640,
}


def run(paths):
    values = {}
    for path in paths:
        for line in pathlib.Path(path).read_text().splitlines():
            fields = line.split("\t")
            if len(fields) < 2:
                continue
            name = fields[0].rsplit(":", 1)[-1]
            if name not in TARGETS:
                continue
            if not fields[1].isdigit():
                raise AssertionError(f"{name}: unknown GCC stack usage {line!r}")
            frame = int(fields[1])
            values[name] = frame
            if frame > TARGETS[name]:
                raise AssertionError(
                    f"{name} uses {frame} B (> {TARGETS[name]} B); "
                    "move scratch to static task-owned memory"
                )
    missing = TARGETS.keys() - values.keys()
    if missing:
        raise AssertionError(f"Missing stack report: {sorted(missing)}")
    total = sum(values.values())
    if total > 1300:
        raise AssertionError(f"Nested stack path {total} B exceeds 1300 B")
    print("PASS P2Z: native NTP worker/loader/importer GCC stack frames:", values)
    print(f"PASS P2Z: portable nested frame total {total} B (< 1300 B)")
    print("NOTE: not a BL616 target compiler stack or a hardware proof")


if __name__ == "__main__":
    run(sys.argv[1:])
