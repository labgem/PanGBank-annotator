/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { CLUSTERING  } from '../subworkflows/local/clustering/main'
include { ANNOTATION  } from '../subworkflows/local/annotation/main'
include { MULTIQC     } from '../modules/nf-core/multiqc/main'
include { COLLATE_SOFTWARE_VERSIONS as COLLATE_ALL_SOFTWARE_VERSIONS } from '../modules/local/collate_software_versions/main'
include { VALIDATE_DATABASES } from '../modules/local/validate_databases/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PANANNOTATOR {

    main:

    ch_versions = channel.empty()
    ch_multiqc_report = channel.empty()
    ch_software_versions = channel.empty()
    ch_multiqc_files = channel.empty()
    ch_database_manifest = channel.empty()

    run_clustering = params.run_clustering.toString() == 'true'
    run_annotation = params.run_annotation.toString() == 'true'

    if (!run_clustering && !run_annotation) {
        error "At least one stage must be enabled with --run_clustering true or --run_annotation true."
    }

    if (run_clustering) {
        CLUSTERING()
        ch_versions = ch_versions.mix(CLUSTERING.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(CLUSTERING.out.multiqc)
    }

    if (run_annotation) {
        if (!run_clustering) {
            error "Annotation-only mode needs published PANFAM inputs and is not implemented yet. Run clustering and annotation together for now."
        }
        VALIDATE_DATABASES()
        ch_database_manifest = VALIDATE_DATABASES.out.manifest
        ANNOTATION(CLUSTERING.out.panfam, CLUSTERING.out.all_faa, CLUSTERING.out.pangenome_families, ch_database_manifest)
        ch_versions = ch_versions.mix(ANNOTATION.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(ANNOTATION.out.multiqc)
    }

    COLLATE_ALL_SOFTWARE_VERSIONS(ch_versions.collect())
    ch_software_versions = COLLATE_ALL_SOFTWARE_VERSIONS.out.versions

    ch_multiqc_input = ch_multiqc_files
        .collect()
        .map { multiqc_files ->
            tuple([id: 'panannotator'], multiqc_files, file("${projectDir}/assets/multiqc_config.yml"), [], [], [])
        }
    MULTIQC(ch_multiqc_input)
    ch_multiqc_report = MULTIQC.out.report.map { meta, report -> report }

    emit:
    panfam = CLUSTERING.out.panfam
    all_faa = CLUSTERING.out.all_faa
    pangenome_families = CLUSTERING.out.pangenome_families
    corrected_clusters = CLUSTERING.out.corrected_clusters
    annotation_global_parquet = run_annotation ? ANNOTATION.out.global_parquet : channel.empty()
    annotation_pangenome_parquet = run_annotation ? ANNOTATION.out.pangenome_parquet : channel.empty()
    software_versions = ch_software_versions
    database_manifest = ch_database_manifest
    multiqc_report = ch_multiqc_report
    versions = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
