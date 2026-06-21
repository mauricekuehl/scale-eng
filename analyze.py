#!/usr/bin/env python3
"""Generate charts from k6 benchmark results in ./benchmarks/."""

import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

BENCHMARKS_DIR = Path(__file__).parent / "benchmarks"

FILENAME_RE = re.compile(
    r"^\d{8}T\d{6}Z"
    r"-(?P<profile>steady|spike|breakpoint)"
    r"-(?P<mode>query|read|mixed)"
    r"(?:-(?P<distribution>constant|uniform|hotspot))?"
    r"-summary\.json$"
)


@dataclass
class Run:
    label: str
    variant: str
    p95_ms: float
    error_pct: float
    req_rate: float


def parse_file(path: Path, label: str) -> Run | None:
    m = FILENAME_RE.match(path.name)
    if not m:
        return None

    try:
        data = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None

    metrics = data.get("metrics", {})
    p95 = metrics.get("http_req_duration", {}).get("p(95)", 0.0)
    error_rate = metrics.get("http_req_failed", {}).get("value", 0.0)
    req_rate = metrics.get("http_reqs", {}).get("rate", 0.0)

    parts = [m.group("profile"), m.group("mode")]
    if m.group("distribution"):
        parts.append(m.group("distribution"))

    return Run(
        label=label,
        variant="-".join(parts),
        p95_ms=p95,
        error_pct=error_rate * 100,
        req_rate=req_rate,
    )


def load_runs() -> list[Run]:
    runs: list[Run] = []

    subdirs = sorted(d for d in BENCHMARKS_DIR.iterdir() if d.is_dir())
    if subdirs:
        for subdir in subdirs:
            for path in sorted(subdir.glob("*-summary.json")):
                run = parse_file(path, label=subdir.name)
                if run:
                    runs.append(run)
    else:
        for path in sorted(BENCHMARKS_DIR.glob("*-summary.json")):
            run = parse_file(path, label="run")
            if run:
                runs.append(run)

    return runs


def plot_metric(
    runs: list[Run],
    attr: str,
    ylabel: str,
    title: str,
    ax: plt.Axes,
) -> None:
    variant_values: dict[str, dict[str, float]] = defaultdict(dict)
    for run in runs:
        variant_values[run.variant][run.label] = getattr(run, attr)

    variants = sorted(variant_values)
    labels = sorted({r.label for r in runs})
    n = len(labels)

    x = np.arange(len(variants))
    width = 0.8 / n
    colors = plt.cm.tab10(np.linspace(0, 0.9, n))

    for i, label in enumerate(labels):
        values = [variant_values[v].get(label, 0.0) for v in variants]
        offset = (i - n / 2 + 0.5) * width
        bars = ax.bar(x + offset, values, width, label=label, color=colors[i])

        for bar, val in zip(bars, values):
            if val > 0:
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_height(),
                    f"{val:.1f}",
                    ha="center",
                    va="bottom",
                    fontsize=7,
                )

    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_xticks(x)
    ax.set_xticklabels(variants, rotation=35, ha="right", fontsize=8)
    ax.set_xlim(-0.5, len(variants) - 0.5)
    ax.yaxis.grid(True, linestyle="--", alpha=0.5)
    ax.set_axisbelow(True)

    if n > 1:
        ax.legend()


def label_sort_key(label: str) -> tuple[float, str]:
    # Sort node-count labels ("1-node", "3-node", ...) numerically, others A-Z.
    m = re.match(r"^(\d+)", label)
    return (float(m.group(1)) if m else float("inf"), label)


def plot_scaling(runs: list[Run], ax: plt.Axes) -> None:
    # The headline slide: throughput per variant as the configuration scales out.
    # x = label (e.g. node count), one line per variant. A well-scaling system
    # produces upward-sloping lines.
    variant_values: dict[str, dict[str, float]] = defaultdict(dict)
    for run in runs:
        variant_values[run.variant][run.label] = run.req_rate

    labels = sorted({r.label for r in runs}, key=label_sort_key)
    for variant in sorted(variant_values):
        values = [variant_values[variant].get(label) for label in labels]
        ax.plot(labels, values, marker="o", label=variant)
        for x, val in enumerate(values):
            if val:
                ax.annotate(
                    f"{val:.0f}",
                    (x, val),
                    textcoords="offset points",
                    xytext=(0, 6),
                    ha="center",
                    fontsize=7,
                )

    ax.set_ylabel("req/s")
    ax.set_title("Throughput vs Configuration (scaling curve)")
    ax.yaxis.grid(True, linestyle="--", alpha=0.5)
    ax.set_axisbelow(True)
    ax.legend()


def main() -> None:
    if not BENCHMARKS_DIR.exists():
        print(f"error: {BENCHMARKS_DIR} does not exist", file=sys.stderr)
        sys.exit(1)

    runs = load_runs()
    if not runs:
        print("No benchmark files found.", file=sys.stderr)
        sys.exit(1)

    labels = sorted({r.label for r in runs}, key=label_sort_key)
    print(f"Loaded {len(runs)} result(s) across {len(labels)} run(s): {', '.join(labels)}")

    # Add the scaling-curve panel only when there is more than one configuration
    # to compare; with a single label it would just be disconnected dots.
    n_rows = 4 if len(labels) > 1 else 3
    width = max(14, len({r.variant for r in runs}))
    fig, axes = plt.subplots(n_rows, 1, figsize=(width, n_rows * 5.3))
    fig.suptitle("Load Test Results", fontsize=14, fontweight="bold", y=1.01)

    plot_metric(runs, "p95_ms",    "ms",        "p95 Response Time",  axes[0])
    plot_metric(runs, "error_pct", "Error (%)", "Error Rate",         axes[1])
    plot_metric(runs, "req_rate",  "req/s",     "Throughput",         axes[2])
    if n_rows == 4:
        plot_scaling(runs, axes[3])

    fig.tight_layout()

    out_path = BENCHMARKS_DIR / "report.png"
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
