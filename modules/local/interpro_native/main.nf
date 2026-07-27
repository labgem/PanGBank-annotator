process INTERPRO_NATIVE {
    tag "$meta.id"
    label "process_high"
    conda "${projectDir}/modules/local/envs/hmmer/environment.yml"

    publishDir "${params.outdir}/annotation/raw/interpro/native", mode: "copy", enabled: params.keep_raw_annotations, saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("${meta.id}.interpro.tsv.gz"), emit: tsv
    path "*.domtblout.gz", optional: true, emit: domtblout
    path "*.hmmsearch.out.gz", optional: true, emit: search_logs
    path "versions_interpro_native_${meta.id}.yml", emit: versions

    script:
    def apps = params.interpro_apps.toString().split(',').collect { it.trim().toLowerCase() }.findAll { it }
    def run_pfam = apps.contains("pfam")
    def run_ncbifam = apps.contains("ncbifam")
    def invalid_apps = apps.findAll { !["pfam", "ncbifam"].contains(it) }
    if (invalid_apps) {
        error "Native InterPro mode supports only Pfam and NCBIFAM. Unsupported app(s): ${invalid_apps.join(', ')}"
    }
    def pfam_cmd = run_pfam
        ? "hmmsearch -Z 61295632 --cut_ga --cpu ${task.cpus} --domtblout pfam.domtblout ${params.interproscan6_datadir}/pfam/${params.interpro_pfam_version}/pfam_a.hmm ${fasta} > pfam.hmmsearch.out"
        : "rm -f pfam.domtblout pfam.hmmsearch.out"
    def ncbifam_cmd = run_ncbifam
        ? "hmmsearch -Z 61295632 --cut_tc --cpu ${task.cpus} --domtblout ncbifam.domtblout ${params.interproscan6_datadir}/ncbifam/${params.interpro_ncbifam_version}/ncbifam.hmm ${fasta} > ncbifam.hmmsearch.out"
        : "rm -f ncbifam.domtblout ncbifam.hmmsearch.out"
    """
    set -euo pipefail

    ${pfam_cmd}
    ${ncbifam_cmd}

    ${projectDir}/bin/parse_interpro_hmmer_domtblout.py \\
        --pfam-domtblout pfam.domtblout \\
        --ncbifam-domtblout ncbifam.domtblout \\
        --pfam-dat "${params.interproscan6_datadir}/pfam/${params.interpro_pfam_version}/pfam_a.dat" \\
        --ncbifam-hmm "${params.interproscan6_datadir}/ncbifam/${params.interpro_ncbifam_version}/ncbifam.hmm" \\
        --entries-json "${params.interproscan6_datadir}/interpro/${params.interproscan6_interpro_version}/entries.json" \\
        --out "${meta.id}.interpro.tsv"

    for raw_file in pfam.domtblout pfam.hmmsearch.out ncbifam.domtblout ncbifam.hmmsearch.out "${meta.id}.interpro.tsv"; do
        if [[ -f "\$raw_file" ]]; then
            gzip -f "\$raw_file"
        fi
    done

    {
        printf '"%s":\n' "${task.process}"
        printf '    hmmer: "%s"\n' "\$(hmmsearch -h | awk 'NR==2 {print \$3}')"
        printf '    pfam: "%s"\n' "${params.interpro_pfam_version}"
        printf '    ncbifam: "%s"\n' "${params.interpro_ncbifam_version}"
        printf '    interpro: "%s"\n' "${params.interproscan6_interpro_version}"
    } > versions_interpro_native_${meta.id}.yml
    """

    stub:
    """
    cat > "${meta.id}.interpro.tsv" <<'EOF'
PANFAM_80_rtest_000001			Pfam	PF00001	Stub family	1	10	1e-10	T		IPR000001	Stub InterPro	stub
EOF
    gzip -f "${meta.id}.interpro.tsv"

    {
        printf '"%s":\n' "${task.process}"
        printf '    hmmer: "stub"\n'
        printf '    pfam: "stub"\n'
        printf '    ncbifam: "stub"\n'
        printf '    interpro: "stub"\n'
    } > versions_interpro_native_${meta.id}.yml
    """
}
