"""Compares two or three `dusk:perf_end` envelopes on the metrics that mean
something.

Counts only, and normalised per painted frame. `perf.sh`'s header records why
at length: the milliseconds vary more between two runs of the same code than
between two versions of it, and the block attribution's micros are nested, so
ranking by them ranks by tree depth. A count divided by `PAINT` is the one
figure that survived every check.

Usage: python3 tool/dusk/perf_compare.py <label>=<file.json> [...]
"""

import json
import sys

METRICS = [
    "_RenderLayoutBuilder",
    "RenderFractionallySizedOverflowBox",
    "RenderConstrainedBox",
    "RenderSemanticsAnnotations",
    "RenderFlex",
    "RenderPadding",
    "RenderMouseRegion",
]


def read(path):
    envelope = json.load(open(path))
    blocks = {b["name"]: b["count"] for b in envelope.get("blockAttribution") or []}
    # PAINT is the frame count the other spans have to be divided by. A run that
    # drew ten per cent fewer frames reports ten per cent fewer of everything,
    # which reads as an improvement and is not one.
    return blocks, blocks.get("PAINT") or 1


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1

    runs = []
    for arg in argv[1:]:
        label, _, path = arg.partition("=")
        blocks, frames = read(path)
        runs.append((label, blocks, frames))

    width = max(len(m) for m in METRICS) + 2
    head = f"{'metric':<{width}}" + "".join(f"{label:>14}" for label, _, _ in runs)
    if len(runs) > 1:
        head += f"{'per frame':>12}"
    print(head)
    print(f"{'PAINT frames':<{width}}" + "".join(f"{f:>14}" for _, _, f in runs))
    print("-" * len(head))

    for metric in METRICS:
        counts = [blocks.get(metric, 0) for _, blocks, _ in runs]
        row = f"{metric:<{width}}" + "".join(f"{c:>14}" for c in counts)
        if len(runs) > 1:
            first = counts[0] / runs[0][2]
            last = counts[-1] / runs[-1][2]
            row += f"{(last / first - 1) * 100:>11.1f}%" if first else f"{'-':>12}"
        print(row)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
