# panAnnotator

<!-- [![Open in GitHub Codespaces](https://img.shields.io/badge/Open_In_GitHub_Codespaces-black?labelColor=grey&logo=github)](https://github.com/codespaces/new/yazid-hoblos/panannotator) -->

[![GitHub Actions CI Status](https://github.com/yazid-hoblos/panannotator/actions/workflows/nf-test.yml/badge.svg)](https://github.com/yazid-hoblos/panannotator/actions/workflows/nf-test.yml)
[![GitHub Actions Linting Status](https://github.com/yazid-hoblos/panannotator/actions/workflows/linting.yml/badge.svg)](https://github.com/yazid-hoblos/panannotator/actions/workflows/linting.yml)
[![nf-test](https://img.shields.io/badge/unit_tests-nf--test-337ab7.svg)](https://www.nf-test.com)

[![Nextflow](https://img.shields.io/badge/version-%E2%89%A525.10.4-green?style=flat&logo=nextflow&logoColor=white&color=%230DC09D&link=https%3A%2F%2Fnextflow.io)](https://www.nextflow.io/)
[![nf-core template version](https://img.shields.io/badge/nf--core_template-4.0.2-green?style=flat&logo=nfcore&logoColor=white&color=%2324B064&link=https%3A%2F%2Fnf-co.re)](https://github.com/nf-core/tools/releases/tag/4.0.2)
[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)
[![Launch on Seqera Platform](https://img.shields.io/badge/Launch%20%F0%9F%9A%80-Seqera%20Platform-%234256e7)](https://cloud.seqera.io/launch?pipeline=https://github.com/yazid-hoblos/panannotator)

## Introduction

**panAnnotator** is a workflow for building PANFAM protein clusters from PanGBank pangenome family representatives and annotating the resulting representative sequences.

The current implementation contains:

1. Resolve a PanGBank collection release and collection (`GTDB_all` or `GTDB_refseq`).
2. Fetch `all_protein_families.faa.gz` records and build a pangenome-family map.
3. Run DIAMOND `deepclust`, followed by `recluster` and `reassign` correction.
4. Package PANFAM parquet files, representative FASTA files, and a report file.
5. Optionally annotate PANFAM representatives with InterProScan 6, DeepKOALA, eggNOGMapper, and AMRFinder+.

DIAMOND is currently pinned to 2.1.13 for all clustering steps. Newer tested
versions are not suitable for this workflow yet: 2.1.24 fails during
`reassign`, and 2.2.4 temporarily removed `reassign`. The DIAMOND modules
declare both Conda and container execution for this pinned version.

## Usage

> [!NOTE]
> If you are new to Nextflow and nf-core, please refer to [this page](https://nf-co.re/docs/get_started/environment_setup/overview) on how to set-up Nextflow. Make sure to [test your setup](https://nf-co.re/docs/get_started/run-your-first-pipeline) with `-profile test` before running the workflow on actual data.

Run the clustering stage with a PanGBank collection release:

```bash
nextflow run panAnnotator \
   -profile slurm,conda \
   --release v1.0.0 \
   --collection GTDB_all \
   --outdir <OUTDIR>
```

Use `conda` or `mamba` as the primary software profile. `singularity` and
`apptainer` are kept for containerized modes such as imported InterProScan 6 and for future full-container support.
Use `conda_singularity` or `conda_apptainer` as temporary bridge profiles when
you need Conda-managed panAnnotator modules with imported InterProScan 6
containerized app modules.

DeepKOALA is run from a dedicated container image and external model resources.
Build the default image from `modules/local/deepkoala/Dockerfile` and provide
the resources directory with `--deepkoala_resources`.

> [!WARNING]
> Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/running/run-pipelines#using-parameter-files).

## Citations

<!-- TODO nf-core: Add bibliography of tools and data used in your pipeline -->

An extensive list of references for the tools used by the pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) file.

This pipeline uses code and infrastructure developed and maintained by the [nf-core](https://nf-co.re) community, reused here under the [MIT license](https://github.com/nf-core/tools/blob/main/LICENSE).

> **The nf-core framework for community-curated bioinformatics pipelines.**
>
> Philip Ewels, Alexander Peltzer, Sven Fillinger, Harshil Patel, Johannes Alneberg, Andreas Wilm, Maxime Ulysse Garcia, Paolo Di Tommaso & Sven Nahnsen.
>
> _Nat Biotechnol._ 2020 Feb 13. doi: [10.1038/s41587-020-0439-x](https://dx.doi.org/10.1038/s41587-020-0439-x).
