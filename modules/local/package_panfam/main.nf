process PACKAGE_PANFAM {
    tag "PANFAM"
    label "process_high"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    publishDir "${params.outdir}", mode: "copy", saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    path all_faa_gz
    path pangenome_families
    val collection_release_id
    path cluster_tables
    val package_levels
    val output_dir
    val skip_report

    output:
    path "${output_dir}", emit: panfam
    path "report/clustering/custom_content/*_mqc.yaml", emit: multiqc, optional: true
    path "report/clustering/tables/*.tsv", emit: multiqc_raw_data, optional: true
    path "report/clustering/plots/*.png", emit: multiqc_plots, optional: true
    path "versions_package_*.yml", emit: versions

    script:
    def levels_arg = package_levels instanceof List
        ? package_levels.join(' ')
        : package_levels.toString().split(',').collect { it.trim() }.findAll { it }.join(' ')
    def cluster_pattern = params.run_cluster_correction.toString() == 'true'
        ? 'corrected_{level}.tsv.gz'
        : 'deepclust_{level}.tsv.gz'
    def report_arg = skip_report.toString() == 'true'
        ? '--skip-report'
        : '--report-dir report/clustering'
    def safe_output_dir = output_dir.toString().replaceAll(/[^A-Za-z0-9_.-]/, '_')

    """
    mkdir -p clusters
    export XDG_CACHE_HOME="\$PWD/.cache"
    export MPLCONFIGDIR="\$PWD/.matplotlib"
    cp ${cluster_tables} clusters/
    python ${projectDir}/bin/package_clusters.py \\
      --clusters-dir clusters \\
      --all-faa-gz ${all_faa_gz} \\
      --pangenome-families ${pangenome_families} \\
      --collection-release-id "${collection_release_id}" \\
      --out-dir ${output_dir} \\
      ${report_arg} \\
      --cluster-pattern "${cluster_pattern}" \\
      --levels ${levels_arg} \\
      --compression ${params.compression}

    python - <<'PY' > versions_package_${safe_output_dir}.yml
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
