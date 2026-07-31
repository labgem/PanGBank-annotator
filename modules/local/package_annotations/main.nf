process PACKAGE_ANNOTATIONS {
    tag "$tool"
    label "process_medium"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.panannotator_container : params.panannotator_container}"
    publishDir "${params.outdir}/annotation/parquet", mode: "copy", saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    val tool
    val input_mode
    path raw_annotations
    path panfam_dir
    path pangenome_families

    output:
    path "${tool}.parquet", emit: global
    path "pangenomes/*.parquet", optional: true, emit: pangenomes
    path "versions_package_${tool}.yml", emit: versions

    script:
    """
    set -euo pipefail
    mkdir -p out

    python ${projectDir}/bin/package_annotations.py \\
        --tool "${tool}" \\
        --input-mode "${input_mode}" \\
        --raw ${raw_annotations} \\
        --panfam-80 "${panfam_dir}/parquet/PANFAM_80.parquet" \\
        --pangenome-families "${pangenome_families}" \\
        --out-dir out \\
        --compression "${params.compression}"

    mv out/${tool}.parquet .
    mkdir -p pangenomes
    mv out/pangenomes/*.parquet pangenomes/ 2>/dev/null || true

    python - <<'PY' > versions_package_${tool}.yml
import platform
import pandas

print('"${task.process}":')
print(f'    python: {platform.python_version()}')
print(f'    pandas: {pandas.__version__}')
PY
    """
}
