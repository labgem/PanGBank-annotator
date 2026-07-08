#!/usr/bin/env python3
"""Create PANFAM cluster deliverables from corrected DIAMOND cluster tables."""

from __future__ import annotations

import argparse
import gzip
import os
import statistics
from collections import Counter
from pathlib import Path

import pandas as pd


LEVELS = ("deep", "50", "80")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clusters-dir", type=Path, required=True)
    parser.add_argument("--cluster-pattern", default="corrected_{level}.tsv")
    parser.add_argument("--all-faa-gz", type=Path, required=True)
    parser.add_argument("--pangenome-families", type=Path, required=True)
    parser.add_argument("--collection-release-id", required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
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
            for i in range(0, len(seq), 80):
                out.write(seq[i : i + 80] + "\n")
            remaining.discard(seq_id)
    if remaining:
        missing = ", ".join(sorted(remaining)[:10])
        raise RuntimeError(f"{len(remaining)} representatives were absent from FASTA; first missing: {missing}")


def read_pangenome_families(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t", dtype=str)
    required = {"Pangenome_id", "Pangenome_family_id"}
    if not required.issubset(df.columns):
        raise ValueError(f"{path} must contain columns {sorted(required)}")
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
        out = per_pangenome_dir / f"PANFAM_{pangenome_id}.parquet"
        df[["Pangenome_family_id", "Cluster_level", "Cluster_id"]].to_parquet(
            out, index=False, compression=compression
        )


def report_lines(before: dict[str, pd.DataFrame], after: dict[str, pd.DataFrame]) -> list[str]:
    lines = ["section\tcluster_level\tmetric\tvalue"]
    for section, tables in (("before_ec", before), ("after_ec", after)):
        for level, df in tables.items():
            sizes = df.groupby("centroid").size().tolist()
            counts = Counter(sizes)
            lines.append(f"{section}\t{level}\tmembers\t{len(df)}")
            lines.append(f"{section}\t{level}\tclusters\t{len(sizes)}")
            lines.append(f"{section}\t{level}\tsingletons\t{counts.get(1, 0)}")
            avg = statistics.mean(sizes) if sizes else 0
            lines.append(f"{section}\t{level}\tavg_cluster_size\t{avg:.6f}")
            for size in sorted(counts):
                lines.append(f"{section}\t{level}\tcluster_size_{size}\t{counts[size]}")
    return lines


def cluster_size_counts(df: pd.DataFrame) -> Counter:
    return Counter(df.groupby("centroid").size().tolist())


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


def plot_cluster_size_distribution(
    before: dict[str, pd.DataFrame],
    after: dict[str, pd.DataFrame],
    out_path: Path,
) -> None:
    os.environ.setdefault("XDG_CACHE_HOME", str(out_path.parent / ".cache"))
    os.environ.setdefault("MPLCONFIGDIR", str(out_path.parent / ".matplotlib"))
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    levels = list(after)
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

    level_colors = {"deep": "#7c3aed", "50": "#0891b2", "80": "#ea580c"}
    for ax, level in zip(axes, levels):
        plotted = False
        level_color = level_colors.get(level, "#2563eb")
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
                label=label,
            )
            plotted = True

        after_counts = cluster_size_counts(after[level])
        singleton_count = after_counts.get(1, 0)
        cluster_count = sum(after_counts.values())
        ax.set_title(
            f"Cluster level {level}: {cluster_count:,} clusters, {singleton_count:,} singletons after correction",
            loc="left",
            fontsize=11,
            fontweight="bold",
        )
        ax.set_ylabel("Cluster size")
        ax.spines[["top", "right"]].set_visible(False)
        if plotted:
            ax.set_xscale("log")
            ax.set_yscale("log")
            ax.legend(frameon=False, loc="upper right")

    axes[-1].set_xlabel("Cluster rank, largest to smallest")
    fig.suptitle("PANFAM Cluster Size Rank Distribution", fontsize=15, fontweight="bold")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=180)
    plt.close(fig)


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    before: dict[str, pd.DataFrame] = {}
    after: dict[str, pd.DataFrame] = {}
    packaged: dict[str, pd.DataFrame] = {}

    for level in args.levels:
        corrected = args.clusters_dir / args.cluster_pattern.format(level=level)
        raw = args.clusters_dir / f"deepclust_{level}.tsv"
        if not corrected.exists():
            raise FileNotFoundError(f"Corrected cluster table not found: {corrected}")
        after[level] = read_clusters(corrected)
        before[level] = read_clusters(raw) if raw.exists() else after[level]
        annotated, sizes = assign_cluster_ids(after[level], level, args.collection_release_id)
        packaged[level] = annotated
        write_representative_fasta(args.all_faa_gz, sizes, args.out_dir / "fasta" / f"PANFAM_{level}.faa.gz")

    pangenome_families = read_pangenome_families(args.pangenome_families)
    write_parquets(packaged, pangenome_families, args.out_dir, args.compression)
    (args.out_dir / "PANFAM_report.txt").write_text("\n".join(report_lines(before, after)) + "\n")
    plot_cluster_size_distribution(
        before,
        after,
        args.out_dir / "plots" / "PANFAM_cluster_size_distribution.png",
    )


if __name__ == "__main__":
    main()
