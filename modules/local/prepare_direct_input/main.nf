process PREPARE_DIRECT_INPUT {
    tag "test_data"
    label "process_low"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    publishDir "${params.outdir}/inputs", mode: "copy", saveAs: { filename ->
        if (filename.startsWith("versions_")) {
            return null
        } else if (filename == "collection_metadata.yml" || filename == "pangenome_api_ids.tsv") {
            return "metadata/${filename}"
        }
        return filename
    }

    input:
    path all_faa

    output:
    path all_faa, emit: all_faa
    path "pangenome_families.tsv.gz", emit: pangenome_families
    path "collection_metadata.yml", emit: metadata
    path "pangenome_api_ids.tsv", emit: pangenome_api_ids
    val params.test_release_id, emit: collection_release_id
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

    family_count=\$(awk 'substr(\$0, 1, 1) == ">" { count++ } END { print count + 0 }' ${all_faa})
    gzip -n -f pangenome_families.tsv

    cat > collection_metadata.yml <<-END_METADATA
    input_mode: test_data
    release_id: "${params.test_release_id}"
    input_fasta: "${params.test_data}"
    pangenome_count: 1
    family_count: "\${family_count}"
    END_METADATA

    printf 'Local_pangenome_name\\tPangenome_id\\n' > pangenome_api_ids.tsv
    printf 'test_data\\t1\\n' >> pangenome_api_ids.tsv

    cat <<-END_VERSIONS > versions_prepare_direct_input.yml
    "${task.process}":
        awk: \$(awk --version 2>/dev/null | head -n 1 || echo unknown)
    END_VERSIONS
    """

    stub:
    """
    rm -f ${all_faa}
    printf '>stub_family_1\\nMKTAYIAKQRQISFVKSHFSRQ\\n' > ${all_faa}
    printf '>stub_family_2\\nMKTAYIAKQRQISFVKSHFSRQ\\n' >> ${all_faa}
    printf '>stub_family_3\\nGAVLILALLAVAGALAAPAA\\n' >> ${all_faa}
    printf '>stub_family_4\\nGAVLILALLAVAGALAAPAA\\n' >> ${all_faa}

    printf 'Pangenome_id\\tPangenome_family_id\\n' > pangenome_families.tsv
    printf '1\\tstub_family_1\\n' >> pangenome_families.tsv
    printf '1\\tstub_family_2\\n' >> pangenome_families.tsv
    printf '1\\tstub_family_3\\n' >> pangenome_families.tsv
    printf '1\\tstub_family_4\\n' >> pangenome_families.tsv
    gzip -n -f pangenome_families.tsv

    cat > collection_metadata.yml <<-END_METADATA
    input_mode: test_data_stub
    release_id: "${params.test_release_id}"
    input_fasta: "${params.test_data}"
    pangenome_count: 1
    family_count: "4"
    END_METADATA

    printf 'Local_pangenome_name\\tPangenome_id\\n' > pangenome_api_ids.tsv
    printf 'test_data\\t1\\n' >> pangenome_api_ids.tsv

    cat <<-END_VERSIONS > versions_prepare_direct_input.yml
    "${task.process}":
        awk: "stub"
    END_VERSIONS
    """
}
