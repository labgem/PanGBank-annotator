#!/usr/bin/env python3
"""Create annotation summary tables, plots, and MultiQC custom content."""

from __future__ import annotations

import argparse
import base64
import html
import os
import tempfile
from collections import Counter
from pathlib import Path

import pandas as pd


TOOL_LABELS = {
    "pfam": "Pfam",
    "ncbifam": "NCBIfam",
    "deepkoala": "DeepKOALA",
    "eggnog": "eggNOG root OGs",
    "amrfinder": "AMRFinder+",
}
TOOL_COLORS = {
    "pfam": "#5B7FB2",
    "ncbifam": "#6DA36F",
    "deepkoala": "#C77C59",
    "eggnog": "#8A6BBE",
    "amrfinder": "#C45C5C",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parquets", type=Path, nargs="+", required=True)
    parser.add_argument("--pangenome-families", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--compression", default="zstd")
    return parser.parse_args()


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
            "axes.titlesize": 9.5,
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


def tool_from_path(path: Path) -> str:
    return path.stem.lower()


def normalize_eggnog_terms(value: object) -> list[str]:
    text = "" if value is None else str(value).strip()
    if not text or text in {"-", "NA", "nan"}:
        return []
    out = []
    for term in text.split(","):
        term = term.strip()
        if not term:
            continue
        # Use the root OG to match the previous OG_root_only reports.
        out.append(term.split("@", 1)[0])
    return out


def read_annotation_table(path: Path) -> pd.DataFrame:
    tool = tool_from_path(path)
    df = pd.read_parquet(path)
    required = {"Pangenome_id", "Pangenome_family_id"}
    missing = sorted(required - set(df.columns))
    if missing:
        raise ValueError(f"{path} missing columns: {', '.join(missing)}")

    if "eggNOG_OGs" in df.columns:
        term_col = "eggNOG_OGs"
        rows = []
        for protein_id, value in zip(df["Pangenome_family_id"], df[term_col]):
            for term in normalize_eggnog_terms(value):
                rows.append((protein_id, term))
        terms = pd.DataFrame(rows, columns=["Pangenome_family_id", "Annotation_id"])
    elif "Annotation_id" in df.columns:
        terms = df[["Pangenome_family_id", "Annotation_id"]].copy()
    else:
        raise ValueError(f"{path} must contain Annotation_id or eggNOG_OGs")

    terms["Annotation_id"] = terms["Annotation_id"].astype(str).str.strip()
    terms = terms[
        terms["Pangenome_family_id"].astype(str).str.len().gt(0)
        & terms["Annotation_id"].astype(str).str.len().gt(0)
        & ~terms["Annotation_id"].isin(["-", "NA", "nan"])
    ].copy()
    terms["tool"] = tool
    return terms[["tool", "Pangenome_family_id", "Annotation_id"]]


def load_total_proteins(path: Path) -> int:
    df = pd.read_csv(path, sep="\t", dtype={"Pangenome_family_id": str})
    if "Pangenome_family_id" not in df.columns:
        raise ValueError(f"{path} missing Pangenome_family_id")
    return int(df["Pangenome_family_id"].dropna().nunique())


def sort_tools(tools: list[str]) -> list[str]:
    return sorted(dict.fromkeys(tools), key=lambda x: list(TOOL_LABELS).index(x) if x in TOOL_LABELS else 99)


def build_tables(annotations: pd.DataFrame, total_proteins: int, tools: list[str]) -> dict[str, pd.DataFrame]:
    tools = sort_tools(tools)

    coverage_rows = []
    redundancy_rows = []
    vocab_rows = []
    top_rows = []
    protein_tool_sets: dict[str, set[str]] = {}

    for tool in tools:
        sub = annotations[annotations["tool"] == tool]
        counts = sub.groupby("Pangenome_family_id").size()
        n_with = int(counts.size)
        hist = Counter(int(value) for value in counts.tolist())
        term_counts = sub["Annotation_id"].value_counts()
        total_mentions = int(term_counts.sum())
        coverage_rows.append(
            {
                "tool": tool,
                "tool_display": TOOL_LABELS.get(tool, tool),
                "n_with_annotations": n_with,
                "total_proteins": total_proteins,
                "coverage": n_with / total_proteins if total_proteins else 0,
                "mean_annotations_per_protein": float(counts.mean()) if n_with else 0,
                "median_annotations": float(counts.median()) if n_with else 0,
                "min_annotations": int(counts.min()) if n_with else 0,
                "max_annotations": int(counts.max()) if n_with else 0,
            }
        )
        for n_annotations, protein_count in sorted(hist.items()):
            redundancy_rows.append(
                {
                    "tool": tool,
                    "tool_display": TOOL_LABELS.get(tool, tool),
                    "n_annotations": n_annotations,
                    "protein_count": protein_count,
                    "fraction_annotated_proteins": protein_count / n_with if n_with else 0,
                    "fraction_all_proteins": protein_count / total_proteins if total_proteins else 0,
                    "total_proteins": total_proteins,
                }
            )
        vocab_rows.append(
            {
                "tool": tool,
                "tool_display": TOOL_LABELS.get(tool, tool),
                "vocab_size": int(term_counts.size),
                "total_mentions": total_mentions,
            }
        )
        for top_k in (10, 100):
            top_mentions = int(term_counts.head(top_k).sum())
            top_rows.append(
                {
                    "tool": tool,
                    "tool_display": TOOL_LABELS.get(tool, tool),
                    "top_k": top_k,
                    "top_mentions": top_mentions,
                    "total_mentions": total_mentions,
                    "fraction_mentions": top_mentions / total_mentions if total_mentions else 0,
                }
            )
        protein_tool_sets[tool] = set(sub["Pangenome_family_id"].drop_duplicates())

    co_rows = []
    for tool in tools:
        for other in tools:
            count = len(protein_tool_sets[tool] & protein_tool_sets[other])
            co_rows.append(
                {
                    "tool": tool,
                    "tool_display": TOOL_LABELS.get(tool, tool),
                    "other_tool": other,
                    "other_tool_display": TOOL_LABELS.get(other, other),
                    "protein_count": count,
                    "fraction_all_proteins": count / total_proteins if total_proteins else 0,
                    "total_proteins": total_proteins,
                }
            )

    by_protein = annotations[["Pangenome_family_id", "tool"]].drop_duplicates()
    tool_counts = by_protein.groupby("Pangenome_family_id").size()
    count_hist = Counter(int(value) for value in tool_counts.tolist())
    zero_count = total_proteins - int(tool_counts.size)
    tool_count_rows = [
        {
            "n_tools": 0,
            "protein_count": zero_count,
            "fraction_all_proteins": zero_count / total_proteins if total_proteins else 0,
            "total_proteins": total_proteins,
        }
    ]
    for n_tools, protein_count in sorted(count_hist.items()):
        tool_count_rows.append(
            {
                "n_tools": n_tools,
                "protein_count": protein_count,
                "fraction_all_proteins": protein_count / total_proteins if total_proteins else 0,
                "total_proteins": total_proteins,
            }
        )

    return {
        "coverage_summary": pd.DataFrame(coverage_rows),
        "annotation_count_distribution": pd.DataFrame(redundancy_rows),
        "vocabulary_size": pd.DataFrame(vocab_rows),
        "top_term_coverage": pd.DataFrame(top_rows),
        "tool_co_coverage": pd.DataFrame(co_rows),
        "tool_count_distribution": pd.DataFrame(tool_count_rows),
    }


def plot_coverage(df: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()
    df = df.sort_values("coverage", ascending=False)
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    bars = ax.bar(
        df["tool_display"],
        df["coverage"],
        color=[TOOL_COLORS.get(tool, "#777777") for tool in df["tool"]],
        edgecolor="white",
        linewidth=1,
    )
    ax.set_ylabel("Fraction of proteins")
    ax.set_title("Annotation coverage by tool")
    ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0))
    ax.set_ylim(0, min(1.0, max(df["coverage"].max() * 1.18, 0.05)))
    ax.tick_params(axis="x", rotation=28)
    clean_axes(ax)
    for bar, value in zip(bars, df["coverage"]):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.01, f"{value:.1%}", ha="center", va="bottom", fontsize=8)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_count_distribution(df: pd.DataFrame, out_path: Path) -> None:
    plt, _ticker = configure_matplotlib()
    fig, ax = plt.subplots(figsize=(7.5, 4.6))
    for tool, sub in df.groupby("tool", sort=False):
        sub = sub.sort_values("n_annotations")
        ax.step(
            sub["n_annotations"],
            sub["protein_count"],
            where="mid",
            linewidth=2,
            color=TOOL_COLORS.get(tool, "#777777"),
            label=TOOL_LABELS.get(tool, tool),
        )
    ax.set_xlabel("Annotations per protein")
    ax.set_ylabel("Number of proteins")
    ax.set_title("Annotation count distribution")
    ax.set_yscale("log")
    ax.legend(frameon=False, loc="upper right")
    clean_axes(ax)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_vocab(df: pd.DataFrame, out_path: Path) -> None:
    plt, _ticker = configure_matplotlib()
    df = df.sort_values("vocab_size", ascending=False)
    fig, ax = plt.subplots(figsize=(7.2, 4.4))
    bars = ax.bar(
        df["tool_display"],
        df["vocab_size"],
        color=[TOOL_COLORS.get(tool, "#777777") for tool in df["tool"]],
        edgecolor="white",
        linewidth=1,
    )
    ax.set_ylabel("Unique annotation terms")
    ax.set_title("Vocabulary size across annotation tools")
    ax.tick_params(axis="x", rotation=28)
    clean_axes(ax)
    for bar, value in zip(bars, df["vocab_size"]):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height(), f"{int(value):,}", ha="center", va="bottom", fontsize=8)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_top_terms(df: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()
    import numpy as np

    tools = sort_tools(df["tool"].drop_duplicates().tolist())
    x = np.arange(len(tools))
    width = 0.34
    fig, ax = plt.subplots(figsize=(8.0, 4.6))
    for offset, top_k, label in ((-width / 2, 10, "Top 10"), (width / 2, 100, "Top 100")):
        sub = df[df["top_k"] == top_k].set_index("tool").reindex(tools)
        bars = ax.bar(
            x + offset,
            sub["fraction_mentions"],
            width=width,
            color=[TOOL_COLORS.get(tool, "#777777") for tool in tools],
            alpha=0.7 if top_k == 10 else 1.0,
            edgecolor="white",
            linewidth=1,
            label=label,
        )
        for bar, value in zip(bars, sub["fraction_mentions"]):
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.006, f"{value:.1%}", ha="center", va="bottom", rotation=90, fontsize=7)
    ax.set_xticks(x)
    ax.set_xticklabels([TOOL_LABELS.get(tool, tool) for tool in tools], rotation=28, ha="right")
    ax.set_ylabel("Fraction of annotation mentions")
    ax.set_title("Top annotation term concentration")
    ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0))
    ax.legend(frameon=False, loc="upper left")
    clean_axes(ax)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_heatmap(df: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()
    tools = list(df["tool"].drop_duplicates())
    matrix = (
        df.pivot(index="tool", columns="other_tool", values="fraction_all_proteins")
        .reindex(index=tools, columns=tools)
        .fillna(0)
    )
    fig, ax = plt.subplots(figsize=(6.0, 5.2))
    im = ax.imshow(matrix.values, cmap="YlGnBu", vmin=0, vmax=max(float(matrix.values.max()), 0.01))
    ax.set_xticks(range(len(tools)))
    ax.set_yticks(range(len(tools)))
    ax.set_xticklabels([TOOL_LABELS.get(tool, tool) for tool in tools], rotation=35, ha="right")
    ax.set_yticklabels([TOOL_LABELS.get(tool, tool) for tool in tools])
    ax.set_title("Tool co-coverage")
    for i in range(len(tools)):
        for j in range(len(tools)):
            ax.text(j, i, f"{matrix.iloc[i, j]:.1%}", ha="center", va="center", fontsize=7, color="#111111")
    cbar = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    cbar.ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0))
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def plot_tool_counts(df: pd.DataFrame, out_path: Path) -> None:
    plt, ticker = configure_matplotlib()
    fig, ax = plt.subplots(figsize=(7.0, 4.4))
    bars = ax.bar(df["n_tools"].astype(str), df["fraction_all_proteins"], color="#5B7FB2", edgecolor="white", linewidth=1)
    ax.set_xlabel("Number of annotation tools")
    ax.set_ylabel("Fraction of proteins")
    ax.set_title("Number of tools annotating each protein")
    ax.yaxis.set_major_formatter(ticker.PercentFormatter(1.0))
    clean_axes(ax)
    for bar, value in zip(bars, df["fraction_all_proteins"]):
        if value > 0:
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.006, f"{value:.1%}", ha="center", va="bottom", fontsize=8)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def image_to_data_uri(path: Path) -> str:
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:image/png;base64,{encoded}"


