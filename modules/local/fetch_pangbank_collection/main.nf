process FETCH_PANGBANK_COLLECTION {
    tag "${params.collection}:${params.collection_release}"
    label "process_medium"
    publishDir "${params.outdir}/inputs", mode: "copy"

    output:
    path "all_protein_families.faa.gz", emit: all_faa
    path "pangenome_families.tsv", emit: pangenome_families
    path "pangenomes.txt", emit: pangenomes
    path "pangenomes_root.txt", emit: pangenomes_root
    path "pangenome_api_ids.tsv", emit: pangenome_api_ids
    path "collection_release_id.txt", emit: collection_release_id
    path "versions_fetch_pangbank_collection.yml", emit: versions

    script:
    """
    bash ${projectDir}/bin/fetch_pangbank_collection.sh \\
      --collection-release ${params.collection_release} \\
      --collection ${params.collection} \\
      --out-dir . \\
      --pangbank-root ${params.pangbank_root} \\
      --pangbank-api-url ${params.pangbank_api_url}

    cat <<-END_VERSIONS > versions_fetch_pangbank_collection.yml
    "${task.process}":
        bash: \$(bash --version | head -n 1 | sed 's/^GNU bash, version //; s/(.*//')
        python: \$(python3 --version | sed 's/^Python //')
    END_VERSIONS
    """
}
