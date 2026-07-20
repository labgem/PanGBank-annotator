/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { CLUSTERING } from '../subworkflows/clustering/main'
include { MULTIQC    } from '../modules/nf-core/multiqc/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PANANNOTATOR {

    main:

    ch_versions = channel.empty()
    ch_multiqc_report = channel.empty()

    if (params.run_clustering.toString() == 'true') {
        CLUSTERING()
        ch_versions = ch_versions.mix(CLUSTERING.out.versions)

        ch_multiqc_input = CLUSTERING.out.multiqc
            .collect()
            .combine(Channel.fromPath("${projectDir}/assets/multiqc_config.yml", checkIfExists: true))
            .map { multiqc_files, multiqc_config ->
                tuple([id: 'panannotator'], multiqc_files, multiqc_config, [], [], [])
            }
        MULTIQC(ch_multiqc_input)
        ch_multiqc_report = MULTIQC.out.report.map { meta, report -> report }
    } else {
        error "At least one stage must be enabled. Currently only --run_clustering true is implemented."
    }

    emit:
    panfam = CLUSTERING.out.panfam
    all_faa = CLUSTERING.out.all_faa
    pangenome_families = CLUSTERING.out.pangenome_families
    corrected_clusters = CLUSTERING.out.corrected_clusters
    multiqc_report = ch_multiqc_report
    versions = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
