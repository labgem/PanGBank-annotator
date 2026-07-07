# LABGeM/panAnnotator: Usage

Run from the repository root:

```bash
nextflow run . \
  --collection_release v1.0.0 \
  --source all \
  --outdir outputs/panAnnotator/GTDB_all_v1.0.0 \
  -profile slurm
```

Use `--source refseq` to process the `GTDB_refseq` collection.

The workflow currently implements the clustering stage. The `--run_clustering`
parameter is present so annotation can be added later as a second optional
stage without changing the top-level workflow shape.

## Required Parameters

`--collection_release`

: PanGBank collection release ID, for example `v1.0.0`.

`--outdir`

: Directory where workflow outputs are published.

## PanGBank Access

The clustering stage first tries to read the local PanGBank mirror:

```text
<pangbank_root>/collections/GTDB_<source>/release_<collection_release>/data/pangenomes
```

If that path is absent and `pangbank` is installed, the fetch helper falls back
to PanGBank-cli download mode.
