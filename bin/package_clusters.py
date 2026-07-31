#!/usr/bin/env python3
"""Create PANFAM cluster deliverables from corrected DIAMOND cluster tables."""

from __future__ import annotations

import argparse
import base64
import gzip
import html
import math
import os
import statistics
import tempfile
from collections import Counter
from pathlib import Path

import pandas as pd


LEVELS = ("deep", "50", "80")
SIZE_BINS = (
    ("1", 1, 1),
    ("2-10", 2, 10),
    ("11-100", 11, 100),
    ("101-500", 101, 500),
    (">500", 501, None),
)
LEVEL_LABELS = {"deep": "DeepClust 0", "50": "DeepClust 50", "80": "DeepClust 80"}
LEVEL_COLORS = {"deep": "#5B7FB2", "50": "#5FA06E", "80": "#B95E63"}
LEVEL_DISPLAY_ORDER = ("80", "50", "deep")


def level_label(level: str) -> str:
    return LEVEL_LABELS.get(level, f"DeepClust {level}")


def ordered_levels(levels) -> list[str]:
    seen = [str(level) for level in levels]
    order = {level: index for index, level in enumerate(LEVEL_DISPLAY_ORDER)}
    return sorted(dict.fromkeys(seen), key=lambda level: (order.get(level, len(order)), level))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clusters-dir", type=Path, required=True)
    parser.add_argument("--cluster-pattern", default="corrected_{level}.tsv.gz")
    parser.add_argument("--all-faa-gz", type=Path, required=True)
    parser.add_argument("--pangenome-families", type=Path, required=True)
    parser.add_argument("--collection-release-id", required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path)
    parser.add_argument("--skip-report", action="store_true")
    parser.add_argument("--levels", nargs="+", default=list(LEVELS))
    parser.add_argument("--compression", default="zstd")
    return parser.parse_args()


