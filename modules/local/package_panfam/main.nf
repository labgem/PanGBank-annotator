process PACKAGE_PANFAM {
    tag "PANFAM"
    label "process_medium"
    publishDir "${params.outdir}/PANFAM", mode: "copy"

    input:
    path all_faa_gz
    path pangenome_families
    path cluster_tables

    output:
    path "PANFAM", emit: panfam

    script:
    """
    mkdir -p clusters
    cp ${cluster_tables} clusters/
    python ${projectDir}/bin/package_clusters.py \\
      --clusters-dir clusters \\
      --all-faa-gz ${all_faa_gz} \\
      --pangenome-families ${pangenome_families} \\
      --collection-release-id ${params.collection_release} \\
      --out-dir PANFAM \\
      --levels ${params.levels.join(' ')} \\
      --compression ${params.compression}
    """
}