def write_multiqc(tables: dict[str, pd.DataFrame], plot_paths: list[Path], out_dir: Path) -> None:
    mqc_dir = out_dir / "custom_content"
    mqc_dir.mkdir(parents=True, exist_ok=True)
    coverage = tables["coverage_summary"].sort_values("coverage", ascending=False)
    rows = []
    for _, row in coverage.iterrows():
        rows.append(
            "<tr>"
            f"<td>{html.escape(str(row['tool_display']))}</td>"
            f"<td>{int(row['n_with_annotations']):,}</td>"
            f"<td>{float(row['coverage']):.2%}</td>"
            f"<td>{float(row['mean_annotations_per_protein']):.2f}</td>"
            f"<td>{int(row['max_annotations']):,}</td>"
            "</tr>"
        )
    plot_titles = {
        "annotation_coverage.png": "Annotation Coverage",
        "annotation_count_distribution.png": "Annotation Count Distribution",
        "annotation_tool_co_coverage_heatmap.png": "Tool Co-Coverage",
        "annotation_number_of_tools_per_protein.png": "Number of Tools per Protein",
        "annotation_vocabulary_size.png": "Vocabulary Size",
        "annotation_top_term_coverage.png": "Top Term Concentration",
    }
    plot_html = "\n".join(
        '<div style="width: 100%; margin: 1.6rem 0;">'
        f'<h4 style="font-size: 1.25rem; margin-bottom: 0.75rem; font-weight: 700;">{html.escape(plot_titles.get(path.name, path.stem))}</h4>'
        f'<img src="{image_to_data_uri(path)}" style="display: block; width: 100%; max-width: 1080px; height: auto; margin: 0 auto;" />'
        "</div>"
        for path in plot_paths
        if path.exists()
    )
    html_body = f"""
<div style="width: 100%; max-width: 1700px; font-size: 1.05rem;">
  <h3 style="font-size: 1.45rem;">PANFAM annotation summary</h3>
  <div style="width: 100%; overflow-x: auto;">
    <table class="table table-striped" style="font-size: 1.02rem; min-width: 800px;">
      <thead>
        <tr><th>Tool</th><th>Annotated proteins</th><th>Coverage</th><th>Mean annotations/protein</th><th>Max annotations/protein</th></tr>
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
        "id: panfam_annotation",
        "section_name: PANFAM Annotation",
        "description: PANFAM annotation coverage, redundancy, and vocabulary summaries.",
        "plot_type: html",
        "data: |",
    ]
    yaml_lines.extend(f"  {line}" for line in html_body.splitlines())
    (mqc_dir / "panfam_annotation_mqc.yaml").write_text("\n".join(yaml_lines) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    tables_dir = args.out_dir / "tables"
    plots_dir = args.out_dir / "plots"
    tables_dir.mkdir(parents=True, exist_ok=True)
    plots_dir.mkdir(parents=True, exist_ok=True)

    total_proteins = load_total_proteins(args.pangenome_families)
    tools = [tool_from_path(path) for path in args.parquets]
    frames = [read_annotation_table(path) for path in args.parquets]
    annotations = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame(columns=["tool", "Pangenome_family_id", "Annotation_id"])
    annotations = annotations.drop_duplicates()

    tables = build_tables(annotations, total_proteins, tools)
    for name, df in tables.items():
        df.to_csv(tables_dir / f"{name}.tsv", sep="\t", index=False)

    plot_paths = [
        plots_dir / "annotation_coverage.png",
        plots_dir / "annotation_count_distribution.png",
        plots_dir / "annotation_tool_co_coverage_heatmap.png",
        plots_dir / "annotation_number_of_tools_per_protein.png",
        plots_dir / "annotation_vocabulary_size.png",
        plots_dir / "annotation_top_term_coverage.png",
    ]
    plot_coverage(tables["coverage_summary"], plot_paths[0])
    plot_count_distribution(tables["annotation_count_distribution"], plot_paths[1])
    plot_heatmap(tables["tool_co_coverage"], plot_paths[2])
    plot_tool_counts(tables["tool_count_distribution"], plot_paths[3])
    plot_vocab(tables["vocabulary_size"], plot_paths[4])
    plot_top_terms(tables["top_term_coverage"], plot_paths[5])
    write_multiqc(tables, plot_paths, args.out_dir)


if __name__ == "__main__":
    main()
