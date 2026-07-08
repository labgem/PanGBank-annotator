process PACKAGE_PANFAM {
    tag "PANFAM"
    label "process_high"
    publishDir "${params.outdir}", mode: "copy"

    input:
    path all_faa_gz
    path pangenome_families
    path cluster_tables

    output:
    path "PANFAM", emit: panfam

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
      --collection-release-id ${params.collection_release} \\
      --out-dir PANFAM \\
      --levels ${levels_arg} \\
      --compression ${params.compression}
    """
}
