#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: fetch_pangbank_collection.sh \
  --collection-release RELEASE \
  --collection COLLECTION \
  --out-dir DIR \
  [--pangbank-root DIR] \
  [--pangbank-api-url URL]

Resolve a PanGBank collection release through the PanGBank API, write
collection_release_id.txt as r<api_release_id>, write pangenomes.txt, write
pangenome_families.tsv from FASTA record IDs, and concatenate local
all_protein_families.faa.gz files into all_protein_families.faa.gz.

Sequence data are read from the local PanGBank data mirror:
  <pangbank-root>/collections/<collection>/release_<release>/data/pangenomes
EOF
}

collection_release=""
collection=""
out_dir=""
pangbank_root="${PANGBANK_ROOT:-/env/export/pangbank_data/prod}"
pangbank_api_url="${PANGBANK_API_URL:-https://pangbank-api.genoscope.cns.fr}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --collection-release)
            collection_release="$2"
            shift 2
            ;;
        --collection)
            collection="$2"
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

if [[ -z "$collection_release" || -z "$collection" || -z "$out_dir" ]]; then
    usage
    exit 2
fi

case "$collection" in
    GTDB_all|GTDB_refseq) ;;
    *)
        echo "[error] --collection must be a full PanGBank collection name, e.g. GTDB_all or GTDB_refseq" >&2
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

fetch_pangenome_api_ids() {
    local collection_name="$1"
    local release_id="$2"
    local api_url="$3"
    local out_tsv="$4"

    API_URL="$api_url" COLLECTION_NAME="$collection_name" RELEASE_ID="${release_id#r}" OUT_TSV="$out_tsv" python3 <<'PY'
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen

api_url = os.environ["API_URL"].rstrip("/")
collection_name = os.environ["COLLECTION_NAME"]
release_id = int(os.environ["RELEASE_ID"])
out_tsv = os.environ["OUT_TSV"]

limit = 100
offset = 0
name_to_id: dict[str, int] = {}

while True:
    query = urlencode(
        {
            "collection_name": collection_name,
            "only_latest_release": "false",
            "offset": offset,
            "limit": limit,
        }
    )
    url = f"{api_url}/pangenomes/?{query}"
    try:
        with urlopen(url, timeout=30) as response:
            records = json.load(response)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"[error] failed to query PanGBank API: {url}: {error}", file=sys.stderr)
        sys.exit(1)

    if not records:
        break

    for record in records:
        record_release_id = record.get("collection_release_id")
        if record_release_id is None:
            record_release_id = (record.get("collection_release") or {}).get("id")
        if record_release_id != release_id:
            continue

        name = record.get("name")
        pangenome_id = record.get("id")
        if not name or pangenome_id is None:
            print(f"[error] malformed pangenome API record: {record}", file=sys.stderr)
            sys.exit(1)
        if name in name_to_id and name_to_id[name] != pangenome_id:
            print(f"[error] duplicate pangenome name with different ids in API: {name}", file=sys.stderr)
            sys.exit(1)
        name_to_id[name] = pangenome_id

    offset += limit
    if len(records) < limit:
        break

if not name_to_id:
    print(
        f"[error] no pangenomes found in PanGBank API for {collection_name} release id r{release_id}",
        file=sys.stderr,
    )
    sys.exit(1)

with open(out_tsv, "w", encoding="utf-8") as handle:
    handle.write("Local_pangenome_name\tPangenome_id\n")
    for name, pangenome_id in sorted(name_to_id.items()):
        handle.write(f"{name}\t{pangenome_id}\n")
PY
}

export_from_pangenomes_root() {
    local root="$1"
    local api_ids_tsv="$2"
    local local_pangenomes="$out_dir/local_pangenomes.txt"

    find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort > "$local_pangenomes"
    if [[ ! -s "$local_pangenomes" ]]; then
        echo "[error] no pangenome directories found in $root" >&2
        exit 1
    fi

    printf 'Pangenome_id\tPangenome_family_id\n' > "$out_dir/pangenome_families.tsv"
    : > "$out_dir/pangenomes.txt"

    declare -A pangenome_ids=()
    while IFS=$'\t' read -r local_name pangenome_id; do
        if [[ "$local_name" == "Local_pangenome_name" ]]; then
            continue
        fi
        pangenome_ids["$local_name"]="$pangenome_id"
    done < "$api_ids_tsv"

    {
        while IFS= read -r local_pangenome_name; do
            pangenome_id="${pangenome_ids[$local_pangenome_name]:-}"
            if [[ -z "$pangenome_id" ]]; then
                echo "[error] pangenome is present in the local mirror but absent from the PanGBank API release: $local_pangenome_name" >&2
                exit 1
            fi

            printf '%s\n' "$pangenome_id" >> "$out_dir/pangenomes.txt"
            fasta="$root/$local_pangenome_name/all_protein_families.faa.gz"
            if [[ ! -s "$fasta" ]]; then
                echo "[error] missing FASTA for pangenome $local_pangenome_name: $fasta" >&2
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
        done < "$local_pangenomes"
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
fetch_pangenome_api_ids "$collection" "$collection_release_id" "$pangbank_api_url" "$out_dir/pangenome_api_ids.tsv"

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
    export_from_pangenomes_root "$pangenomes_root" "$out_dir/pangenome_api_ids.tsv"
    printf '%s\n' "$pangenomes_root" > "$out_dir/pangenomes_root.txt"
    exit 0
fi

echo "[error] local PanGBank mirror not found for $collection release $collection_release" >&2
printf '[error] tried path: %s\n' "${tried_roots[@]}" >&2
exit 1
