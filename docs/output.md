# LABGeM/panAnnotator: Output

The clustering stage publishes final deliverables under:

```text
<outdir>/PANFAM/
```

Expected files:

```text
fasta/PANFAM_deep.faa.gz
fasta/PANFAM_50.faa.gz
fasta/PANFAM_80.faa.gz
parquet/PANFAM_deep.parquet
parquet/PANFAM_50.parquet
parquet/PANFAM_80.parquet
parquet/pangenomes/PANFAM_p<pangenome_id>.parquet
PANFAM_report.txt
```

`PANFAM_report.txt` is a compact summary table.

The workflow publishes one report directory under:

```text
<outdir>/multiqc/
├── analysis/
│   └── raw_data/
│       ├── cluster_summary_metrics.tsv
│       ├── cluster_size_distribution.tsv
│       └── cluster_size_bin_summary.tsv
├── custom_content/
│   └── panfam_clustering_mqc.yaml
├── multiqc_data/
├── multiqc_plots/
│   ├── PANFAM_cluster_reduction_summary.png
│   ├── PANFAM_cluster_size_rank_distribution.png
│   ├── PANFAM_singleton_rates.png
│   ├── PANFAM_cluster_size_bins_combined.png
│   ├── PANFAM_cluster_size_distribution.png
│   ├── PANFAM_cluster_size_ecdf.png
│   └── PANFAM_cluster_size_ccdf.png
└── multiqc_report.html
```

`analysis/raw_data/` contains the raw tables used for report statistics and
plots. `multiqc_plots/` contains the PNG plots embedded in the MultiQC report.

The fetch and DIAMOND database intermediate outputs are published under:

```text
<outdir>/inputs/
<outdir>/diamond/dbs/
```

DIAMOND cluster tables are kept compressed in the Nextflow `work/` directory for
resume/provenance, but they are not published by default. Use
`--keep_raw_clusters true` to also copy them to
`<outdir>/diamond/clusters/` as `.tsv.gz` files.
