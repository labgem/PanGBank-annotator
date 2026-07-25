process DIAMOND_DEEPCLUST {
    tag "${level}"
    label "process_deepclust"
    conda "${projectDir}/modules/local/envs/diamond_2_1_13/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'https://depot.galaxyproject.org/singularity/diamond:2.1.13--h13889ed_0' : 'quay.io/biocontainers/diamond:2.1.13--h13889ed_0'}"
    publishDir "${params.outdir}/clustering/raw/diamond/clusters", mode: "copy", enabled: params.keep_raw_clusters, saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    tuple val(level), val(approx_id), path(db)

    output:
    tuple val(level), path("deepclust_${level}.tsv.gz"), emit: clusters
    path "versions_deepclust_${level}.yml", emit: versions

    script:
    def diamond_bin = workflow.profile.tokenize(',').contains('local_tools') ? '/env/products/diamond/2.1.13/bin/diamond' : 'diamond'
    """
    diamond_bin="${diamond_bin}"
    if [[ "\$diamond_bin" != "diamond" && ! -x "\$diamond_bin" ]]; then
      diamond_bin="diamond"
    fi

    "\$diamond_bin" deepclust \\
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
        diamond: \$("\$diamond_bin" --version | sed 's/^diamond version //')
    END_VERSIONS
    """
}
