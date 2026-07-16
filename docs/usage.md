# LABGeM/panAnnotator: Usage

Run from the repository root:

```bash
nextflow run . \
  --collection_release v1.0.0 \
  --collection GTDB_all \
  --outdir outputs/panAnnotator/GTDB_all_v1.0.0 \
  -profile slurm
```

Use `--collection GTDB_refseq` to process the RefSeq-only collection.

The workflow currently implements the clustering stage. The `--run_clustering`
parameter is present so annotation can be added later as a second optional
stage without changing the top-level workflow shape.

## Required Parameters

`--collection_release`

: PanGBank collection release ID, for example `v1.0.0`.

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
<pangbank_root>/collections/<collection>/release_<collection_release>/data/pangenomes
```

Each pangenome directory must contain `all_protein_families.faa.gz`.
