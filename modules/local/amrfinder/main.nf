process AMRFINDER {
    tag "$meta.id"
    label "process_high"
    conda "${projectDir}/modules/local/envs/amrfinder/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.amrfinder_container : params.amrfinder_container}"

    publishDir "${params.outdir}/annotation/raw/amrfinder", mode: "copy", enabled: params.keep_raw_annotations, saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    tuple val(meta), path(fasta)
    path amrfinder_db

    output:
    tuple val(meta), path("${meta.id}.amrfinder.tsv.gz"), emit: tsv
    path "versions_amrfinder_${meta.id}.yml", emit: versions

    script:
    """
    set -euo pipefail

    AMRFINDER_DB="${amrfinder_db}"
    if [[ -n "\$AMRFINDER_DB" && ! -f "\$AMRFINDER_DB/AMRProt.fa.phr" && -f "\$AMRFINDER_DB/latest/AMRProt.fa.phr" ]]; then
        AMRFINDER_DB="\$AMRFINDER_DB/latest"
    fi

    DB_ARG=()
    if [[ -n "\$AMRFINDER_DB" ]]; then
        DB_ARG=(--database "\$AMRFINDER_DB")
    fi

    amrfinder -p "${fasta}" \\
        --threads "${task.cpus}" \\
        "\${DB_ARG[@]}" \\
        -o "${meta.id}.amrfinder.tsv"

    gzip -f "${meta.id}.amrfinder.tsv"

    {
        printf '"%s":\n' "${task.process}"
        printf '    amrfinder: "%s"\n' "\$(amrfinder --version 2>&1 | head -n 1 | sed 's/^AMRFinderPlus //')"
    } > versions_amrfinder_${meta.id}.yml
    """

    stub:
    """
    cat > "${meta.id}.amrfinder.tsv" <<'EOF'
Protein identifier	Contig id	Start	Stop	Strand	Gene symbol	Element symbol	Sequence name	Scope	Element type	Element subtype	Class	Subclass	Method	Target length	Reference sequence length	% Coverage of reference sequence	% Identity to reference sequence	Alignment length	Accession of closest sequence	Name of closest sequence	HMM id	HMM description
stub_family_1	NA	1	10	+	blaSTUB	blaSTUB	stub	plus	AMR	NA	BETA-LACTAM	NA	EXACT	10	10	100	100	10	NA	NA	NA	NA
EOF
    gzip -f "${meta.id}.amrfinder.tsv"

    {
        printf '"%s":\n' "${task.process}"
        printf '    amrfinder: "stub"\n'
    } > versions_amrfinder_${meta.id}.yml
    """
}
