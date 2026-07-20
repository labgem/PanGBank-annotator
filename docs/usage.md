# LABGeM/panAnnotator: Usage

Run from the repository root:

```bash
nextflow run . \
  --release v1.0.0 \
  --collection GTDB_all \
  --outdir outputs/panAnnotator/GTDB_all_v1.0.0 \
  -profile slurm
```

Use `--collection GTDB_refseq` to process the RefSeq-only collection.

Run the built-in small test dataset with:

```bash
nextflow run . -profile test,local_tools --outdir results/test
```

`local_tools` disables Nextflow-managed Conda/container environments and uses
tools from the environment already active in your shell. Use `test,conda`
instead when you deliberately want Nextflow to create reproducible Conda
environments for processes such as MultiQC.

For production or shared runs, prefer a reproducible profile such as `conda`,
`mamba`, `apptainer`, or `docker`. With `-profile conda`, the workflow uses
shared environments by tool group: PANFAM utility/reporting steps, DIAMOND
2.1.24 steps, DIAMOND 2.1.13 correction steps, and MultiQC. With `-profile
local_tools`, no Nextflow-managed environments are created.

The DIAMOND correction steps intentionally use DIAMOND 2.1.13 for `recluster`
and `reassign`, while `makedb` and `deepclust` use DIAMOND 2.1.24. This
downgrade is deliberate because newer DIAMOND versions currently have a bug
affecting the correction commands.

The workflow currently implements the clustering stage. The `--run_clustering`
parameter is present so annotation can be added later as a second optional
stage without changing the top-level workflow shape.

## Required Parameters

`--release`

: PanGBank collection release ID, for example `v1.0.0`. Required for normal
  PanGBank runs. The built-in `test` profile supplies its own small FASTA
  dataset instead.

`--collection`

: Full PanGBank collection name, for example `GTDB_all` or `GTDB_refseq`.

`--outdir`

: Directory where workflow outputs are published.

## PanGBank Access

The clustering stage uses the PanGBank API only to validate the selected
collection release and resolve its numeric API release ID. That ID is written
as `r<id>` and used in PANFAM cluster identifiers.

Protein sequence data are read from the local PanGBank mirror:

```text
<pangbank_root>/collections/<collection>/release_<release>/data/pangenomes
```

Each pangenome directory must contain `all_protein_families.faa.gz`.

## Intermediate Cluster Tables

DIAMOND cluster tables are compressed and kept in the Nextflow `work/`
directory. They are not copied to the output directory by default. Add
`--keep_raw_clusters true` if you want to keep them under
`<outdir>/diamond/clusters/`.
