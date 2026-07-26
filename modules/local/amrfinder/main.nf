process AMRFINDER {
    tag "$meta.id"
    label "process_high"
    conda "${projectDir}/modules/local/envs/amrfinder/environment.yml"

    publishDir "${params.outdir}/annotation/raw/amrfinder", mode: "copy", enabled: params.keep_raw_annotations, saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}.amrfinder.tsv.gz"), emit: tsv
    path "versions_amrfinder.yml", emit: versions

    script:
    def db_arg = params.amrfinder_db ? "--database \"${params.amrfinder_db}\"" : ""
    """
    set -euo pipefail

    amrfinder -p "${fasta}" \\
        --threads "${task.cpus}" \\
        ${db_arg} \\
        -o "${meta.id}.amrfinder.tsv"

    gzip -f "${meta.id}.amrfinder.tsv"

    {
        printf '"%s":\n' "${task.process}"
        printf '    amrfinder: "%s"\n' "\$(amrfinder --version 2>&1 | head -n 1 | sed 's/^AMRFinderPlus //')"
    } > versions_amrfinder.yml
    """

    stub:
    """
    cat > "${meta.id}.amrfinder.tsv" <<'EOF'
Protein identifier	Contig id	Start	Stop	Strand	Gene symbol	Sequence name	Scope	Element type	Element subtype	Class	Subclass	Method	Target length	Reference sequence length	% Coverage of reference sequence	% Identity to reference sequence	Alignment length	Accession of closest sequence	Name of closest sequence	HMM id	HMM description
tiny_mock_1	NA	1	10	+	blaSTUB	stub	plus	AMR	NA	BETA-LACTAM	NA	EXACT	10	10	100	100	10	NA	NA	NA	NA
EOF
    gzip -f "${meta.id}.amrfinder.tsv"

    {
        printf '"%s":\n' "${task.process}"
        printf '    amrfinder: "stub"\n'
    } > versions_amrfinder.yml
    """
}
