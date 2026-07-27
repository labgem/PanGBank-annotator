#!/usr/bin/env python3
"""Validate annotation database paths used by panAnnotator."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request


INTERPRO_APP_DIRS = {
    "antifam": "antifam",
    "cath": "cath",
    "cdd": "cdd",
    "hamap": "hamap",
    "ncbifam": "ncbifam",
    "panther": "panther",
    "pfam": "pfam",
    "pirsf": "pirsf",
    "pirsr": "pirsr",
    "prints": "prints",
    "prositepatterns": "prosite",
    "prositeprofiles": "prosite",
    "sfld": "sfld",
    "smart": "smart",
    "superfamily": "superfamily",
}

INTERPRO_APPS_WITH_DATA = {
    "antifam": ("antifam", ""),
    "cathgene3d": ("cath", "gene3d"),
    "cathfunfam": ("cath", "funfam"),
    "cdd": ("cdd", ""),
    "hamap": ("hamap", ""),
    "ncbifam": ("ncbifam", ""),
    "panther": ("panther", ""),
    "pfam": ("pfam", ""),
    "pirsf": ("pirsf", ""),
    "pirsr": ("pirsr", ""),
    "prints": ("prints", ""),
    "prositepatterns": ("prosite", ""),
    "prositeprofiles": ("prosite", ""),
    "sfld": ("sfld", ""),
    "smart": ("smart", ""),
    "superfamily": ("superfamily", ""),
}

INTERPRO_DOWNLOAD_BASE = "https://ftp.ebi.ac.uk/pub/software/unix/iprscan/6"
DEEPKOALA_BASE = "https://www.genome.jp/ftp/db/deepkoala"
DEEPKOALA_PAGE = "https://www.genome.jp/tools/deepkoala/"
DEEPKOALA_SHARED_FILES = ["evaluation.csv"]
DEEPKOALA_MODEL_FILES = {
    "full": ["ko_config_full.json", "weights_full.pt"],
    "frag": ["ko_config_frag.json", "weights_frag.pt"],
    "fragment": ["ko_config_frag.json", "weights_frag.pt"],
}


def split_csv(value: str) -> list[str]:
    return [item.strip().lower() for item in str(value).split(",") if item.strip() and item.strip().lower() != "none"]


def q(value: object) -> str:
    text = str(value).replace('"', '\\"')
    return f'"{text}"'


def newest_subdir(path: Path) -> str | None:
    if not path.is_dir():
        return None
    children = sorted([p.name for p in path.iterdir() if p.is_dir()])
    return children[-1] if children else None


def deepkoala_required_files(model: str) -> list[str]:
    key = model.lower()
    if key not in DEEPKOALA_MODEL_FILES:
        raise ValueError(f"Unsupported DeepKOALA model for database preparation: {model}")
    return DEEPKOALA_SHARED_FILES + DEEPKOALA_MODEL_FILES[key]


def newest_complete_deepkoala_model(path: Path, model: str) -> str | None:
    required = deepkoala_required_files(model)
    if not path.is_dir():
        return None
    for child in sorted([p for p in path.iterdir() if p.is_dir()], reverse=True):
        if all((child / filename).exists() for filename in required):
            return child.name
    return None


def resolve_amrfinder_db(path: str | Path) -> Path:
    db_dir = Path(path)
    if (db_dir / "AMRProt.fa.phr").exists():
        return db_dir
    latest = db_dir / "latest"
    if (latest / "AMRProt.fa.phr").exists():
        return latest
    return db_dir


def fetch_deepkoala_current_version() -> str | None:
    try:
        with urllib.request.urlopen(DEEPKOALA_PAGE, timeout=30) as response:
            html = response.read().decode("utf-8", errors="replace")
    except Exception:
        return None
    match = re.search(r"Current database version.*?([0-9]{6})", html, flags=re.IGNORECASE | re.DOTALL)
    return match.group(1) if match else None


def fetch_deepkoala_ftp_versions() -> list[str]:
    with urllib.request.urlopen(f"{DEEPKOALA_BASE}/", timeout=30) as response:
        html = response.read().decode("utf-8", errors="replace")
    return sorted(set(re.findall(r'href="([0-9]{6})/?\"', html)))


def fetch_deepkoala_file_listing(date: str) -> set[str]:
    with urllib.request.urlopen(f"{DEEPKOALA_BASE}/{date}/", timeout=30) as response:
        html = response.read().decode("utf-8", errors="replace")
    return set(re.findall(r'href="([^"/]+)"', html))


def download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".tmp")
    print(f"[download] {url}", file=sys.stderr)
    with urllib.request.urlopen(url) as response, tmp.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    tmp.replace(dest)


def read_md5(md5_path: Path) -> str:
    text = md5_path.read_text().strip().split()
    if not text:
        raise ValueError(f"empty MD5 file: {md5_path}")
    return text[0]


def md5sum(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_extract(tar: tarfile.TarFile, dest: Path) -> None:
    dest = dest.resolve()
    for member in tar.getmembers():
        target = (dest / member.name).resolve()
        if not str(target).startswith(str(dest)):
            raise RuntimeError(f"unsafe path in archive: {member.name}")
    tar.extractall(dest)


def download_interpro_archive(arcname: str, version: str, outdir: Path, iprscan_version: str) -> None:
    major_minor = ".".join(iprscan_version.split(".")[:2])
    final_dir = outdir / arcname / version
    if final_dir.exists():
        return

    url_prefix = f"{INTERPRO_DOWNLOAD_BASE}/{major_minor}/{arcname}"
    archive = Path(f"{arcname}-{version}.tar.gz")
    md5_file = Path(f"{archive.name}.md5")
    download_file(f"{url_prefix}/{archive.name}", archive)
    download_file(f"{url_prefix}/{md5_file.name}", md5_file)
    expected = read_md5(md5_file)
    observed = md5sum(archive)
    if observed != expected:
        raise RuntimeError(f"MD5 checksum failed for {archive}: expected {expected}, observed {observed}")
    with tarfile.open(archive, "r:gz") as tar:
        safe_extract(tar, outdir)
    archive.unlink()
    md5_file.unlink()


def prepare_interpro(args: argparse.Namespace, requested_apps: list[str]) -> None:
    datadir = Path(args.interproscan6_datadir)
    datadir.mkdir(parents=True, exist_ok=True)
    interpro_dir = datadir / "interpro" / args.interproscan6_interpro_version
    databases_json = interpro_dir / "databases.json"
    if not databases_json.exists():
        download_interpro_archive(
            "interpro",
            args.interproscan6_interpro_version,
            datadir,
            args.interproscan6_version,
        )

    if not databases_json.exists():
        raise RuntimeError(f"InterPro metadata download did not create {databases_json}")

    databases = json.loads(databases_json.read_text())
    normalised = {re.sub(r"[\s-]+", "", key).lower(): str(value) for key, value in databases.items()}
    apps = set(requested_apps)
    if "cathgene3d" in apps or "cathfunfam" in apps:
        apps.update(["cathgene3d", "cathfunfam"])

    seen_archives: set[str] = set()
    for app in sorted(apps):
        if app not in INTERPRO_APPS_WITH_DATA:
            continue
        archive_name, subdir = INTERPRO_APPS_WITH_DATA[app]
        version = normalised.get(app)
        if not version:
            raise RuntimeError(f"Could not find InterPro database version for app {app} in {databases_json}")
        expected_dir = datadir / archive_name / version / subdir
        if expected_dir.exists():
            continue
        key = f"{archive_name}:{version}"
        if key in seen_archives:
            continue
        download_interpro_archive(archive_name, version, datadir, args.interproscan6_version)
        seen_archives.add(key)


def gunzip(path: Path) -> Path:
    out = path.with_suffix("")
    with gzip.open(path, "rb") as fin, out.open("wb") as fout:
        shutil.copyfileobj(fin, fout)
    path.unlink()
    return out


def prepare_pfam_native(args: argparse.Namespace) -> None:
    pfam_dir = Path(args.interproscan6_datadir) / "pfam" / args.interpro_pfam_version
    hmm = pfam_dir / "pfam_a.hmm"
    dat = pfam_dir / "pfam_a.dat"
    if hmm.exists() and dat.exists():
        return
    pfam_dir.mkdir(parents=True, exist_ok=True)
    download_file("https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz", pfam_dir / "pfam_a.hmm.gz")
    download_file("https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.dat.gz", pfam_dir / "pfam_a.dat.gz")
    gunzip(pfam_dir / "pfam_a.hmm.gz")
    gunzip(pfam_dir / "pfam_a.dat.gz")
    subprocess.run(["hmmpress", "-f", str(hmm)], check=True)


def prepare_eggnog(args: argparse.Namespace) -> None:
    data_dir = Path(args.eggnog_data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)
    required = [Path(args.eggnog_mapper_db), data_dir / "eggnog.db", data_dir / "eggnog.taxa.db"]
    if all(path.exists() for path in required):
        return
    subprocess.run(["download_eggnog_data.py", "-y", "--data_dir", str(data_dir)], check=True)


def prepare_amrfinder(args: argparse.Namespace) -> None:
    if not args.amrfinder_db:
        return
    db_dir = Path(args.amrfinder_db)
    db_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(["amrfinder_update", "--database", str(db_dir)], check=True)


def prepare_deepkoala(args: argparse.Namespace) -> None:
    if not args.deepkoala_resources:
        return
    resources = Path(args.deepkoala_resources)
    resources.mkdir(parents=True, exist_ok=True)
    required_files = deepkoala_required_files(args.deepkoala_model)
    if args.deepkoala_date == "latest":
        local_latest = newest_complete_deepkoala_model(resources, args.deepkoala_model)
        if local_latest:
            return
        dates = []
        current_version = fetch_deepkoala_current_version()
        if current_version:
            dates.append(current_version)
        dates.extend(reversed(fetch_deepkoala_ftp_versions()))
        dates = list(dict.fromkeys(dates))
        if not dates:
            raise RuntimeError(f"Could not determine latest DeepKOALA model date from {DEEPKOALA_BASE}/")
        date = None
        missing_by_date = {}
        for candidate in dates:
            available = fetch_deepkoala_file_listing(candidate)
            missing = [filename for filename in required_files if filename not in available]
            if not missing:
                date = candidate
                break
            missing_by_date[candidate] = missing
        if date is None:
            details = "; ".join(f"{candidate}: missing {', '.join(missing)}" for candidate, missing in missing_by_date.items())
            raise RuntimeError(f"No complete DeepKOALA {args.deepkoala_model} model release found. {details}")
    else:
        date = args.deepkoala_date
        available = fetch_deepkoala_file_listing(date)
        missing = [filename for filename in required_files if filename not in available]
        if missing:
            raise RuntimeError(
                f"DeepKOALA release {date} is missing required files for model {args.deepkoala_model}: {', '.join(missing)}"
            )
    target = resources / date
    target.mkdir(parents=True, exist_ok=True)
    for filename in required_files:
        dest = target / filename
        if not dest.exists():
            download_file(f"{DEEPKOALA_BASE}/{date}/{filename}", dest)


def prepare_databases(args: argparse.Namespace, requested: set[str], interpro_apps: list[str]) -> None:
    if args.db_root:
        for dirname in ["interproscan", "eggnog", "deepkoala", "amrfinder"]:
            Path(args.db_root, dirname).mkdir(parents=True, exist_ok=True)
    if "interpro" in requested:
        if args.interpro_mode == "native":
            native_apps = set(interpro_apps)
            if "pfam" in native_apps:
                prepare_pfam_native(args)
            if "ncbifam" in native_apps:
                prepare_interpro(args, ["ncbifam"])
            prepare_interpro(args, [])
        else:
            prepare_interpro(args, interpro_apps)
    if "deepkoala" in requested:
        prepare_deepkoala(args)
    if "eggnog" in requested:
        prepare_eggnog(args)
    if "amrfinder" in requested:
        prepare_amrfinder(args)


class Validator:
    def __init__(self, skip: bool):
        self.skip = skip
        self.records: list[dict[str, object]] = []
        self.errors: list[str] = []

    def add(self, tool: str, name: str, path: str | Path | None, required: bool = True, note: str = "") -> None:
        if path in (None, ""):
            status = "missing" if required else "not_configured"
            exists = False
            path_text = ""
        else:
            p = Path(str(path))
            exists = p.exists()
            status = "skipped" if self.skip else ("ok" if exists else "missing")
            path_text = str(p)

        self.records.append(
            {
                "tool": tool,
                "name": name,
                "path": path_text,
                "required": required,
                "status": status,
                "note": note,
            }
        )
        if required and not self.skip and not exists:
            self.errors.append(f"{tool}: missing {name}: {path_text or '<unset>'}")

    def write(self, out: Path, args: argparse.Namespace) -> None:
        with out.open("w") as handle:
            handle.write("panannotator_databases:\n")
            handle.write(f"  db_root: {q(args.db_root or '')}\n")
            handle.write(f"  prepare_databases: {str(args.prepare_databases).lower()}\n")
            handle.write(f"  skip_db_validation: {str(args.skip_db_validation).lower()}\n")
            handle.write("  entries:\n")
            for rec in self.records:
                handle.write(f"    - tool: {q(rec['tool'])}\n")
                handle.write(f"      name: {q(rec['name'])}\n")
                handle.write(f"      path: {q(rec['path'])}\n")
                handle.write(f"      required: {str(rec['required']).lower()}\n")
                handle.write(f"      status: {q(rec['status'])}\n")
                if rec["note"]:
                    handle.write(f"      note: {q(rec['note'])}\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--annotation-tools", required=True)
    parser.add_argument("--all-protein-tools", required=True)
    parser.add_argument("--interpro-apps", required=True)
    parser.add_argument("--interpro-mode", required=True, choices=["native", "imported"])
    parser.add_argument("--interproscan6-datadir", required=True)
    parser.add_argument("--interproscan6-version", required=True)
    parser.add_argument("--interproscan6-interpro-version", required=True)
    parser.add_argument("--interpro-pfam-version", required=True)
    parser.add_argument("--interpro-ncbifam-version", required=True)
    parser.add_argument("--deepkoala-resources", default="")
    parser.add_argument("--deepkoala-workdir", default="")
    parser.add_argument("--deepkoala-model", default="full")
    parser.add_argument("--deepkoala-date", default="latest")
    parser.add_argument("--eggnog-data-dir", default="")
    parser.add_argument("--eggnog-mapper-db", default="")
    parser.add_argument("--amrfinder-db", default="")
    parser.add_argument("--db-root", default="")
    parser.add_argument("--prepare-databases", action="store_true")
    parser.add_argument("--skip-db-validation", action="store_true")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    requested = set(split_csv(args.annotation_tools))
    all_protein = set(split_csv(args.all_protein_tools)) & requested
    requested.update(all_protein)
    interpro_apps = split_csv(args.interpro_apps)

    if args.prepare_databases:
        prepare_databases(args, requested, interpro_apps)

    validator = Validator(skip=args.skip_db_validation)

    if "interpro" in requested:
        datadir = Path(args.interproscan6_datadir)
        validator.add("interpro", "data directory", datadir)
        validator.add(
            "interpro",
            "InterPro entries",
            datadir / "interpro" / args.interproscan6_interpro_version / "entries.json",
        )
        validator.add(
            "interpro",
            "InterPro database metadata",
            datadir / "interpro" / args.interproscan6_interpro_version / "databases.json",
            required=args.interpro_mode == "imported",
        )

        apps = interpro_apps
        if args.interpro_mode == "native":
            if "pfam" in apps:
                validator.add("interpro", "Pfam HMM", datadir / "pfam" / args.interpro_pfam_version / "pfam_a.hmm")
                validator.add("interpro", "Pfam metadata", datadir / "pfam" / args.interpro_pfam_version / "pfam_a.dat")
            if "ncbifam" in apps:
                validator.add(
                    "interpro",
                    "NCBIFAM HMM",
                    datadir / "ncbifam" / args.interpro_ncbifam_version / "ncbifam.hmm",
                )
        else:
            for app in apps:
                app_dir = INTERPRO_APP_DIRS.get(app)
                if app_dir:
                    validator.add(
                        "interpro",
                        f"{app} data directory",
                        datadir / app_dir,
                        note="Version subdirectory is selected by the vendored InterProScan 6 workflow.",
                    )

    if "deepkoala" in requested:
        resources = args.deepkoala_resources
        if resources:
            validator.add("deepkoala", "resources directory", resources)
            if args.deepkoala_date == "latest":
                latest = newest_complete_deepkoala_model(Path(resources), args.deepkoala_model)
                validator.add(
                    "deepkoala",
                    "latest model directory",
                    Path(resources) / latest if latest else None,
                    note="Selected because --deepkoala_date latest.",
                )
            else:
                validator.add("deepkoala", "model directory", Path(resources) / args.deepkoala_date)
        elif args.deepkoala_workdir:
            validator.add(
                "deepkoala",
                "legacy source checkout",
                args.deepkoala_workdir,
                note="Prefer --deepkoala_resources for packaged/container execution.",
            )
        else:
            validator.add(
                "deepkoala",
                "resources directory",
                None,
                note="Set --deepkoala_resources, or --deepkoala_workdir for legacy source-checkout execution.",
            )

    if "eggnog" in requested:
        validator.add("eggnog", "data directory", args.eggnog_data_dir)
        validator.add("eggnog", "DIAMOND database", args.eggnog_mapper_db)
        validator.add("eggnog", "annotation database", Path(args.eggnog_data_dir) / "eggnog.db")
        validator.add("eggnog", "taxonomy database", Path(args.eggnog_data_dir) / "eggnog.taxa.db")

    if "amrfinder" in requested:
        if args.amrfinder_db:
            validator.add("amrfinder", "database directory", resolve_amrfinder_db(args.amrfinder_db))
        else:
            validator.add(
                "amrfinder",
                "database directory",
                "",
                required=False,
                note="No --amrfinder_db provided; AMRFinder+ will use its own configured default database lookup.",
            )

    validator.write(Path(args.out), args)

    if validator.errors:
        print("Database validation failed:", file=sys.stderr)
        for error in validator.errors:
            print(f"  - {error}", file=sys.stderr)
        print("Use --skip_db_validation true to bypass checks, or set the relevant database path parameters.", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
