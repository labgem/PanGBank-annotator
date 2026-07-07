process DIAMOND_MAKEDB {
    tag "all_protein_families"
    label "process_high"
    publishDir "${params.outdir}/diamond/dbs", mode: "copy"

    input:
    path all_faa_gz

    output:
    path "panfam.dmnd", emit: db

    script:
    """
    gzip -dc ${all_faa_gz} > all_protein_families.faa
    diamond makedb --in all_protein_families.faa -d panfam
    """
}
