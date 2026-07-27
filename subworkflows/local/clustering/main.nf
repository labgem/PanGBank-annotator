include { FETCH_PANGBANK_COLLECTION } from '../../../modules/local/fetch_pangbank_collection/main'
include { PREPARE_DIRECT_INPUT } from '../../../modules/local/prepare_direct_input/main'
include { DIAMOND_MAKEDB } from '../../../modules/local/diamond_makedb/main'
include { DIAMOND_DEEPCLUST } from '../../../modules/local/diamond_deepclust/main'
include { DIAMOND_RECLUSTER } from '../../../modules/local/diamond_recluster/main'
include { DIAMOND_REASSIGN } from '../../../modules/local/diamond_reassign/main'
include { PACKAGE_PANFAM as PACKAGE_PANFAM_FINAL } from '../../../modules/local/package_panfam/main'
include { PACKAGE_PANFAM as PACKAGE_PANFAM_FOR_ANNOTATION } from '../../../modules/local/package_panfam/main'

workflow CLUSTERING {
    main:
    def cluster_levels = params.levels instanceof List
        ? params.levels
        : params.levels.toString().split(',').collect { it.trim() }.findAll { it }
    def scheduled_levels = params.run_annotation.toString() == 'true' && cluster_levels.contains("80")
        ? ["80"] + cluster_levels.findAll { it != "80" }
        : cluster_levels

    levels_ch = Channel.from(scheduled_levels).map { level ->
        def approx = level == "deep" ? params.deep_approx_id : level
        tuple(level, approx as Integer)
    }

    if (params.test_data) {
        PREPARE_DIRECT_INPUT(Channel.fromPath(params.test_data, checkIfExists: true))
        ch_all_faa = PREPARE_DIRECT_INPUT.out.all_faa
        ch_pangenome_families = PREPARE_DIRECT_INPUT.out.pangenome_families
        ch_collection_release_id = PREPARE_DIRECT_INPUT.out.collection_release_id
        input_versions = PREPARE_DIRECT_INPUT.out.versions
    } else {
        FETCH_PANGBANK_COLLECTION()
        ch_all_faa = FETCH_PANGBANK_COLLECTION.out.all_faa
        ch_pangenome_families = FETCH_PANGBANK_COLLECTION.out.pangenome_families
        ch_collection_release_id = FETCH_PANGBANK_COLLECTION.out.collection_release_id.map { it.trim() }
        input_versions = FETCH_PANGBANK_COLLECTION.out.versions
    }

    DIAMOND_MAKEDB(ch_all_faa)

    deepclust_input_ch = levels_ch
        .combine(DIAMOND_MAKEDB.out.db)
        .map { level, approx, db -> tuple(level, approx, db) }
    DIAMOND_DEEPCLUST(deepclust_input_ch)

    run_cluster_correction = params.run_cluster_correction.toString() == 'true'
    ch_correction_versions = channel.empty()
    if (run_cluster_correction) {
        recluster_input_ch = DIAMOND_DEEPCLUST.out.clusters
            .combine(DIAMOND_MAKEDB.out.db)
            .map { level, clusters, db -> tuple(level, clusters, db) }
        DIAMOND_RECLUSTER(recluster_input_ch)

        reassign_input_ch = DIAMOND_RECLUSTER.out.clusters
            .combine(DIAMOND_MAKEDB.out.db)
            .map { level, clusters, db -> tuple(level, clusters, db) }
        DIAMOND_REASSIGN(reassign_input_ch)
        corrected_tables_ch = DIAMOND_REASSIGN.out.clusters
        ch_correction_versions = DIAMOND_RECLUSTER.out.versions.mix(DIAMOND_REASSIGN.out.versions)
    } else {
        corrected_tables_ch = DIAMOND_DEEPCLUST.out.clusters
    }

    raw_tables_ch = DIAMOND_DEEPCLUST.out.clusters.map { level, file -> file }
    corrected_files_ch = corrected_tables_ch.map { level, file -> file }
    package_tables_ch = run_cluster_correction
        ? raw_tables_ch.mix(corrected_files_ch).collect()
        : raw_tables_ch.collect()

    ch_annotation_panfam = channel.empty()
    if (params.run_annotation.toString() == 'true' && cluster_levels.contains("80")) {
        corrected_80_ch = corrected_tables_ch
            .filter { level, file -> level == "80" }
            .map { level, file -> file }
        PACKAGE_PANFAM_FOR_ANNOTATION(
            ch_all_faa,
            ch_pangenome_families,
            ch_collection_release_id,
            corrected_80_ch,
            "80",
            "panfam80",
            true
        )
        ch_annotation_panfam = PACKAGE_PANFAM_FOR_ANNOTATION.out.panfam
    }

    PACKAGE_PANFAM_FINAL(
        ch_all_faa,
        ch_pangenome_families,
        ch_collection_release_id,
        package_tables_ch,
        cluster_levels,
        "clustering",
        false
    )

    if (params.run_annotation.toString() == 'true' && !cluster_levels.contains("80")) {
        ch_annotation_panfam = PACKAGE_PANFAM_FINAL.out.panfam
    }

    ch_versions = input_versions
        .mix(DIAMOND_MAKEDB.out.versions)
        .mix(DIAMOND_DEEPCLUST.out.versions)
        .mix(ch_correction_versions)
        .mix(PACKAGE_PANFAM_FINAL.out.versions)

    emit:
    panfam = PACKAGE_PANFAM_FINAL.out.panfam
    annotation_panfam = ch_annotation_panfam
    multiqc = PACKAGE_PANFAM_FINAL.out.multiqc
    all_faa = ch_all_faa
    pangenome_families = ch_pangenome_families
    corrected_clusters = corrected_tables_ch
    versions = ch_versions
}