def read_clusters(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t", dtype=str)
    if not {"centroid", "member"}.issubset(df.columns):
        raise ValueError(f"{path} must contain centroid and member columns")
    return df[["centroid", "member"]].dropna()


def assign_cluster_ids(df: pd.DataFrame, level: str, release_id: str) -> tuple[pd.DataFrame, pd.DataFrame]:
    sizes = (
        df.groupby("centroid", as_index=False)
        .agg(cluster_size=("member", "size"))
        .sort_values(["cluster_size", "centroid"], ascending=[False, True], kind="mergesort")
        .reset_index(drop=True)
    )
    width = max(6, len(str(len(sizes))))
    sizes["Cluster_id"] = [
        f"PANFAM_{level}_{release_id}_{i:0{width}d}" for i in range(1, len(sizes) + 1)
    ]
    annotated = df.merge(sizes[["centroid", "Cluster_id", "cluster_size"]], on="centroid", how="left")
    annotated["Cluster_level"] = level
    annotated["is_representative"] = annotated["centroid"] == annotated["member"]
    return annotated, sizes


def fasta_records(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt") as handle:
        header = None
        chunks: list[str] = []
        for line in handle:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if header is not None:
                    yield header, "".join(chunks)
                header = line[1:].split()[0]
                chunks = []
            else:
                chunks.append(line)
        if header is not None:
            yield header, "".join(chunks)


def write_representative_fasta(all_faa_gz: Path, cluster_sizes: pd.DataFrame, out_path: Path) -> None:
    centroid_to_cluster = dict(zip(cluster_sizes["centroid"], cluster_sizes["Cluster_id"]))
    remaining = set(centroid_to_cluster)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(out_path, "wt") as out:
        for seq_id, seq in fasta_records(all_faa_gz):
            cluster_id = centroid_to_cluster.get(seq_id)
            if cluster_id is None:
                continue
            out.write(f">{cluster_id} representative={seq_id}\n")
            out.write(seq + "\n")
            remaining.discard(seq_id)
    if remaining:
        missing = ", ".join(sorted(remaining)[:10])
        raise RuntimeError(f"{len(remaining)} representatives were absent from FASTA; first missing: {missing}")


def read_pangenome_families(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t", dtype={"Pangenome_family_id": str})
    required = {"Pangenome_id", "Pangenome_family_id"}
    if not required.issubset(df.columns):
        raise ValueError(f"{path} must contain columns {sorted(required)}")
    df["Pangenome_id"] = pd.to_numeric(df["Pangenome_id"], errors="raise").astype("int64")
    return df[["Pangenome_id", "Pangenome_family_id"]].dropna().drop_duplicates()


def write_parquets(
    clusters_by_level: dict[str, pd.DataFrame],
    pangenome_families: pd.DataFrame,
    out_dir: Path,
    compression: str,
) -> None:
    parquet_dir = out_dir / "parquet"
    per_pangenome_dir = parquet_dir / "pangenomes"
    parquet_dir.mkdir(parents=True, exist_ok=True)
    per_pangenome_dir.mkdir(parents=True, exist_ok=True)

    per_pangenome_frames = []
    for level, clusters in clusters_by_level.items():
        joined = clusters.merge(
            pangenome_families,
            left_on="member",
            right_on="Pangenome_family_id",
            how="inner",
        )
        global_df = joined[
            ["Pangenome_id", "Pangenome_family_id", "Cluster_id", "is_representative"]
        ].drop_duplicates()
        global_df.to_parquet(parquet_dir / f"PANFAM_{level}.parquet", index=False, compression=compression)

        per_level = joined[
            ["Pangenome_id", "Pangenome_family_id", "Cluster_level", "Cluster_id"]
        ].drop_duplicates()
        per_pangenome_frames.append(per_level)

    all_per_pangenome = pd.concat(per_pangenome_frames, ignore_index=True).drop_duplicates()
    for pangenome_id, df in all_per_pangenome.groupby("Pangenome_id", sort=True):
        out = per_pangenome_dir / f"PANFAM_p{pangenome_id}.parquet"
        df[["Pangenome_family_id", "Cluster_level", "Cluster_id"]].to_parquet(
            out, index=False, compression=compression
        )


def cluster_size_counts(df: pd.DataFrame) -> Counter:
    return Counter(df.groupby("centroid").size().tolist())


def metrics_row(section: str, level: str, df: pd.DataFrame) -> dict[str, int | float | str]:
    sizes = df.groupby("centroid").size().tolist()
    clusters = len(sizes)
    members = len(df)
    singletons = sum(size == 1 for size in sizes)
    return {
        "section": section,
        "cluster_level": level,
        "members": members,
        "clusters": clusters,
        "singletons": singletons,
        "singleton_cluster_fraction": singletons / clusters if clusters else 0,
        "singleton_member_fraction": singletons / members if members else 0,
        "avg_cluster_size": statistics.mean(sizes) if sizes else 0,
        "median_cluster_size": statistics.median(sizes) if sizes else 0,
        "max_cluster_size": max(sizes) if sizes else 0,
    }


def build_summary_metrics(before: dict[str, pd.DataFrame], after: dict[str, pd.DataFrame]) -> pd.DataFrame:
    rows = []
    for section, tables in (("before_ec", before), ("after_ec", after)):
        for level, df in tables.items():
            rows.append(metrics_row(section, level, df))
    return pd.DataFrame(rows)


def write_minimal_report(summary: pd.DataFrame, out_path: Path) -> None:
    columns = [
        "section",
        "cluster_level",
        "members",
        "clusters",
        "singletons",
        "singleton_cluster_fraction",
        "avg_cluster_size",
        "median_cluster_size",
        "max_cluster_size",
    ]
    out_path.write_text(summary[columns].to_csv(sep="\t", index=False), encoding="utf-8")


def build_cluster_size_distribution(
    tables_by_section: dict[str, dict[str, pd.DataFrame]]
) -> pd.DataFrame:
    rows = []
    for section, tables in tables_by_section.items():
        for level, df in tables.items():
            counts = cluster_size_counts(df)
            total_clusters = sum(counts.values())
            total_members = sum(size * count for size, count in counts.items())
            for size, count in sorted(counts.items()):
                members = size * count
                rows.append(
                    {
                        "section": section,
                        "cluster_level": level,
                        "cluster_size": size,
                        "n_clusters": count,
                        "n_members": members,
                        "cluster_fraction": count / total_clusters if total_clusters else 0,
                        "member_fraction": members / total_members if total_members else 0,
                    }
                )
    return pd.DataFrame(rows)


def build_size_bin_summary(distribution: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (section, level), sub in distribution.groupby(["section", "cluster_level"], sort=False):
        total_clusters = sub["n_clusters"].sum()
        total_members = sub["n_members"].sum()
        for label, lower, upper in SIZE_BINS:
            if upper is None:
                in_bin = sub[sub["cluster_size"] >= lower]
            else:
                in_bin = sub[(sub["cluster_size"] >= lower) & (sub["cluster_size"] <= upper)]
            n_clusters = int(in_bin["n_clusters"].sum())
            n_members = int(in_bin["n_members"].sum())
            rows.append(
                {
                    "section": section,
                    "cluster_level": level,
                    "size_bin": label,
                    "n_clusters": n_clusters,
                    "n_members": n_members,
                    "cluster_fraction": n_clusters / total_clusters if total_clusters else 0,
                    "member_fraction": n_members / total_members if total_members else 0,
                }
            )
    return pd.DataFrame(rows)


def rank_curve(counts: Counter) -> tuple[list[int], list[int]]:
    ranks: list[int] = []
    sizes: list[int] = []
    rank = 1
    for size in sorted(counts, reverse=True):
        count = counts[size]
        ranks.extend([rank, rank + count - 1])
        sizes.extend([size, size])
        rank += count
    return ranks, sizes


def rank_curve_from_distribution(distribution: pd.DataFrame) -> tuple[list[int], list[int]]:
    ranks: list[int] = []
    sizes: list[int] = []
    rank = 1
    for _, row in distribution.sort_values("cluster_size", ascending=False).iterrows():
        size = int(row["cluster_size"])
        count = int(row["n_clusters"])
        ranks.extend([rank, rank + count - 1])
        sizes.extend([size, size])
        rank += count
    return ranks, sizes


def configure_matplotlib():
    cache_root = Path(tempfile.gettempdir()) / "panannotator-matplotlib"
    os.environ.setdefault("XDG_CACHE_HOME", str(cache_root / "xdg"))
    os.environ.setdefault("MPLCONFIGDIR", str(cache_root / "config"))
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import matplotlib.ticker as ticker

    matplotlib.rcParams.update(
        {
            "figure.dpi": 120,
            "savefig.dpi": 400,
            "savefig.bbox": "tight",
            "savefig.pad_inches": 0.04,
            "font.family": "DejaVu Sans",
            "font.size": 8.5,
            "axes.titlesize": 9,
            "axes.labelsize": 9,
            "xtick.labelsize": 8,
            "ytick.labelsize": 8,
            "legend.fontsize": 8,
            "axes.edgecolor": "#BDBDBD",
            "axes.linewidth": 0.9,
            "axes.grid": True,
            "axes.axisbelow": True,
            "grid.color": "#D8D8D8",
            "grid.linewidth": 0.8,
            "grid.alpha": 0.9,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )
    return plt, ticker


def clean_axes(ax, *, keep_x_grid: bool = False) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(axis="x", visible=keep_x_grid)
    ax.grid(axis="y", visible=True)


def percent_label(value: float) -> str:
    return f"{100 * value:.1f}%"


def sci_tick_label(value: float) -> str:
    if value <= 0:
        return "0"
    exponent = int(math.floor(math.log10(value)))
    coefficient = value / (10**exponent)
    if abs(coefficient - round(coefficient)) < 1e-8:
        coefficient_text = str(int(round(coefficient)))
    else:
        coefficient_text = f"{coefficient:.1f}".rstrip("0").rstrip(".")
    return rf"${coefficient_text} \times 10^{exponent}$"


def short_number(value: float) -> str:
    abs_value = abs(value)
    if abs_value >= 1_000_000:
        return f"{value / 1_000_000:.2f}M"
    if abs_value >= 1_000:
        return f"{value / 1_000:.1f}k"
    return f"{value:.0f}"


def plot_rank_distribution(before: dict[str, pd.DataFrame], after: dict[str, pd.DataFrame], out_path: Path) -> None:
    plt, _ticker = configure_matplotlib()

    levels = ordered_levels(after)
    if not levels:
        return

    fig, axes = plt.subplots(
        len(levels),
        1,
        figsize=(10, max(3.2, 3.1 * len(levels))),
        sharex=True,
        constrained_layout=True,
    )
    if len(levels) == 1:
        axes = [axes]

    for ax, level in zip(axes, levels):
        plotted = False
        level_color = LEVEL_COLORS.get(level, "#5B7FB2")
        for tables, label, linestyle, alpha, linewidth in (
            (before, "Before error correction", "--", 0.45, 1.8),
            (after, "After error correction", "-", 1.0, 2.2),
        ):
            counts = cluster_size_counts(tables[level])
            if not counts:
                continue
            x, y = rank_curve(counts)
            ax.plot(
                x,
                y,
                linewidth=linewidth,
                linestyle=linestyle,
                color=level_color,
                alpha=alpha,
                label=f"{level_label(level)} {label.lower()}",
            )
            plotted = True

        after_counts = cluster_size_counts(after[level])
        singleton_count = after_counts.get(1, 0)
        cluster_count = sum(after_counts.values())
        ax.set_title(
            f"Cluster level {level}: {cluster_count:,} clusters, {singleton_count:,} singletons after correction",
            loc="left",
            fontsize=7.8,
            fontweight="bold",
        )
        ax.set_ylabel("Cluster size")
        clean_axes(ax)
        if plotted:
            ax.set_xscale("log")
            ax.set_yscale("log")
            ax.legend(frameon=False, loc="upper right")

    axes[-1].set_xlabel("Cluster rank, largest to smallest")
    fig.suptitle("PANFAM Cluster Size Rank Distribution", fontsize=9.5, fontweight="bold")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path)
    plt.close(fig)


def plot_rank_distribution_from_distribution(distribution: pd.DataFrame, out_path: Path) -> None:
    plt, _ticker = configure_matplotlib()

    after = distribution[distribution["section"] == "after_ec"]
    levels = ordered_levels(after["cluster_level"].drop_duplicates())
    if not levels:
        return

    fig, axes = plt.subplots(
        len(levels),
        1,
        figsize=(10, max(3.2, 3.1 * len(levels))),
        sharex=True,
        constrained_layout=True,
    )
    if len(levels) == 1:
        axes = [axes]

    for ax, level in zip(axes, levels):
        level_color = LEVEL_COLORS.get(level, "#5B7FB2")
        for section, label, linestyle, alpha, linewidth in (
            ("before_ec", "Before error correction", "--", 0.45, 1.8),
            ("after_ec", "After error correction", "-", 1.0, 2.2),
        ):
            sub = distribution[
                (distribution["section"] == section) & (distribution["cluster_level"] == level)
            ]
            if sub.empty:
                continue
            x, y = rank_curve_from_distribution(sub)
            ax.plot(
                x,
                y,
                linewidth=linewidth,
                linestyle=linestyle,
                color=level_color,
                alpha=alpha,
                label=f"{level_label(level)} {label.lower()}",
            )

        after_sub = after[after["cluster_level"] == level]
        singleton_count = int(after_sub.loc[after_sub["cluster_size"] == 1, "n_clusters"].sum())
        cluster_count = int(after_sub["n_clusters"].sum())
        ax.set_title(
            f"Cluster level {level}: {cluster_count:,} clusters, {singleton_count:,} singletons after correction",
            loc="left",
            fontsize=7.8,
            fontweight="bold",
        )
        ax.set_ylabel("Cluster size")
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.legend(frameon=False, loc="upper right")
        clean_axes(ax)

    axes[-1].set_xlabel("Cluster rank, largest to smallest")
    fig.suptitle("PANFAM Cluster Size Rank Distribution", fontsize=9.5, fontweight="bold")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path)
    plt.close(fig)


def plot_hist_distribution(distribution: pd.DataFrame, out_path: Path) -> None:
    plt, _ticker = configure_matplotlib()
    import numpy as np

    after = distribution[distribution["section"] == "after_ec"]
    max_size = int(after["cluster_size"].max()) if not after.empty else 1
    bins = sorted(set(int(x) for x in np.logspace(0, np.log10(max_size + 1), 55)))
    if len(bins) < 2:
        bins = [1, max_size + 1]

    fig, ax = plt.subplots(figsize=(7.2, 4.8))
    for level in ordered_levels(after["cluster_level"].drop_duplicates()):
        sub = after[after["cluster_level"] == level]
        if not sub.empty:
            hist, edges = np.histogram(
                sub["cluster_size"].astype(int).to_numpy(),
                bins=bins,
                weights=sub["n_clusters"].astype(int).to_numpy(),
            )
            ax.stairs(
                hist,
                edges,
                linewidth=2.2,
                color=LEVEL_COLORS.get(level, "#5B7FB2"),
                label=level_label(level),
            )
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Cluster size")
    ax.set_ylabel("Number of clusters")
    ax.set_title("PANFAM cluster size distribution after error correction")
    ax.legend(frameon=False, loc="upper right")
    clean_axes(ax)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path)
    plt.close(fig)


def plot_ecdf(distribution: pd.DataFrame, out_path: Path, *, ccdf: bool = False) -> None:
    plt, _ticker = configure_matplotlib()
    after = distribution[distribution["section"] == "after_ec"]
    fig, ax = plt.subplots(figsize=(7.0, 4.7))
    has_points = False
    for level in ordered_levels(after["cluster_level"].drop_duplicates()):
        sub = after[after["cluster_level"] == level]
        if sub.empty:
            continue
        sub = sub.sort_values("cluster_size")
        values = sub["cluster_size"].astype(int).tolist()
        cumulative = sub["n_clusters"].astype(int).cumsum()
        total = int(sub["n_clusters"].sum())
        y = (cumulative / total).tolist()
        if ccdf:
            y = [1 - value for value in y]
            values = [value for value, y_value in zip(values, y) if y_value > 0]
            y = [y_value for y_value in y if y_value > 0]
        if not values:
            continue
        has_points = True
        ax.step(
            values,
            y,
            where="post",
            label=level_label(level),
            color=LEVEL_COLORS.get(level, "#5B7FB2"),
            linewidth=2,
        )
    ax.set_xscale("log")
    if ccdf:
        if has_points:
            ax.set_yscale("log")
        ax.set_ylabel("Fraction of clusters with size >= x")
        ax.set_title("PANFAM cluster size tail distribution")
    else:
        ax.set_ylabel("Cumulative fraction of clusters")
        ax.set_title("PANFAM cluster size ECDF")
    ax.set_xlabel("Cluster size")
    ax.legend(frameon=False, loc="best")
    clean_axes(ax)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path)
    plt.close(fig)


def plot_size_bins(bin_summary: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()
    after = bin_summary[bin_summary["section"] == "after_ec"]
    levels = ordered_levels(after["cluster_level"].drop_duplicates())
    bins = list(after["size_bin"].drop_duplicates())
    import numpy as np

    x = np.arange(len(bins))
    width = min(0.82 / max(len(levels), 1), 0.22)
    offsets = (np.arange(len(levels)) - (len(levels) - 1) / 2) * width
    fig, axes = plt.subplots(2, 1, figsize=(10.5, 8.0), sharex=True)
    for ax, value_col, ylabel in (
        (axes[0], "cluster_fraction", "Fraction of clusters"),
        (axes[1], "member_fraction", "Fraction of proteins"),
    ):
        for offset, level in zip(offsets, levels):
            sub = after[after["cluster_level"] == level].set_index("size_bin").reindex(bins)
            values = sub[value_col].fillna(0).to_numpy()
            bars = ax.bar(
                x + offset,
                values,
                width=width,
                color=LEVEL_COLORS.get(level, "#5B7FB2"),
                edgecolor="white",
                linewidth=0.8,
                label=level_label(level),
            )
            for bar, value in zip(bars, values):
                if value <= 0:
                    continue
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_height() + 0.004,
                    percent_label(value),
                    ha="center",
                    va="bottom",
                    rotation=90,
                    fontsize=6,
                    color="#2B2B2B",
                )
        ax.set_ylabel(ylabel)
        ax.set_ylim(0, min(1.0, max(float(bin_summary[value_col].max()) * 1.22, 0.01)))
        ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0, decimals=0))
        ax.grid(axis="x", visible=False)
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)
    axes[0].set_title("PANFAM cluster size bins after error correction")
    axes[0].legend(frameon=False, loc="upper right", ncol=2)
    axes[1].set_xticks(x)
    axes[1].set_xticklabels(bins)
    axes[1].set_xlabel("Cluster size bin")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_cluster_reduction_summary(summary: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()
    import numpy as np

    levels = ordered_levels(summary["cluster_level"].drop_duplicates())
    labels = [level_label(level) for level in levels]
    x = np.arange(len(levels))
    width = 0.34

    fig, axes = plt.subplots(1, 2, figsize=(12.6, 4.6))

    for offset, section, label, alpha in (
        (-width / 2, "before_ec", "Before error correction", 0.5),
        (width / 2, "after_ec", "After error correction", 1.0),
    ):
        sub = summary[summary["section"] == section].set_index("cluster_level").reindex(levels)
        bars = axes[0].bar(
            x + offset,
            sub["clusters"],
            width=width,
            color=[LEVEL_COLORS.get(level, "#5B7FB2") for level in levels],
            alpha=alpha,
            edgecolor="white",
            linewidth=1.0,
            label=label,
        )
        axes[0].bar_label(
            bars,
            labels=[short_number(float(value)) for value in sub["clusters"]],
            fontsize=7,
            padding=2,
            rotation=90,
        )
    axes[0].set_title("Number of clusters across thresholds")
    axes[0].set_ylabel("Number of clusters")
    axes[0].set_xticks(x)
    axes[0].set_xticklabels(labels, rotation=28, ha="right")
    axes[0].set_yscale("log")
    y_max = max(float(value) for value in summary["clusters"])
    y_ticks = [tick for tick in [1e7, 2e7, 6e7] if tick <= y_max * 1.12]
    axes[0].set_yticks(y_ticks)
    axes[0].set_yticklabels([sci_tick_label(tick) for tick in y_ticks])
    axes[0].legend(frameon=False, loc="upper right")
    clean_axes(axes[0])
    axes[0].grid(False)

    after = summary[summary["section"] == "after_ec"].set_index("cluster_level").reindex(levels)
    values = (1 - (after["clusters"] / after["members"])).tolist()
    bars = axes[1].bar(
        labels,
        values,
        color=[LEVEL_COLORS.get(level, "#5B7FB2") for level in levels],
        edgecolor="white",
        linewidth=1.0,
    )
    axes[1].set_title("Reduction to cluster representatives")
    axes[1].set_ylabel("Reduction from input proteins")
    axes[1].set_ylim(0, min(1.0, max(values) * 1.12))
    axes[1].yaxis.set_major_formatter(ticker.PercentFormatter(1.0, decimals=0))
    axes[1].tick_params(axis="x", rotation=28)
    clean_axes(axes[1])
    axes[1].grid(False)
    y0, y1 = axes[1].get_ylim()
    offset = 0.015 * (y1 - y0)
    for bar, value in zip(bars, values):
        axes[1].text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + offset,
            percent_label(value),
            ha="center",
            va="bottom",
            fontsize=8,
            color="#2B2B2B",
        )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_representative_reduction(summary: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()

    after = (
        summary[summary["section"] == "after_ec"]
        .set_index("cluster_level")
        .reindex(ordered_levels(summary["cluster_level"].drop_duplicates()))
        .reset_index()
    )
    labels = [level_label(level) for level in after["cluster_level"]]
    values = (1 - (after["clusters"] / after["members"])).tolist()

    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    bars = ax.bar(
        labels,
        values,
        color=[LEVEL_COLORS.get(level, "#5B7FB2") for level in after["cluster_level"]],
        edgecolor="white",
        linewidth=1.0,
    )
    ax.set_title("Reduction to cluster representatives")
    ax.set_ylabel("Reduction from input proteins")
    ax.set_xlabel("")
    ax.set_ylim(0, min(1.0, max(values) * 1.12))
    ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0, decimals=0))
    ax.tick_params(axis="x", rotation=28)
    clean_axes(ax)
    y0, y1 = ax.get_ylim()
    offset = 0.015 * (y1 - y0)
    for bar, value in zip(bars, values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + offset,
            percent_label(value),
            ha="center",
            va="bottom",
            fontsize=8,
            color="#2B2B2B",
        )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_singleton_rates(summary: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()
    after = (
        summary[summary["section"] == "after_ec"]
        .set_index("cluster_level")
        .reindex(ordered_levels(summary["cluster_level"].drop_duplicates()))
        .reset_index()
    )
    levels = after["cluster_level"].tolist()
    import numpy as np

    x = np.arange(len(levels))
    width = 0.36
    fig, ax = plt.subplots(figsize=(7.8, 4.6))
    bars_clusters = ax.bar(
        x - width / 2,
        after["singleton_cluster_fraction"],
        width=width,
        color="#5B7FB2",
        edgecolor="white",
        linewidth=1.0,
        label="Singleton clusters / clusters",
    )
    bars_proteins = ax.bar(
        x + width / 2,
        after["singleton_member_fraction"],
        width=width,
        color="#D08A61",
        edgecolor="white",
        linewidth=1.0,
        label="Singletons / proteins",
    )
    ax.set_xticks(x)
    ax.set_xticklabels([level_label(level) for level in levels], rotation=28, ha="right")
    ax.set_ylabel("Fraction")
    ax.set_title("PANFAM singleton rates after error correction")
    max_value = max(after["singleton_cluster_fraction"].tolist() + after["singleton_member_fraction"].tolist())
    ax.set_ylim(0, max_value * 1.18)
    ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0))
    ax.legend(frameon=False, loc="upper left")
    clean_axes(ax)
    for bars, values in (
        (bars_clusters, after["singleton_cluster_fraction"].tolist()),
        (bars_proteins, after["singleton_member_fraction"].tolist()),
    ):
        y0, y1 = ax.get_ylim()
        offset = 0.014 * (y1 - y0)
        for bar, value in zip(bars, values):
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                bar.get_height() + offset,
                percent_label(value),
                ha="center",
                va="bottom",
                fontsize=7,
                color="#2B2B2B",
            )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def write_analysis_outputs(
    before: dict[str, pd.DataFrame],
    after: dict[str, pd.DataFrame],
    report_dir: Path,
) -> tuple[pd.DataFrame, pd.DataFrame, list[Path]]:
    tables_dir = report_dir / "tables"
    plots_dir = report_dir / "plots"
    tables_dir.mkdir(parents=True, exist_ok=True)
    plots_dir.mkdir(parents=True, exist_ok=True)

    summary = build_summary_metrics(before, after)
    distribution = build_cluster_size_distribution({"before_ec": before, "after_ec": after})
    bin_summary = build_size_bin_summary(distribution)

    summary.to_csv(tables_dir / "cluster_summary_metrics.tsv", sep="\t", index=False)
    distribution.to_csv(tables_dir / "cluster_size_distribution.tsv", sep="\t", index=False)
    bin_summary.to_csv(tables_dir / "cluster_size_bin_summary.tsv", sep="\t", index=False)

    plot_paths = [
        plots_dir / "PANFAM_cluster_size_rank_distribution.png",
        plots_dir / "PANFAM_cluster_reduction_summary.png",
        plots_dir / "PANFAM_singleton_rates.png",
        plots_dir / "PANFAM_cluster_size_bins_combined.png",
        plots_dir / "PANFAM_cluster_size_distribution.png",
        plots_dir / "PANFAM_cluster_size_ecdf.png",
        plots_dir / "PANFAM_cluster_size_ccdf.png",
    ]
    plot_rank_distribution_from_distribution(distribution, plot_paths[0])
    plot_cluster_reduction_summary(summary, plot_paths[1])
    plot_singleton_rates(summary, plot_paths[2])
    plot_size_bins(bin_summary, plot_paths[3])
    plot_hist_distribution(distribution, plot_paths[4])
    plot_ecdf(distribution, plot_paths[5], ccdf=False)
    plot_ecdf(distribution, plot_paths[6], ccdf=True)
    return summary, distribution, plot_paths


