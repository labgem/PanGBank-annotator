process DIAMOND_REASSIGN {
    tag "${level}"
    label "process_deepclust"
    publishDir "${params.outdir}/diamond/clusters", mode: "copy", enabled: params.keep_raw_clusters

    input:
    tuple val(level), path(clusters), path(db)

    output:
    tuple val(level), path("corrected_${level}.tsv.gz"), emit: clusters
    path "versions_reassign_${level}.yml", emit: versions

    script:
    def approx_id = level == "deep" ? params.deep_approx_id : level
    """
    gzip -dc ${clusters} > input_clusters_${level}.tsv

    /env/products/diamond/2.1.13/bin/diamond reassign \\
      -d ${db} \\
      --clusters input_clusters_${level}.tsv \\
      -o corrected_${level}.tsv \\
      --member-cover ${params.member_cover} \\
      -e ${params.evalue} \\
      --masking 0 \\
      --soft-masking 0 \\
      --comp-based-stats 0 \\
      --approx-id ${approx_id} \\
      --threads ${task.cpus} \\
      -M ${params.diamond_memory} \\
      --header

    gzip -f corrected_${level}.tsv
    rm -f input_clusters_${level}.tsv

    cat <<-END_VERSIONS > versions_reassign_${level}.yml
    "${task.process}":
        diamond: \$(/env/products/diamond/2.1.13/bin/diamond --version | sed 's/^diamond version //')
    END_VERSIONS
    """
}
