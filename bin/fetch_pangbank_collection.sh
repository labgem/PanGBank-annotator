#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: fetch_pangbank_collection.sh \
  --collection-release RELEASE \
  --source all|refseq \
  --out-dir DIR \
  [--pangbank-root DIR] \
  [--pangbank-cli pangbank]

Resolve a PanGBank collection release, write pangenomes.txt, write
pangenome_families.tsv from FASTA record IDs, and concatenate
all_protein_families.faa.gz into all_protein_families.faa.gz.

The preferred path is direct filesystem access to the PanGBank data mirror:
  <pangbank-root>/collections/GTDB_<source>/release_<release>/data/pangenomes

If that path is absent and pangbank is installed, the script falls back to
PanGBank-cli download mode.
EOF
}

collection_release=""
source_name=""
out_dir=""
pangbank_root="${PANGBANK_ROOT:-/env/export/pangbank_data/prod}"
pangbank_cli="${PANGBANK_CLI:-pangbank}"

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
        --pangbank-cli)
            pangbank_cli="$2"
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
    export_from_pangenomes_root "$pangenomes_root"
    printf '%s\n' "$pangenomes_root" > "$out_dir/pangenomes_root.txt"
    exit 0
fi

if ! command -v "$pangbank_cli" >/dev/null 2>&1; then
    echo "[error] local mirror not found and PanGBank-cli is unavailable: $pangbank_cli" >&2
    printf '[error] tried path: %s\n' "${tried_roots[@]}" >&2
    exit 1
fi

echo "[info] local mirror absent; using PanGBank-cli for $collection" >&2
"$pangbank_cli" search-pangenomes \
    --collection "$collection" \
    --outdir "$out_dir/download" \
    --download \
    --no-progress \
    --table-path "$out_dir/pangenomes.tsv"

export_from_pangenomes_root "$out_dir/download"
printf '%s\n' "$out_dir/download" > "$out_dir/pangenomes_root.txt"
