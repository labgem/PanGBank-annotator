process VALIDATE_DATABASES {
    tag "annotation_databases"
    label "process_single"
    conda "${projectDir}/modules/local/envs/database_setup/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.database_setup_container : params.database_setup_container}"

    publishDir "${params.outdir}/pipeline_info", mode: "copy"

    input:
    path interproscan6_datadir
    path deepkoala_resources
    path eggnog_data_dir
    path eggnog_mapper_db
    path amrfinder_db

    output:
    path "database_manifest.yml", emit: manifest

    script:
    def prepare_arg = params.prepare_databases.toString() == "true" ? "--prepare-databases" : ""
    def skip_arg = params.skip_db_validation.toString() == "true" ? "--skip-db-validation" : ""
    """
    set -euo pipefail

    ${projectDir}/bin/validate_databases.py \\
        --annotation-tools "${params.annotation_tools}" \\
        --all-protein-tools "${params.all_protein_tools}" \\
        --interpro-apps "${params.interpro_apps}" \\
        --interpro-mode "${params.interpro_mode}" \\
        --interproscan6-datadir "${interproscan6_datadir}" \\
        --interproscan6-version "${params.interproscan6_version}" \\
        --interproscan6-interpro-version "${params.interproscan6_interpro_version}" \\
        --interpro-pfam-version "${params.interpro_pfam_version}" \\
        --interpro-ncbifam-version "${params.interpro_ncbifam_version}" \\
        --deepkoala-resources "${deepkoala_resources}" \\
        --deepkoala-workdir "${params.deepkoala_workdir ?: ''}" \\
        --deepkoala-model "${params.deepkoala_model}" \\
        --deepkoala-date "${params.deepkoala_date}" \\
        --eggnog-data-dir "${eggnog_data_dir}" \\
        --eggnog-mapper-db "${eggnog_mapper_db}" \\
        --amrfinder-db "${amrfinder_db}" \\
        --db-root "${params.db_root ?: ''}" \\
        ${prepare_arg} \\
        ${skip_arg} \\
        --out database_manifest.yml
    """

    stub:
    """
    cat > database_manifest.yml <<'EOF'
panannotator_databases:
  db_root: "stub"
  prepare_databases: false
  skip_db_validation: true
  entries: []
EOF
    """
}
