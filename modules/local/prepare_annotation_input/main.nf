process PREPARE_ANNOTATION_INPUT {
    tag "$annotation_input_mode"
    label "process_low"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.panannotator_container : params.panannotator_container}"
    publishDir enabled: false

    input:
    path panfam_dir
    path all_faa
    val annotation_input_mode

    output:
    path "${annotation_input_mode}.faa.gz", emit: fasta
    path "versions_prepare_annotation_input_*.yml", emit: versions

    script:
    def source_path = annotation_input_mode == "all_proteins"
        ? "${all_faa}"
        : "${panfam_dir}/fasta/PANFAM_80.faa.gz"

    """
    if [[ "${source_path}" == *.gz ]]; then
        cp ${source_path} ${annotation_input_mode}.faa.gz
    else
        gzip -c ${source_path} > ${annotation_input_mode}.faa.gz
    fi

    {
        printf '"%s":\n' "${task.process}"
        printf '    cp: "%s"\n' "\$(cp --version | head -n 1)"
    } > versions_prepare_annotation_input_${annotation_input_mode}.yml
    """
}
