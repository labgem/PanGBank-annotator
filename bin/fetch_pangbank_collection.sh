#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: fetch_pangbank_collection.sh \
  --collection-release RELEASE \
  --source all|refseq \
  --out-dir DIR \
  [--pangbank-root DIR] \
  [--pangbank-api-url URL]

Resolve a PanGBank collection release through the PanGBank API, write
collection_release_id.txt as r<api_release_id>, write pangenomes.txt, write
pangenome_families.tsv from FASTA record IDs, and concatenate local
all_protein_families.faa.gz files into all_protein_families.faa.gz.

Sequence data are read from the local PanGBank data mirror:
  <pangbank-root>/collections/GTDB_<source>/release_<release>/data/pangenomes
EOF
}

collection_release=""
source_name=""
out_dir=""
pangbank_root="${PANGBANK_ROOT:-/env/export/pangbank_data/prod}"
pangbank_api_url="${PANGBANK_API_URL:-https://pangbank-api.genoscope.cns.fr}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --collection-release)
            collection_release="$2"
            shift 2
            ;;
        --source)
            source_name="$2"
            shift 2
            ;;
        --out-dir)
            out_dir="$2"
            shift 2
            ;;
        --pangbank-root)
            pangbank_root="$2"
            shift 2
            ;;
        --pangbank-api-url)
            pangbank_api_url="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "[error] unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -z "$collection_release" || -z "$source_name" || -z "$out_dir" ]]; then
    usage
    exit 2
fi

case "$source_name" in
    all) collection="GTDB_all" ;;
    refseq) collection="GTDB_refseq" ;;
    *)
        echo "[error] --source must be one of: all, refseq" >&2
        exit 2
        ;;
esac

mkdir -p "$out_dir"

resolve_collection_release_id() {
    local collection_name="$1"
    local release_version="$2"
    local api_url="$3"

    API_URL="$api_url" COLLECTION_NAME="$collection_name" RELEASE_VERSION="$release_version" python3 <<'PY'
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

api_url = os.environ["API_URL"].rstrip("/")
collection_name = os.environ["COLLECTION_NAME"]
release_version = os.environ["RELEASE_VERSION"].removeprefix("v")
query = urlencode({"collection_name": collection_name, "only_latest_release": "false"})
url = f"{api_url}/collections/?{query}"

try:
    with urlopen(url, timeout=30) as response:
        collections = json.load(response)
except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
    print(f"[error] failed to query PanGBank API: {url}: {error}", file=sys.stderr)
    sys.exit(1)

matches = [collection for collection in collections if collection.get("name") == collection_name]
if not matches:
    print(f"[error] collection not found in PanGBank API: {collection_name}", file=sys.stderr)
    sys.exit(1)

releases = matches[0].get("releases") or []
for release in releases:
    if str(release.get("version", "")).removeprefix("v") == release_version:
        release_id = release.get("id")
        if release_id is None:
            print(f"[error] API release for {collection_name} {release_version} has no id", file=sys.stderr)
            sys.exit(1)
        print(f"r{release_id}")
        sys.exit(0)

available = ", ".join(str(release.get("version")) for release in releases) or "none"
print(
    f"[error] release {release_version} not found for {collection_name} in PanGBank API; "
    f"available releases: {available}",
    file=sys.stderr,
)
sys.exit(1)
PY
}

export_from_pangenomes_root() {
    local root="$1"
    find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort > "$out_dir/pangenomes.txt"
    if [[ ! -s "$out_dir/pangenomes.txt" ]]; then
        echo "[error] no pangenome directories found in $root" >&2
        exit 1
    fi

    printf 'Pangenome_id\tPangenome_family_id\n' > "$out_dir/pangenome_families.tsv"
    {
        while IFS= read -r pangenome_id; do
            fasta="$root/$pangenome_id/all_protein_families.faa.gz"
            if [[ ! -s "$fasta" ]]; then
                echo "[error] missing FASTA for pangenome $pangenome_id: $fasta" >&2
                exit 1
            fi

            gzip -dc "$fasta" | awk -v pg="$pangenome_id" '
                /^>/ {
                    id = substr($0, 2)
                    sub(/[[:space:]].*$/, "", id)
                    print pg "\t" id >> families
                }
                { print }
            ' families="$out_dir/pangenome_families.tsv"
        done < "$out_dir/pangenomes.txt"
    } | gzip -c > "$out_dir/all_protein_families.faa.gz"

    if [[ ! -s "$out_dir/all_protein_families.faa.gz" ]]; then
        echo "[error] no all_protein_families.faa.gz data found in $root" >&2
        exit 1
    fi
    if [[ "$(wc -l < "$out_dir/pangenome_families.tsv")" -le 1 ]]; then
        echo "[error] no pangenome family records found in $root" >&2
        exit 1
    fi
}

collection_release_id="$(resolve_collection_release_id "$collection" "$collection_release" "$pangbank_api_url")"
printf '%s\n' "$collection_release_id" > "$out_dir/collection_release_id.txt"

release_candidates=("$collection_release")
if [[ "$collection_release" != v* ]]; then
    release_candidates+=("v$collection_release")
fi

pangenomes_root=""
tried_roots=()
for candidate in "${release_candidates[@]}"; do
    candidate_root="$pangbank_root/collections/$collection/release_$candidate/data/pangenomes"
    tried_roots+=("$candidate_root")
    if [[ -d "$candidate_root" ]]; then
        pangenomes_root="$candidate_root"
        break
    fi
done

if [[ -z "$pangenomes_root" ]]; then
    pangenomes_root="$pangbank_root/collections/$collection/release_$collection_release/data/pangenomes"
fi

if [[ -d "$pangenomes_root" ]]; then
    echo "[info] using local PanGBank mirror: $pangenomes_root" >&2
    echo "[info] using PanGBank API collection release id: $collection_release_id" >&2
    export_from_pangenomes_root "$pangenomes_root"
    printf '%s\n' "$pangenomes_root" > "$out_dir/pangenomes_root.txt"
    exit 0
fi

echo "[error] local PanGBank mirror not found for $collection release $collection_release" >&2
printf '[error] tried path: %s\n' "${tried_roots[@]}" >&2
exit 1
