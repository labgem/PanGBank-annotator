process REPORT_ANNOTATIONS {
    tag "annotation"
    label "process_medium"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    publishDir "${params.outdir}/report/annotation", mode: "copy", saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    path annotation_parquets
    path pangenome_families

    output:
    path "custom_content/*_mqc.yaml", emit: multiqc
    path "tables/*.tsv", emit: tables
    path "plots/*.png", emit: plots
    path "versions_report_annotations.yml", emit: versions

    script:
    """
    set -euo pipefail
    export XDG_CACHE_HOME="\$PWD/.cache"
    export MPLCONFIGDIR="\$PWD/.matplotlib"

    python ${projectDir}/bin/report_annotations.py \\
        --parquets ${annotation_parquets} \\
        --pangenome-families ${pangenome_families} \\
        --out-dir . \\
        --compression "${params.compression}"

    python - <<'PY' > versions_report_annotations.yml
import platform
import pandas

print('"${task.process}":')
print(f'    python: {platform.python_version()}')
print(f'    pandas: {pandas.__version__}')
try:
    import matplotlib
    print(f'    matplotlib: {matplotlib.__version__}')
except Exception:
    pass
PY
    """
}
