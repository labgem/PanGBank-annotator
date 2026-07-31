process PREP_INPUT {
    tag { faa.baseName }
    label "process_low"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.panannotator_container : params.panannotator_container}"
    publishDir "${params.outdir}/annotation/inputs/preprocessed", mode: "copy", enabled: false

    input:
    path faa

    output:
    tuple path("*.clean.faa"), path("*.proteins.tsv")

    script:
    """
    set -euo pipefail

    input_faa=input.faa
    if [[ "${faa}" == *.gz ]]; then
        gzip -c -d "${faa}" > "\$input_faa"
    else
        cp "${faa}" "\$input_faa"
    fi

    # InterProScan is strict about input characters. Remove stop codons and map
    # unsupported residues to X to keep pipeline runs robust on mixed FASTA inputs.
    awk 'BEGIN{valid="ACDEFGHIKLMNPQRSTVWYX"}
      /^>/ {print; next}
      {
        line=toupper(\$0)
        gsub(/[[:space:]]/,"",line)
        gsub(/[*]\$/,"",line)
        gsub(/[^ACDEFGHIKLMNPQRSTVWYX]/,"X",line)
        print line
      }
    ' "\$input_faa" > "${faa.baseName}.clean.faa"

    awk '
      /^>/ {
        hdr=substr(\$0,2)
        split(hdr, arr, /[[:space:]]+/)
        pid=arr[1]
        print pid"\t"hdr
      }
    ' "${faa.baseName}.clean.faa" > "${faa.baseName}.proteins.tsv"
    """

    stub:
    """
    if [[ "${faa}" == *.gz ]]; then
        gzip -c -d "${faa}" > "${faa.baseName}.clean.faa"
    else
        cp "${faa}" "${faa.baseName}.clean.faa"
    fi
    cat > "${faa.baseName}.proteins.tsv" <<EOF
    protein_id\theader
    tiny_mock_1\ttiny_mock_1 fake
    EOF
    """
}
