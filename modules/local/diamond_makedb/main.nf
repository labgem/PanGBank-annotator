process DIAMOND_MAKEDB {
    tag "all_protein_families"
    label "process_high"
    conda "${projectDir}/modules/local/envs/diamond_2_1_13/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'https://depot.galaxyproject.org/singularity/diamond:2.1.13--h13889ed_0' : 'quay.io/biocontainers/diamond:2.1.13--h13889ed_0'}"
    publishDir "${params.outdir}/clustering/raw/diamond/dbs", mode: "copy", enabled: params.keep_raw_clusters, saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    path all_faa_gz

    output:
    path "panfam.dmnd", emit: db
    path "versions_makedb.yml", emit: versions

    script:
    def diamond_bin = workflow.profile.tokenize(',').contains('local_tools') ? '/env/products/diamond/2.1.13/bin/diamond' : 'diamond'
    """
    diamond_bin="${diamond_bin}"
    if [[ "\$diamond_bin" != "diamond" && ! -x "\$diamond_bin" ]]; then
      diamond_bin="diamond"
    fi

    if [[ "${all_faa_gz}" == *.gz ]]; then
      gzip -dc ${all_faa_gz} > all_protein_families_for_db.faa
    else
      cp ${all_faa_gz} all_protein_families_for_db.faa
    fi
    "\$diamond_bin" makedb --in all_protein_families_for_db.faa -d panfam

    cat <<-END_VERSIONS > versions_makedb.yml
    "${task.process}":
        diamond: \$("\$diamond_bin" --version | sed 's/^diamond version //')
    END_VERSIONS
    """
}
