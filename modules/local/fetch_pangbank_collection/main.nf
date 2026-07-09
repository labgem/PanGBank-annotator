process FETCH_PANGBANK_COLLECTION {
    tag "${params.source}:${params.collection_release}"
    label "process_medium"
    publishDir "${params.outdir}/inputs", mode: "copy"

    output:
    path "all_protein_families.faa.gz", emit: all_faa
    path "pangenome_families.tsv", emit: pangenome_families
    path "pangenomes.txt", emit: pangenomes
    path "pangenomes_root.txt", emit: pangenomes_root
    path "collection_release_id.txt", emit: collection_release_id

    script:
    """
    bash ${projectDir}/bin/fetch_pangbank_collection.sh \\
      --collection-release ${params.collection_release} \\
      --source ${params.source} \\
      --out-dir . \\
      --pangbank-root ${params.pangbank_root} \\
      --pangbank-api-url ${params.pangbank_api_url}
    """
}
