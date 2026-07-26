process PARSE_EGGNOG {
    tag "$meta.id"
    label "process_single"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    publishDir "${params.outdir}/annotation/raw/eggnog", mode: "copy", enabled: params.keep_raw_annotations

    input:
    tuple val(meta), path(eggnog_raw)

    output:
    tuple val(meta.id), path("${meta.id}.eggnog.tsv.gz")

    script:
    """
    set -euo pipefail
    python - <<'PY'
import csv
import gzip
import sys

sample = "${meta.id}"
raw_path = "${eggnog_raw}"
out_path = "${meta.id}.eggnog.tsv"

header = None
query_idx = 0
ogs_idx = None

opener = gzip.open if raw_path.endswith(".gz") else open
with opener(raw_path, "rt", newline="") as handle, open(out_path, "w", newline="") as out_handle:
    writer = csv.writer(out_handle, delimiter="\\t", lineterminator="\\n")
    writer.writerow(["sample_id", "protein_id", "eggNOG_OGs"])

    for line in handle:
        line = line.rstrip("\\n")
        if not line:
            continue
        if line.startswith("#"):
            candidate = line.lstrip("#").split("\\t")
            lowered = [col.strip().lower() for col in candidate]
            if "eggnog_ogs" in lowered:
                header = candidate
                ogs_idx = lowered.index("eggnog_ogs")
                for name in ("query", "query_name", "protein_id"):
                    if name in lowered:
                        query_idx = lowered.index(name)
                        break
            continue

        fields = line.split("\\t")
        if ogs_idx is None:
            sys.exit("Could not find eggNOG_OGs column in eggNOGMapper output header")
        if len(fields) <= max(query_idx, ogs_idx):
            continue
        ogs = fields[ogs_idx].strip()
        if ogs and ogs not in {"-", "NA"}:
            writer.writerow([sample, fields[query_idx].strip(), ogs])
PY
    gzip -f "${meta.id}.eggnog.tsv"
    """
}
