include { FETCH_PANGBANK_COLLECTION } from '../../modules/local/fetch_pangbank_collection/main'
include { DIAMOND_MAKEDB } from '../../modules/local/diamond_makedb/main'
include { DIAMOND_DEEPCLUST } from '../../modules/local/diamond_deepclust/main'
include { DIAMOND_RECLUSTER } from '../../modules/local/diamond_recluster/main'
include { DIAMOND_REASSIGN } from '../../modules/local/diamond_reassign/main'
include { PACKAGE_PANFAM } from '../../modules/local/package_panfam/main'

workflow CLUSTERING {
    main:
    def cluster_levels = params.levels instanceof List
        ? params.levels
        : params.levels.toString().split(',').collect { it.trim() }.findAll { it }

    levels_ch = Channel.from(cluster_levels).map { level ->
        def approx = level == "deep" ? params.deep_approx_id : level
        tuple(level, approx as Integer)
    }

    FETCH_PANGBANK_COLLECTION()
    DIAMOND_MAKEDB(FETCH_PANGBANK_COLLECTION.out.all_faa)

    deepclust_input_ch = levels_ch
        .combine(DIAMOND_MAKEDB.out.db)
        .map { level, approx, db -> tuple(level, approx, db) }
    DIAMOND_DEEPCLUST(deepclust_input_ch)

    recluster_input_ch = DIAMOND_DEEPCLUST.out.clusters
        .combine(DIAMOND_MAKEDB.out.db)
        .map { level, clusters, db -> tuple(level, clusters, db) }
    DIAMOND_RECLUSTER(recluster_input_ch)

    reassign_input_ch = DIAMOND_RECLUSTER.out.clusters
        .combine(DIAMOND_MAKEDB.out.db)
        .map { level, clusters, db -> tuple(level, clusters, db) }
    DIAMOND_REASSIGN(reassign_input_ch)

    raw_tables_ch = DIAMOND_DEEPCLUST.out.clusters.map { level, file -> file }
    corrected_tables_ch = DIAMOND_REASSIGN.out.clusters.map { level, file -> file }
    package_tables_ch = raw_tables_ch.mix(corrected_tables_ch).collect()

    PACKAGE_PANFAM(
        FETCH_PANGBANK_COLLECTION.out.all_faa,
        FETCH_PANGBANK_COLLECTION.out.pangenome_families,
        FETCH_PANGBANK_COLLECTION.out.collection_release_id,
        package_tables_ch
    )

    emit:
    panfam = PACKAGE_PANFAM.out.panfam
    multiqc = PACKAGE_PANFAM.out.multiqc
    all_faa = FETCH_PANGBANK_COLLECTION.out.all_faa
    pangenome_families = FETCH_PANGBANK_COLLECTION.out.pangenome_families
    corrected_clusters = DIAMOND_REASSIGN.out.clusters
    versions = FETCH_PANGBANK_COLLECTION.out.versions
        .mix(DIAMOND_MAKEDB.out.versions)
        .mix(DIAMOND_DEEPCLUST.out.versions)
        .mix(DIAMOND_RECLUSTER.out.versions)
        .mix(DIAMOND_REASSIGN.out.versions)
        .mix(PACKAGE_PANFAM.out.versions)
}
