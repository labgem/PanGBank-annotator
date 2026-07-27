include { PREPARE_ANNOTATION_INPUT as PREPARE_PANFAM80_ANNOTATION_INPUT } from '../../../modules/local/prepare_annotation_input/main'
include { PREPARE_ANNOTATION_INPUT as PREPARE_ALL_PROTEIN_ANNOTATION_INPUT } from '../../../modules/local/prepare_annotation_input/main'
include { PREP_INPUT } from '../../../modules/local/preprocess/main'
include { INTERPRO_NATIVE } from '../../../modules/local/interpro_native/main'
include { INTERPROSCAN6_IMPORTED } from '../interproscan6_imported/main'
include { DEEPKOALA } from '../../../modules/local/deepkoala/main'
include { EGGNOGMAPPER } from '../../../modules/nf-core/eggnogmapper/main'
include { PARSE_EGGNOG } from '../../../modules/local/parse_eggnog_nfcore/main'
include { SPLIT_FASTA as SPLIT_PANFAM80_FASTA } from '../../../modules/local/split_fasta/main'
include { SPLIT_FASTA as SPLIT_ALL_PROTEIN_FASTA } from '../../../modules/local/split_fasta/main'
include { AMRFINDER } from '../../../modules/local/amrfinder/main'
include { PACKAGE_INTERPRO_ANNOTATIONS } from '../../../modules/local/package_interpro_annotations/main'
include { PACKAGE_ANNOTATIONS as PACKAGE_DEEPKOALA_ANNOTATIONS } from '../../../modules/local/package_annotations/main'
include { PACKAGE_ANNOTATIONS as PACKAGE_EGGNOG_ANNOTATIONS } from '../../../modules/local/package_annotations/main'
include { PACKAGE_ANNOTATIONS as PACKAGE_AMRFINDER_ANNOTATIONS } from '../../../modules/local/package_annotations/main'
include { REPORT_ANNOTATIONS } from '../../../modules/local/report_annotations/main'

