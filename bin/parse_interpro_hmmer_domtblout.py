#!/usr/bin/env python3
"""Convert Pfam/NCBIFAM HMMER domtblout files to InterProScan-like TSV."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pfam-domtblout", type=Path)
    parser.add_argument("--ncbifam-domtblout", type=Path)
    parser.add_argument("--pfam-dat", type=Path)
    parser.add_argument("--ncbifam-hmm", type=Path)
    parser.add_argument("--entries-json", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    return parser.parse_args()


def clean(value: object) -> str:
    return "" if value is None else str(value).replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()


def parse_pfam_dat(path: Path | None) -> dict[str, dict[str, str]]:
    if path is None:
        return {}
    meta: dict[str, dict[str, str]] = {}
    acc = name = desc = None
    with path.open(errors="replace") as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith("#=GF ID"):
                name = line.split(maxsplit=2)[2]
            elif line.startswith("#=GF AC"):
                acc = line.split(maxsplit=2)[2].split(".")[0]
            elif line.startswith("#=GF DE"):
                desc = line.split(maxsplit=2)[2]
            elif line == "//":
                if acc:
                    meta[acc] = {"name": name or acc, "description": desc or ""}
                acc = name = desc = None
    return meta


def parse_hmm_metadata(path: Path | None) -> dict[str, dict[str, str]]:
    if path is None:
        return {}
    meta: dict[str, dict[str, str]] = {}
    acc = name = desc = None
    with path.open(errors="replace") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if line.startswith("NAME"):
                name = line.split(maxsplit=1)[1].strip()
            elif line.startswith("ACC"):
                acc = line.split(maxsplit=1)[1].strip().split(".")[0]
            elif line.startswith("DESC"):
                desc = line.split(maxsplit=1)[1].strip()
            elif line == "//":
                if acc:
                    meta[acc] = {"name": name or acc, "description": desc or ""}
                acc = name = desc = None
    return meta


def load_entries(path: Path) -> dict[str, dict[str, str]]:
    with path.open() as handle:
        data = json.load(handle)
    interpro_descriptions = {
        accession: entry.get("description") or entry.get("name") or ""
        for accession, entry in data.items()
        if isinstance(entry, dict) and str(entry.get("database", "")).lower() == "interpro"
    }
    out = {}
    for accession, entry in data.items():
        if not isinstance(entry, dict):
            continue
        integrated = entry.get("integrated")
        if integrated:
            out[accession.split(".")[0]] = {
                "interpro_accession": integrated,
                "interpro_description": interpro_descriptions.get(integrated, ""),
            }
        elif str(entry.get("database", "")).lower() == "interpro":
            out[accession] = {
                "interpro_accession": accession,
                "interpro_description": entry.get("description") or entry.get("name") or "",
            }
    return out


def parse_domtblout(path: Path, analysis: str, metadata: dict[str, dict[str, str]], entries: dict[str, dict[str, str]]):
    if path is None or not path.exists():
        return
    with path.open(errors="replace") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split(maxsplit=22)
            if len(fields) < 22:
                continue
            sequence_id = fields[0]
            model_name = fields[3]
            model_acc_raw = fields[4] if fields[4] != "-" else model_name
            seq_evalue = fields[6]
            seq_score = fields[7]
            domain_evalue = fields[12]
            domain_score = fields[13]
            hmm_from = fields[15]
            hmm_to = fields[16]
            ali_from = fields[17]
            ali_to = fields[18]
            description = fields[22] if len(fields) > 22 else ""

            model_acc = model_acc_raw.split(".")[0]
            model_meta = metadata.get(model_acc, {})
            entry = entries.get(model_acc, {})
            signature_desc = model_meta.get("description") or description
            interpro_acc = entry.get("interpro_accession", "")
            interpro_desc = entry.get("interpro_description", "")

            raw = ";".join(
                [
                    f"model={model_name}",
                    f"hmm_from={hmm_from}",
                    f"hmm_to={hmm_to}",
                    f"seq_evalue={seq_evalue}",
                    f"seq_score={seq_score}",
                    f"domain_score={domain_score}",
                ]
            )
            yield [
                sequence_id,
                "",
                "",
                analysis,
                model_acc,
                signature_desc,
                ali_from,
                ali_to,
                domain_evalue,
                "T",
                "",
                interpro_acc,
                interpro_desc,
                raw,
            ]


def main() -> None:
    args = parse_args()
    entries = load_entries(args.entries_json)
    pfam_meta = parse_pfam_dat(args.pfam_dat)
    ncbifam_meta = parse_hmm_metadata(args.ncbifam_hmm)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w") as handle:
        for row in parse_domtblout(args.pfam_domtblout, "Pfam", pfam_meta, entries) or []:
            print(*[clean(value) for value in row], sep="\t", file=handle)
        for row in parse_domtblout(args.ncbifam_domtblout, "NCBIFAM", ncbifam_meta, entries) or []:
            print(*[clean(value) for value in row], sep="\t", file=handle)


if __name__ == "__main__":
    main()
