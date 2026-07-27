#!/usr/bin/env python3
"""Convert annotation tool outputs to panAnnotator parquet deliverables."""

from __future__ import annotations

import argparse
import csv
import gzip
import re
from pathlib import Path

import pandas as pd


INTERPRO_TOOL_ALIASES = {
    "antifam": "antifam",
    "cdd": "cdd",
    "cathgene3d": "gene3d",
    "gene3d": "gene3d",
    "cathfunfam": "funfam",
    "funfam": "funfam",
    "coils": "coils",
    "deeptmhmm": "deeptmhmm",
    "hamap": "hamap",
    "interpron": "interpro_n",
    "mobidblite": "mobidblite",
    "ncbifam": "ncbifam",
    "panther": "panther",
    "pfam": "pfam",
    "phobius": "phobius",
    "pirsf": "pirsf",
    "pirsr": "pirsr",
    "prints": "prints",
    "prositepatterns": "prositepatterns",
    "prositeprofiles": "prositeprofiles",
    "sfld": "sfld",
    "signalp": "signalp",
    "signalpeuk": "signalp_euk",
    "signalpprok": "signalp_prok",
    "smart": "smart",
    "superfamily": "superfamily",
    "tmbed": "tmbed",
}

INTERPRO_ANALYSIS_ALIASES = {
    "cathgene3d": "gene3d",
    "cathfunfam": "funfam",
    "gene3d": "gene3d",
    "funfam": "funfam",
    "interpron": "interpro_n",
    "signalpeuk": "signalp",
    "signalpprok": "signalp",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tool", required=True)
    parser.add_argument("--input-mode", required=True, choices=["panfam_80", "all_proteins"])
    parser.add_argument("--raw", type=Path, nargs="+", required=True)
    parser.add_argument("--panfam-80", type=Path, required=True)
    parser.add_argument("--pangenome-families", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--compression", default="zstd")
    return parser.parse_args()


def clean(value: object) -> str:
    if value is None:
        return ""
    return str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()


def open_text(path: Path):
    return gzip.open(path, "rt", newline="") if path.suffix == ".gz" else path.open(newline="")


def parse_int(value: object) -> int | None:
    text = clean(value)
    if not text:
        return None
    try:
        return int(float(text))
    except ValueError:
        return None


def extract_raw_position(value: object, key: str) -> int | None:
    match = re.search(rf"(?:^|;){re.escape(key)}=([^;]+)", clean(value))
    return parse_int(match.group(1)) if match else None


def final_annotation_columns(tool: str) -> list[str]:
    if tool == "eggnog":
        return ["Query_id", "eggNOG_OGs", "Match_start", "Match_end", "Raw_order"]
    return ["Query_id", "Annotation_id", "Match_start", "Match_end", "Raw_order"]


def normalize_annotation_frame(df: pd.DataFrame, tool: str) -> pd.DataFrame:
    columns = final_annotation_columns(tool)
    for col in columns:
        if col not in df.columns:
            df[col] = None if col in {"Match_start", "Match_end", "Raw_order"} else ""
    return df[columns]


def read_generic_tsv(paths: list[Path], tool: str) -> pd.DataFrame:
    frames = []
    raw_order = 0
    for path in paths:
        df = pd.read_csv(path, sep="\t", dtype=str, compression="infer")
        rename = {
            "protein_id": "Query_id",
            "annotation_id": "Annotation_id",
            "start": "Match_start",
            "Start": "Match_start",
            "end": "Match_end",
            "End": "Match_end",
            "stop": "Match_end",
            "Stop": "Match_end",
        }
        df = df.rename(columns=rename)
        for col in ["Query_id", "Annotation_id"]:
            if col not in df.columns:
                df[col] = ""
        if "Match_start" not in df.columns and "raw_annotation" in df.columns:
            df["Match_start"] = df["raw_annotation"].map(lambda value: extract_raw_position(value, "start"))
        if "Match_end" not in df.columns and "raw_annotation" in df.columns:
            df["Match_end"] = df["raw_annotation"].map(lambda value: extract_raw_position(value, "end"))
        df["Raw_order"] = range(raw_order, raw_order + len(df))
        raw_order += len(df)
        frames.append(normalize_annotation_frame(df, tool))
    return pd.concat(frames, ignore_index=True) if frames else empty_annotations(tool)


def read_eggnog(paths: list[Path]) -> pd.DataFrame:
    frames = []
    raw_order = 0
    for path in paths:
        df = pd.read_csv(path, sep="\t", dtype=str, compression="infer")
        df = df.rename(columns={"protein_id": "Query_id"})
        for col in ["Query_id", "eggNOG_OGs"]:
            if col not in df.columns:
                df[col] = ""
        df["Raw_order"] = range(raw_order, raw_order + len(df))
        raw_order += len(df)
        frames.append(normalize_annotation_frame(df, "eggnog"))
    return pd.concat(frames, ignore_index=True) if frames else empty_annotations("eggnog")


def read_interpro(paths: list[Path], tool: str) -> pd.DataFrame:
    analysis_filter = None if tool == "interpro" else canonical_interpro_analysis(tool)
    rows = []
    raw_order = 0
    for path in paths:
        with open_text(path) as handle:
            reader = csv.reader(handle, delimiter="\t")
            for row in reader:
                if not row or row[0].startswith("#"):
                    continue
                analysis = canonical_interpro_analysis(row[3] if len(row) > 3 else "")
                if analysis_filter and analysis != analysis_filter:
                    continue
                rows.append(
                    {
                        "Query_id": clean(row[0] if len(row) > 0 else ""),
                        "Annotation_id": clean(row[4] if len(row) > 4 else ""),
                        "Match_start": parse_int(row[6] if len(row) > 6 else None),
                        "Match_end": parse_int(row[7] if len(row) > 7 else None),
                        "Raw_order": raw_order,
                    }
                )
                raw_order += 1
    return pd.DataFrame(rows) if rows else empty_annotations("interpro")


def normalize_tool_name(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", clean(value).lower())


def canonical_interpro_tool(value: object) -> str:
    normalized = normalize_tool_name(value)
    return INTERPRO_TOOL_ALIASES.get(normalized, normalized)


def canonical_interpro_analysis(value: object) -> str:
    normalized = normalize_tool_name(value)
    return INTERPRO_ANALYSIS_ALIASES.get(normalized, normalized)


def read_amrfinder(paths: list[Path]) -> pd.DataFrame:
    rows = []
    raw_order = 0
    for path in paths:
        with open_text(path) as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            for row in reader:
                query = row.get("Protein identifier") or row.get("Protein id") or row.get("protein_id") or row.get("Name")
                annot = row.get("Element symbol") or row.get("Gene symbol") or row.get("Element name") or row.get("HMM id")
                start = row.get("Start") or row.get("Protein start") or row.get("start")
                stop = row.get("Stop") or row.get("End") or row.get("Protein stop") or row.get("end")
                rows.append(
                    {
                        "Query_id": clean(query),
                        "Annotation_id": clean(annot),
                        "Match_start": parse_int(start),
                        "Match_end": parse_int(stop),
                        "Raw_order": raw_order,
                    }
                )
                raw_order += 1
    return pd.DataFrame(rows) if rows else empty_annotations("amrfinder")


def empty_annotations(tool: str) -> pd.DataFrame:
    if tool == "eggnog":
        return pd.DataFrame(columns=["Query_id", "eggNOG_OGs", "Match_start", "Match_end", "Raw_order"])
    return pd.DataFrame(columns=["Query_id", "Annotation_id", "Match_start", "Match_end", "Raw_order"])


def load_mapping(input_mode: str, panfam_80: Path, pangenome_families: Path) -> pd.DataFrame:
    if input_mode == "panfam_80":
        df = pd.read_parquet(panfam_80)
        required = ["Pangenome_id", "Pangenome_family_id", "Cluster_id"]
        missing = [col for col in required if col not in df.columns]
        if missing:
            raise ValueError(f"{panfam_80} missing columns: {', '.join(missing)}")
        return df[required].drop_duplicates().rename(columns={"Cluster_id": "Query_id"})

    df = pd.read_csv(pangenome_families, sep="\t", dtype={"Pangenome_family_id": str})
    required = ["Pangenome_id", "Pangenome_family_id"]
    missing = [col for col in required if col not in df.columns]
    if missing:
        raise ValueError(f"{pangenome_families} missing columns: {', '.join(missing)}")
    df["Query_id"] = df["Pangenome_family_id"]
    return df[["Pangenome_id", "Pangenome_family_id", "Query_id"]].drop_duplicates()


def read_annotations(tool: str, raw: list[Path]) -> pd.DataFrame:
    if tool in {
        "antifam",
        "cdd",
        "cathgene3d",
        "cathfunfam",
        "coils",
        "funfam",
        "gene3d",
        "hamap",
        "interpro",
        "interpro_n",
        "mobidblite",
        "ncbifam",
        "panther",
        "pfam",
        "phobius",
        "pirsf",
        "pirsr",
        "prints",
        "prositepatterns",
        "prositeprofiles",
        "sfld",
        "signalp",
        "signalp_euk",
        "signalp_prok",
        "smart",
        "superfamily",
        "tigrfam",
        "tmbed",
    }:
        return read_interpro(raw, tool)
    if tool == "amrfinder":
        return read_amrfinder(raw)
    if tool == "eggnog":
        return read_eggnog(raw)
    return read_generic_tsv(raw, tool)


def main() -> None:
    args = parse_args()
    args.tool = canonical_interpro_tool(args.tool)
    annotations = read_annotations(args.tool, args.raw)
    annotations = normalize_annotation_frame(annotations, args.tool)
    annotations = annotations[annotations["Query_id"].astype(str).str.len() > 0].copy()
    if args.tool == "eggnog":
        annotations = annotations[annotations["eggNOG_OGs"].astype(str).str.len() > 0].copy()
        annotations = annotations[~annotations["eggNOG_OGs"].isin(["-", "NA", "nan"])].copy()
        output_columns = ["Pangenome_id", "Pangenome_family_id", "eggNOG_OGs"]
    else:
        annotations = annotations[annotations["Annotation_id"].astype(str).str.len() > 0].copy()
        annotations = annotations[~annotations["Annotation_id"].isin(["-", "NA", "nan"])].copy()
        output_columns = ["Pangenome_id", "Pangenome_family_id", "Annotation_id"]

    mapping = load_mapping(args.input_mode, args.panfam_80, args.pangenome_families)
    mapping = mapping.reset_index(drop=True)
    mapping["Mapping_order"] = range(len(mapping))
    out = mapping.merge(annotations, on="Query_id", how="inner")
    for col in ["Match_start", "Match_end", "Raw_order", "Mapping_order"]:
        out[col] = pd.to_numeric(out[col], errors="coerce")
    out = out.sort_values(
        ["Pangenome_id", "Pangenome_family_id", "Query_id", "Match_start", "Match_end", "Raw_order", "Mapping_order"],
        kind="mergesort",
        na_position="last",
    )
    dedupe_columns = output_columns + ["Query_id", "Match_start", "Match_end"]
    out = out.drop_duplicates(subset=dedupe_columns, keep="first")
    out = out.drop(columns=["Query_id", "Match_start", "Match_end", "Raw_order", "Mapping_order"])

    args.out_dir.mkdir(parents=True, exist_ok=True)
    pangenome_dir = args.out_dir / "pangenomes"
    pangenome_dir.mkdir(parents=True, exist_ok=True)

    out = out[output_columns]
    out.to_parquet(args.out_dir / f"{args.tool}.parquet", index=False, compression=args.compression)
    for pangenome_id, df in out.groupby("Pangenome_id", sort=True):
        df.drop(columns=["Pangenome_id"]).to_parquet(
            pangenome_dir / f"{args.tool}_p{int(pangenome_id)}.parquet",
            index=False,
            compression=args.compression,
        )


if __name__ == "__main__":
    main()
