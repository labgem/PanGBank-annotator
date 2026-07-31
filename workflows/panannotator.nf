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

workflow PANGBANK_ANNOTATOR {

    main:

    ch_versions = channel.empty()
    ch_multiqc_report = channel.empty()
    ch_software_versions = channel.empty()
    ch_multiqc_files = channel.empty()
    ch_database_manifest = channel.empty()
    ch_panfam = channel.empty()
    ch_annotation_panfam = channel.empty()
    ch_all_faa = channel.empty()
    ch_pangenome_families = channel.empty()
    ch_corrected_clusters = channel.empty()

    run_clustering = params.run_clustering.toString() == 'true'
    run_annotation = params.run_annotation.toString() == 'true'

    if (!run_clustering && !run_annotation) {
        error "At least one stage must be enabled with --run_clustering true or --run_annotation true."
    }

    if (run_clustering) {
        CLUSTERING()
        ch_versions = ch_versions.mix(CLUSTERING.out.versions)
        ch_multiqc_files = ch_multiqc_files.mix(CLUSTERING.out.multiqc)
        ch_panfam = CLUSTERING.out.panfam
        ch_all_faa = CLUSTERING.out.all_faa
        ch_pangenome_families = CLUSTERING.out.pangenome_families
        ch_corrected_clusters = CLUSTERING.out.corrected_clusters
        ch_annotation_panfam = CLUSTERING.out.annotation_panfam
    } else if (run_annotation) {
        if (!params.outdir) {
            error "Annotation-only mode requires --outdir pointing to an existing panAnnotator result."
        }
        clustering_dir = "${params.outdir}/clustering"
        all_faa = "${params.outdir}/inputs/all_protein_families.faa.gz"
        pangenome_families = "${params.outdir}/inputs/pangenome_families.tsv.gz"

        ch_panfam = Channel.fromPath(clustering_dir, checkIfExists: true)
        ch_annotation_panfam = ch_panfam
        ch_all_faa = Channel.fromPath(all_faa, checkIfExists: true)
        ch_pangenome_families = Channel.fromPath(pangenome_families, checkIfExists: true)
        ch_multiqc_files = ch_multiqc_files.mix(
            Channel.fromPath("${params.outdir}/report/clustering/custom_content/*_mqc.yaml", checkIfExists: false)
        )
    }

    if (run_annotation) {
        VALIDATE_DATABASES()
        ch_database_manifest = VALIDATE_DATABASES.out.manifest
        ANNOTATION(ch_annotation_panfam, ch_all_faa, ch_pangenome_families, ch_database_manifest)
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
    panfam = ch_panfam
    all_faa = ch_all_faa
    pangenome_families = ch_pangenome_families
    corrected_clusters = ch_corrected_clusters
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
