process DIAMOND_MAKEDB {
    tag "all_protein_families"
    label "process_high"
    conda "${projectDir}/modules/local/envs/diamond_2_1_24/environment.yml"
    publishDir "${params.outdir}/diamond/dbs", mode: "copy", saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    path all_faa_gz

    output:
    path "panfam.dmnd", emit: db
    path "versions_makedb.yml", emit: versions

    script:
    """
    if [[ "${all_faa_gz}" == *.gz ]]; then
      gzip -dc ${all_faa_gz} > all_protein_families_for_db.faa
    else
      cp ${all_faa_gz} all_protein_families_for_db.faa
    fi
    diamond makedb --in all_protein_families_for_db.faa -d panfam

    cat <<-END_VERSIONS > versions_makedb.yml
    "${task.process}":
        diamond: \$(diamond --version | sed 's/^diamond version //')
    END_VERSIONS
    """
}