workflow ANNOTATION {
    take:
    panfam_dir
    all_faa
    pangenome_families
    database_manifest

    main:
    def requested_tools = params.annotation_tools instanceof List
        ? params.annotation_tools.collect { it.toString().trim().toLowerCase() }.findAll { it }
        : params.annotation_tools.toString().split(',').collect { it.trim().toLowerCase() }.findAll { it }

    if (!requested_tools) {
        error "--annotation_tools must contain at least one tool when --run_annotation true"
    }

    def allowed_tools = ["interpro", "deepkoala", "eggnog", "amrfinder"]
    def invalid_tools = requested_tools.findAll { !allowed_tools.contains(it) }
    if (invalid_tools) {
        error "Unsupported annotation tool(s): ${invalid_tools.join(', ')}. Allowed values: ${allowed_tools.join(', ')}"
    }

    def all_protein_tools = params.all_protein_tools instanceof List
        ? params.all_protein_tools.collect { it.toString().trim().toLowerCase() }.findAll { it && it != "none" }
        : params.all_protein_tools.toString().split(',').collect { it.trim().toLowerCase() }.findAll { it && it != "none" }

    all_protein_tools = all_protein_tools.findAll { requested_tools.contains(it) }

    def panfam80_tools = requested_tools.findAll { !all_protein_tools.contains(it) }
    def cluster_levels = params.levels instanceof List
        ? params.levels.collect { it.toString().trim() }
        : params.levels.toString().split(',').collect { it.trim() }.findAll { it }
    if (panfam80_tools && !cluster_levels.contains("80")) {
        error "Annotation defaults to PANFAM_80 for ${panfam80_tools.join(', ')}, but --levels does not include 80."
    }

    ch_versions = channel.empty()
    ch_global_parquet = channel.empty()
    ch_pangenome_parquet = channel.empty()

    if (panfam80_tools) {
        PREPARE_PANFAM80_ANNOTATION_INPUT(panfam_dir, all_faa, "panfam_80")
        ch_versions = ch_versions.mix(PREPARE_PANFAM80_ANNOTATION_INPUT.out.versions)

        PREP_INPUT(PREPARE_PANFAM80_ANNOTATION_INPUT.out.fasta)
        ch_prepped = PREP_INPUT.out.combine(database_manifest).map { clean_faa, proteins, manifest ->
            tuple("panfam80", clean_faa, proteins)
        }
        ch_panfam80_chunks = channel.empty()
        ch_panfam80_chunk_meta = channel.empty()
        def needs_panfam80_chunks = panfam80_tools.any { tool ->
            tool in ["deepkoala", "eggnog"] || (tool == "interpro" && params.interpro_mode == "native")
        }
        if (needs_panfam80_chunks) {
            SPLIT_PANFAM80_FASTA(ch_prepped.map { sample_id, faa, proteins -> tuple([id: sample_id], faa) })
            ch_versions = ch_versions.mix(SPLIT_PANFAM80_FASTA.out.versions)
            ch_panfam80_proteins = ch_prepped.map { sample_id, faa, proteins -> proteins }
            ch_panfam80_chunks = SPLIT_PANFAM80_FASTA.out.chunks
                .combine(ch_panfam80_proteins)
                .flatMap { meta, chunks, proteins ->
                    def chunk_files = chunks instanceof List ? chunks : [chunks]
                    chunk_files.collect { chunk -> tuple(chunk.baseName, chunk, proteins) }
                }
            ch_panfam80_chunk_meta = ch_panfam80_chunks.map { sample_id, faa, proteins -> tuple([id: sample_id], faa, proteins) }
        }

        if (requested_tools.contains("interpro") && !all_protein_tools.contains("interpro")) {
            def normalize_interpro_app = { value ->
                value.toString().trim().toLowerCase().replaceAll(/[-_ ]/, "")
            }
            def interpro_app_aliases = [
                antifam: "antifam",
                cathgene3d: "cathgene3d",
                gene3d: "cathgene3d",
                cathfunfam: "cathfunfam",
                funfam: "cathfunfam",
                cdd: "cdd",
                coils: "coils",
                deeptmhmm: "deeptmhmm",
                hamap: "hamap",
                interpron: "interpro_n",
                mobidblite: "mobidblite",
                ncbifam: "ncbifam",
                panther: "panther",
                phobius: "phobius",
                pfam: "pfam",
                pirsf: "pirsf",
                pirsr: "pirsr",
                prints: "prints",
                prositepatterns: "prositepatterns",
                prositeprofiles: "prositeprofiles",
                sfld: "sfld",
                signalpeuk: "signalp_euk",
                signalpprok: "signalp_prok",
                smart: "smart",
                superfamily: "superfamily",
                tmbed: "tmbed",
            ]
            def interpro_apps = params.interpro_apps.toString().split(',').collect { raw_app ->
                def app_name = interpro_app_aliases[normalize_interpro_app(raw_app)]
                if (!app_name) {
                    error "Unsupported InterProScan 6 application '${raw_app}'. Allowed values: ${interpro_app_aliases.values().unique().sort().join(', ')}"
                }
                app_name
            }.findAll { it }.unique()
            if (params.interpro_mode == "native") {
                def unsupported_native_apps = interpro_apps.findAll { !(it in ["pfam", "ncbifam"]) }
                if (unsupported_native_apps) {
                    error "--interpro_mode native supports only Pfam and NCBIFAM. Use --interpro_mode imported for: ${unsupported_native_apps.join(', ')}"
                }
                INTERPRO_NATIVE(ch_panfam80_chunks.map { sample_id, faa, proteins -> tuple([id: sample_id], faa) })
                ch_interpro_tsv = INTERPRO_NATIVE.out.tsv
                ch_versions = ch_versions.mix(INTERPRO_NATIVE.out.versions)
            } else if (params.interpro_mode == "imported") {
                def container_engine = workflow.containerEngine?.toString()
                def using_local_tools = workflow.profile.tokenize(',').contains('local_tools')
                if (!using_local_tools && !["docker", "singularity", "apptainer", "podman"].contains(container_engine)) {
                    error "--interpro_mode imported requires a container profile such as singularity, apptainer, or docker. Use --interpro_mode native with -profile conda."
                }
                INTERPROSCAN6_IMPORTED(ch_prepped.map { sample_id, faa, proteins -> tuple([id: sample_id], faa) })
                ch_interpro_tsv = INTERPROSCAN6_IMPORTED.out.tsv
                ch_versions = ch_versions.mix(INTERPROSCAN6_IMPORTED.out.versions)
            } else {
                error "--interpro_mode must be either 'native' or 'imported'"
            }
            PACKAGE_INTERPRO_ANNOTATIONS(
                interpro_apps.join(','),
                "panfam_80",
                ch_interpro_tsv.map { meta, tsv -> tsv }.collect(),
                panfam_dir,
                pangenome_families
            )
            ch_versions = ch_versions.mix(PACKAGE_INTERPRO_ANNOTATIONS.out.versions)
            ch_global_parquet = ch_global_parquet.mix(PACKAGE_INTERPRO_ANNOTATIONS.out.global.flatten())
            ch_pangenome_parquet = ch_pangenome_parquet.mix(PACKAGE_INTERPRO_ANNOTATIONS.out.pangenomes.flatten())
        }

        if (requested_tools.contains("deepkoala") && !all_protein_tools.contains("deepkoala")) {
            DEEPKOALA(ch_panfam80_chunks)
            PACKAGE_DEEPKOALA_ANNOTATIONS(
                "deepkoala",
                "panfam_80",
                DEEPKOALA.out.tsv.map { sample_id, tsv -> tsv }.collect(),
                panfam_dir,
                pangenome_families
            )
            ch_versions = ch_versions.mix(DEEPKOALA.out.versions).mix(PACKAGE_DEEPKOALA_ANNOTATIONS.out.versions)
            ch_global_parquet = ch_global_parquet.mix(PACKAGE_DEEPKOALA_ANNOTATIONS.out.global)
            ch_pangenome_parquet = ch_pangenome_parquet.mix(PACKAGE_DEEPKOALA_ANNOTATIONS.out.pangenomes)
        }

        if (requested_tools.contains("eggnog") && !all_protein_tools.contains("eggnog")) {
            EGGNOGMAPPER(
                ch_panfam80_chunk_meta.map { meta, faa, proteins -> tuple(meta, faa) },
                channel.value(tuple(params.eggnog_search_mode, file(params.eggnog_mapper_db))),
                channel.value(file(params.eggnog_data_dir))
            )
            PARSE_EGGNOG(EGGNOGMAPPER.out.annotations)
            PACKAGE_EGGNOG_ANNOTATIONS(
                "eggnog",
                "panfam_80",
                PARSE_EGGNOG.out.map { sample_id, tsv -> tsv }.collect(),
                panfam_dir,
                pangenome_families
            )
            ch_versions = ch_versions.mix(PACKAGE_EGGNOG_ANNOTATIONS.out.versions)
            ch_global_parquet = ch_global_parquet.mix(PACKAGE_EGGNOG_ANNOTATIONS.out.global)
            ch_pangenome_parquet = ch_pangenome_parquet.mix(PACKAGE_EGGNOG_ANNOTATIONS.out.pangenomes)
        }
    }

    if (all_protein_tools) {
        PREPARE_ALL_PROTEIN_ANNOTATION_INPUT(panfam_dir, all_faa, "all_proteins")
        ch_versions = ch_versions.mix(PREPARE_ALL_PROTEIN_ANNOTATION_INPUT.out.versions)
        ch_all_meta = PREPARE_ALL_PROTEIN_ANNOTATION_INPUT.out.fasta.combine(database_manifest).map { faa, manifest -> tuple([id: "all_proteins"], faa) }

        if (requested_tools.contains("amrfinder") && all_protein_tools.contains("amrfinder")) {
            SPLIT_ALL_PROTEIN_FASTA(ch_all_meta)
            ch_amr_chunks = SPLIT_ALL_PROTEIN_FASTA.out.chunks.flatMap { meta, chunks ->
                def chunk_files = chunks instanceof List ? chunks : [chunks]
                chunk_files.collect { chunk -> tuple([id: chunk.baseName], chunk) }
            }
            AMRFINDER(ch_amr_chunks)
            PACKAGE_AMRFINDER_ANNOTATIONS(
                "amrfinder",
                "all_proteins",
                AMRFINDER.out.tsv.map { meta, tsv -> tsv }.collect(),
                panfam_dir,
                pangenome_families
            )
            ch_versions = ch_versions.mix(SPLIT_ALL_PROTEIN_FASTA.out.versions).mix(AMRFINDER.out.versions).mix(PACKAGE_AMRFINDER_ANNOTATIONS.out.versions)
            ch_global_parquet = ch_global_parquet.mix(PACKAGE_AMRFINDER_ANNOTATIONS.out.global)
            ch_pangenome_parquet = ch_pangenome_parquet.mix(PACKAGE_AMRFINDER_ANNOTATIONS.out.pangenomes)
        }
    }

    REPORT_ANNOTATIONS(ch_global_parquet.collect(), pangenome_families)
    ch_versions = ch_versions.mix(REPORT_ANNOTATIONS.out.versions)

    emit:
    global_parquet = ch_global_parquet
    pangenome_parquet = ch_pangenome_parquet
    multiqc = REPORT_ANNOTATIONS.out.multiqc
    report_tables = REPORT_ANNOTATIONS.out.tables
    report_plots = REPORT_ANNOTATIONS.out.plots
    versions = ch_versions
}
