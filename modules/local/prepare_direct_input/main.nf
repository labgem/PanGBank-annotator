process PREPARE_DIRECT_INPUT {
    tag "test_data"
    label "process_low"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    publishDir "${params.outdir}/inputs", mode: "copy", saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    path all_faa

    output:
    path all_faa, emit: all_faa
    path "pangenome_families.tsv", emit: pangenome_families
    path "collection_release_id.txt", emit: collection_release_id
    path "versions_prepare_direct_input.yml", emit: versions

    script:
    """
    printf 'Pangenome_id\\tPangenome_family_id\\n' > pangenome_families.tsv
    awk '
      substr(\$0, 1, 1) == ">" {
        id = substr(\$0, 2)
        split(id, fields, " ")
        print "1\\t" fields[1]
      }
    ' ${all_faa} >> pangenome_families.tsv

    printf '%s\\n' "${params.test_release_id}" > collection_release_id.txt

    cat <<-END_VERSIONS > versions_prepare_direct_input.yml
    "${task.process}":
        awk: \$(awk --version 2>/dev/null | head -n 1 || echo unknown)
    END_VERSIONS
    """
}
