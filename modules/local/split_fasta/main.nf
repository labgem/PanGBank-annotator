process SPLIT_FASTA {
    tag "$meta.id"
    label "process_low"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.panannotator_container : params.panannotator_container}"
    publishDir "${params.outdir}/annotation/raw/amrfinder/chunks", mode: "copy", enabled: false

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("chunks/*.faa"), emit: chunks
    path "versions_split_fasta_${meta.id}.yml", emit: versions

    script:
    """
    set -euo pipefail
    mkdir -p chunks

    input_faa=input.faa
    if [[ "${fasta}" == *.gz ]]; then
        gzip -c -d "${fasta}" > "\$input_faa"
    else
        cp "${fasta}" "\$input_faa"
    fi

    awk -v outdir="chunks" -v chunk_size="${params.annotation_chunk_size}" '
      BEGIN { seq_count = 0; chunk_id = 0; out = "" }
      /^>/ {
        if (seq_count % chunk_size == 0) {
          if (out != "") close(out)
          chunk_id++
          out = sprintf("%s/%s_chunk_%05d.faa", outdir, "${meta.id}", chunk_id)
        }
        seq_count++
      }
      {
        if (out == "") {
          chunk_id = 1
          out = sprintf("%s/%s_chunk_%05d.faa", outdir, "${meta.id}", chunk_id)
        }
        print >> out
      }
      END {
        if (out != "") close(out)
      }
    ' "\$input_faa"

    {
        printf '"%s":\n' "${task.process}"
        printf '    awk: "%s"\n' "\$(awk --version 2>/dev/null | head -n 1 || echo unknown)"
    } > versions_split_fasta_${meta.id}.yml
    """
}
