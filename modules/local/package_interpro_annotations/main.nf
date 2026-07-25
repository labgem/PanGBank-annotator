process PACKAGE_INTERPRO_ANNOTATIONS {
    tag "interpro"
    label "process_medium"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    publishDir "${params.outdir}/annotation/parquet", mode: "copy", saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    val tools
    val input_mode
    path raw_annotations
    path panfam_dir
    path pangenome_families

    output:
    path "*.parquet", emit: global
    path "pangenomes/*.parquet", optional: true, emit: pangenomes
    path "versions_package_interpro.yml", emit: versions

    script:
    """
    set -euo pipefail
    mkdir -p pangenomes

    IFS=',' read -r -a interpro_tools <<< "${tools}"
    for raw_tool in "\${interpro_tools[@]}"; do
        tool="\$(printf '%s' "\${raw_tool}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')"
        if [[ -z "\${tool}" ]]; then
            continue
        fi
        mkdir -p "out_\${tool}"

        python ${projectDir}/bin/package_annotations.py \\
            --tool "\${tool}" \\
            --input-mode "${input_mode}" \\
            --raw ${raw_annotations} \\
            --panfam-80 "${panfam_dir}/parquet/PANFAM_80.parquet" \\
            --pangenome-families "${pangenome_families}" \\
            --out-dir "out_\${tool}" \\
            --compression "${params.compression}"

        mv "out_\${tool}/\${tool}.parquet" .
        mv "out_\${tool}"/pangenomes/*.parquet pangenomes/ 2>/dev/null || true
    done

    python - <<'PY' > versions_package_interpro.yml
import platform
import pandas

print('"${task.process}":')
print(f'    python: {platform.python_version()}')
print(f'    pandas: {pandas.__version__}')
PY
    """
}
