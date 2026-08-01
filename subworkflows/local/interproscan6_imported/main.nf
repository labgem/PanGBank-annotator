include { INTERPROSCAN } from '../../interproscan6/workflows/interproscan.nf'

workflow INTERPROSCAN6_IMPORTED {
    take:
    input_fasta

    main:
    def raw_apps_config = new ConfigSlurper().parse(
        new File("${projectDir}/subworkflows/interproscan6/conf/applications.config").toURI().toURL()
    ).params.appsConfig
    def apps_config = raw_apps_config.collectEntries { app_name, app_config ->
        [(app_name.toString().toLowerCase()): app_config]
    }
    def app_aliases = [:]
    apps_config.each { app_name, app_config ->
        app_aliases[app_name.toString().trim().toLowerCase().replaceAll(/[-_ ]/, "")] = app_name
        app_aliases[app_config.name.toString().trim().toLowerCase().replaceAll(/[-_ ]/, "")] = app_name
        (app_config.aliases ?: []).each { alias ->
            app_aliases[alias.toString().trim().toLowerCase().replaceAll(/[-_ ]/, "")] = app_name
        }
    }
    def apps = params.interpro_apps.toString().split(',').collect { raw_app ->
        def normalized = raw_app.toString().trim().toLowerCase().replaceAll(/[-_ ]/, "")
        def app_name = app_aliases[normalized]
        if (!app_name) {
            error "Unsupported InterProScan 6 application '${raw_app}'. Allowed values: ${apps_config.keySet().sort().join(', ')}"
        }
        app_name
    }.findAll { it }.unique()

    input_fasta
        .map { meta, fasta -> tuple(meta, fasta) }
        .set { ch_input }

    def imported_outprefix = "${workflow.workDir}/panfam80.interproscan6"

    INTERPROSCAN(
        ch_input.map { meta, fasta -> fasta },
        apps,
        apps_config,
        file(params.interproscan6_datadir),
        imported_outprefix,
        ["tsv"],
        params.interproscan6_interpro_version,
        params.interproscan6_version,
        "InterProScan6",
        params.interproscan6_no_matches_api,
        "https://www.ebi.ac.uk/interpro/matches/api",
        100,
        3,
        params.interproscan6_batch_size as Integer,
        params.interproscan6_sub_batch_size as Integer,
        false,
        false,
        false,
        false,
        false,
        !params.interproscan6_skip_version_check
    )

    INTERPROSCAN.out
        .flatten()
        .filter { it.name.endsWith(".tsv") || it.name.endsWith(".tsv.gz") }
        .map { tsv -> tuple([id: "panfam80"], file(tsv.toString())) }
        .set { ch_imported_tsv }

    NORMALIZE_INTERPROSCAN6_IMPORTED_OUTPUT(ch_imported_tsv)

    emit:
    tsv = NORMALIZE_INTERPROSCAN6_IMPORTED_OUTPUT.out.tsv
    versions = NORMALIZE_INTERPROSCAN6_IMPORTED_OUTPUT.out.versions
}

process NORMALIZE_INTERPROSCAN6_IMPORTED_OUTPUT {
    tag "$meta.id"
    label "process_low"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.panannotator_container : params.panannotator_container}"
    publishDir "${params.outdir}/annotation/raw/interpro/imported", mode: "copy", enabled: params.keep_raw_annotations, saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    tuple val(meta), path(tsv)

    output:
    tuple val(meta), path("${meta.id}.interproscan6.tsv.gz"), emit: tsv
    path "versions_interproscan6_imported.yml", emit: versions

    script:
    """
    set -euo pipefail
    if [[ "${tsv}" == *.gz ]]; then
        cp "${tsv}" "${meta.id}.interproscan6.tsv.gz"
    elif [[ "\$(readlink -f "${tsv}")" != "\$(readlink -f "${meta.id}.interproscan6.tsv" 2>/dev/null || true)" ]]; then
        cp "${tsv}" "${meta.id}.interproscan6.tsv"
        gzip -f "${meta.id}.interproscan6.tsv"
    else
        gzip -c "${tsv}" > "${meta.id}.interproscan6.tsv.gz"
    fi

    {
        printf '"%s":\n' "${task.process}"
        printf '    interproscan6: "%s"\n' "${params.interproscan6_version}"
        printf '    interpro: "%s"\n' "${params.interproscan6_interpro_version}"
    } > versions_interproscan6_imported.yml
    """
}
