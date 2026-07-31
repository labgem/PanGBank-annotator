# PanGBank-annotator: Output

PanGBank-annotator publishes final deliverables under the following directories:

```text
<outdir>/
├── inputs/
├── clustering/
├── annotation/
├── report/
└── pipeline_info/
```

## Inputs

```text
inputs/
├── all_protein_families.faa.gz
├── pangenome_families.tsv.gz
└── metadata/
    ├── collection_metadata.yml
    └── pangenome_api_ids.tsv
```

Annotation tools use `clustering/fasta/PANFAM_80.faa.gz` by default. Tools
listed in `--all_protein_tools` use `inputs/all_protein_families.faa.gz`.

`inputs/metadata/` contains the details of the selected PanGBank collection,
API release ID, local mirror path, and the local pangenome directory name to
PanGBank integer ID map.

## Clustering

```text
clustering/
├── PANFAM_report.txt
├── fasta/
│   ├── PANFAM_deep.faa.gz
│   ├── PANFAM_50.faa.gz
│   └── PANFAM_80.faa.gz
└── parquet/
    ├── PANFAM_deep.parquet
    ├── PANFAM_50.parquet
    ├── PANFAM_80.parquet
    └── pangenomes/
        └── PANFAM_p<pangenome_id>.parquet
```

Raw DIAMOND cluster tables are gzipped in the Nextflow `work/` directory by default. Use
`--keep_raw_clusters true` to also publish them under `clustering/raw/diamond/`.


## Annotation

```text
annotation/
├── annotation_report.txt
├── parquet/
│   ├── pfam.parquet
│   ├── ncbifam.parquet
│   ├── deepkoala.parquet
│   ├── eggnog.parquet
│   ├── amrfinder.parquet
│   └── pangenomes/
│       └── <annotation_type>_p<pangenome_id>.parquet
└── raw/
    ├── interpro/
    │   ├── native/
    │   └── imported/
    ├── deepkoala/
    ├── eggnog/
    └── amrfinder/
```

The `raw/` directory is not published by default. Raw annotation files are
gzipped inside Nextflow `work/`. Use `--keep_raw_annotations true` to also publish gzipped raw annotation outputs
under `annotation/raw/<tool>/`.

## Report

```text
report/
├── multiqc_report.html
├── multiqc_data/
├── clustering/
│   ├── custom_content/
│   ├── plots/
│   └── tables/
└── annotation/
    ├── custom_content/
    ├── plots/
    └── tables/
```

The `tables/` directories contain the raw data used for plots and MultiQC
sections. The `plots/` directories contain PNG files embedded in MultiQC.

## Pipeline Info

```text
pipeline_info/
├── execution_report_*.html
├── execution_timeline_*.html
├── pipeline_dag_*.html
├── execution_trace_*.txt
├── params_*.json
├── database_manifest.yml
└── software_versions.yml
```