def image_to_data_uri(path: Path) -> str:
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def write_multiqc_custom_content(summary: pd.DataFrame, plot_paths: list[Path], report_dir: Path) -> None:
    mqc_dir = report_dir / "custom_content"
    mqc_dir.mkdir(parents=True, exist_ok=True)
    after = summary[summary["section"] == "after_ec"]
    rows = []
    for _, row in after.iterrows():
        rows.append(
            "<tr>"
            f"<td>{html.escape(str(row['cluster_level']))}</td>"
            f"<td>{int(row['members']):,}</td>"
            f"<td>{int(row['clusters']):,}</td>"
            f"<td>{int(row['singletons']):,}</td>"
            f"<td>{float(row['avg_cluster_size']):.2f}</td>"
            f"<td>{int(row['max_cluster_size']):,}</td>"
            "</tr>"
        )
    multiqc_plot_paths = [path for path in plot_paths if path.name != "PANFAM_cluster_size_rank_distribution.png"]
    plot_titles = {
        "PANFAM_cluster_reduction_summary.png": "Cluster Counts and Representative Reduction",
        "PANFAM_singleton_rates.png": "Singleton Rates",
        "PANFAM_cluster_size_bins_combined.png": "Cluster Size Bins",
        "PANFAM_cluster_size_distribution.png": "Cluster Size Distribution",
        "PANFAM_cluster_size_ecdf.png": "Cluster Size ECDF",
        "PANFAM_cluster_size_ccdf.png": "Cluster Size CCDF",
    }
    plot_html = "\n".join(
        '<div style="width: 100%; margin: 1.6rem 0;">'
        f'<h4 style="font-size: 1.25rem; margin-bottom: 0.75rem; font-weight: 700;">'
        f'{html.escape(plot_titles.get(path.name, path.stem.replace("PANFAM_", "").replace("_", " ").title()))}</h4>'
        f'<img src="{image_to_data_uri(path)}" '
        'style="display: block; width: 100%; max-width: 1080px; height: auto; margin: 0 auto;" />'
        "</div>"
        for path in multiqc_plot_paths
        if path.exists()
    )
    html_body = f"""
<div style="width: 100%; max-width: 1700px; font-size: 1.05rem;">
  <h3 style="font-size: 1.45rem;">PANFAM clustering summary</h3>
  <div style="width: 100%; overflow-x: auto;">
    <table class="table table-striped" style="font-size: 1.02rem; min-width: 900px;">
      <thead>
        <tr><th>Level</th><th>Members</th><th>Clusters</th><th>Singletons</th><th>Average cluster size</th><th>Maximum cluster size</th></tr>
      </thead>
      <tbody>
        {''.join(rows)}
      </tbody>
    </table>
  </div>
  {plot_html}
</div>
""".strip()
    yaml_lines = [
        "id: panfam_clustering",
        "section_name: PANFAM Clustering",
        "description: PANFAM clustering summary statistics and cluster size plots.",
        "plot_type: html",
        "data: |",
    ]
    yaml_lines.extend(f"  {line}" for line in html_body.splitlines())
    (mqc_dir / "panfam_clustering_mqc.yaml").write_text("\n".join(yaml_lines) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    report_dir = args.report_dir or (args.out_dir / "multiqc")

    before: dict[str, pd.DataFrame] = {}
    after: dict[str, pd.DataFrame] = {}
    packaged: dict[str, pd.DataFrame] = {}

    for level in args.levels:
        corrected = args.clusters_dir / args.cluster_pattern.format(level=level)
        raw = args.clusters_dir / f"deepclust_{level}.tsv.gz"
        if not corrected.exists():
            raise FileNotFoundError(f"Corrected cluster table not found: {corrected}")
        after[level] = read_clusters(corrected)
        if not args.skip_report:
            if raw.exists():
                before[level] = read_clusters(raw)
            elif raw == corrected:
                before[level] = after[level]
            else:
                raise FileNotFoundError(
                    f"Raw cluster table required for before/after correction report not found: {raw}"
                )
        annotated, sizes = assign_cluster_ids(after[level], level, args.collection_release_id)
        packaged[level] = annotated
        write_representative_fasta(args.all_faa_gz, sizes, args.out_dir / "fasta" / f"PANFAM_{level}.faa.gz")

    pangenome_families = read_pangenome_families(args.pangenome_families)
    write_parquets(packaged, pangenome_families, args.out_dir, args.compression)
    if not args.skip_report:
        summary, _distribution, plot_paths = write_analysis_outputs(before, after, report_dir)
        write_minimal_report(summary, args.out_dir / "PANFAM_report.txt")
        write_multiqc_custom_content(summary, plot_paths, report_dir)


if __name__ == "__main__":
    main()
