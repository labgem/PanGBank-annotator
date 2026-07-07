process DIAMOND_DEEPCLUST {
    tag "${level}"
    label "process_deepclust"
    publishDir "${params.outdir}/diamond/clusters", mode: "copy"

    input:
    tuple val(level), val(approx_id), path(db)

    output:
    tuple val(level), path("deepclust_${level}.tsv"), emit: clusters

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
    """
}
