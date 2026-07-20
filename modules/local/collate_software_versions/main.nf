process COLLATE_SOFTWARE_VERSIONS {
    tag "software_versions"
    label "process_low"
    conda "${projectDir}/modules/local/envs/panfam/environment.yml"
    publishDir "${params.outdir}/pipeline_info", mode: "copy"

    input:
    path version_files

    output:
    path "software_versions.yml", emit: versions

    script:
    """
    python ${projectDir}/bin/collate_software_versions.py ${version_files} --out software_versions.yml
    """
}
