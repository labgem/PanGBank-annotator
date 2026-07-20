process PACKAGE_PANFAM {
    tag "PANFAM"
    label "process_high"
    publishDir "${params.outdir}", mode: "copy"

    input:
    path all_faa_gz
    path pangenome_families
    path collection_release_id
    path cluster_tables

    output:
    path "PANFAM", emit: panfam
    path "multiqc/custom_content/*_mqc.yaml", emit: multiqc
    path "multiqc/analysis/raw_data/*.tsv", emit: multiqc_raw_data
    path "multiqc/multiqc_plots/*.png", emit: multiqc_plots
    path "versions_package_panfam.yml", emit: versions

    script:
    def levels_arg = params.levels instanceof List
        ? params.levels.join(' ')
        : params.levels.toString().split(',').collect { it.trim() }.findAll { it }.join(' ')

    """
    mkdir -p clusters
    export XDG_CACHE_HOME="\$PWD/.cache"
    export MPLCONFIGDIR="\$PWD/.matplotlib"
    cp ${cluster_tables} clusters/
    python ${projectDir}/bin/package_clusters.py \\
      --clusters-dir clusters \\
      --all-faa-gz ${all_faa_gz} \\
      --pangenome-families ${pangenome_families} \\
      --collection-release-id "\$(cat ${collection_release_id})" \\
      --out-dir PANFAM \\
      --report-dir multiqc \\
      --levels ${levels_arg} \\
      --compression ${params.compression}

    python - <<'PY' > versions_package_panfam.yml
import platform
import pandas

print(f'"${task.process}":')
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
