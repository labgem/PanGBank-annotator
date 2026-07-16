process DIAMOND_DEEPCLUST {
    tag "${level}"
    label "process_deepclust"
    publishDir "${params.outdir}/diamond/clusters", mode: "copy", enabled: params.keep_raw_clusters

    input:
    tuple val(level), val(approx_id), path(db)

    output:
    tuple val(level), path("deepclust_${level}.tsv.gz"), emit: clusters
    path "versions_deepclust_${level}.yml", emit: versions

    script:
    """
    diamond deepclust \\
      -d ${db} \\
      -o deepclust_${level}.tsv \\
      --approx-id ${approx_id} \\
      -e ${params.evalue} \\
      --member-cover ${params.member_cover} \\
      --comp-based-stats 1 \\
      --threads ${task.cpus} \\
      -M ${params.diamond_memory} \\
      --header

    gzip -f deepclust_${level}.tsv

    cat <<-END_VERSIONS > versions_deepclust_${level}.yml
    "${task.process}":
        diamond: \$(diamond --version | sed 's/^diamond version //')
    END_VERSIONS
    """
}
