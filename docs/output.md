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

The fetch and DIAMOND database intermediate outputs are published under:

```text
<outdir>/inputs/
<outdir>/diamond/dbs/
```

DIAMOND cluster tables are kept compressed in the Nextflow `work/` directory for
resume/provenance, but they are not published by default. Use
`--keep_raw_clusters true` to also copy them to
`<outdir>/diamond/clusters/` as `.tsv.gz` files.
