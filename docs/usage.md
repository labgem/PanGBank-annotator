# LABGeM/panAnnotator: Usage

Run from the repository root:

```bash
nextflow run . \
  --release v1.0.0 \
  --collection GTDB_all \
  --outdir outputs/panAnnotator/GTDB_all_v1.0.0 \
  -profile slurm,conda
```

Use `--collection GTDB_refseq` to process the RefSeq-only collection.

Run the built-in small test dataset with:

```bash
nextflow run . -profile test,local_tools --outdir results/test
```

`local_tools` disables Nextflow-managed Conda/container environments and uses
tools from the environment already active in your shell. Use it only for
developer tests where the active environment is known.

For production or shared runs, use `conda` or `mamba` as the primary software
profile. The local panAnnotator modules all declare Conda environments, so this
is the supported standalone mode for full default runs. Add `singularity` or
`apptainer` when you run imported InterProScan 6, whose app modules are
containerized.

Runtime profile summary:

| Profile | Purpose |
| --- | --- |
| `slurm` | Submit processes to Slurm. Combine with a software profile. |
| `conda` / `mamba` | Primary supported software profile. Use only Conda environments. |
| `conda,singularity` | Conda for panAnnotator modules, Singularity for imported InterProScan app modules. |
| `conda,apptainer` | Conda for panAnnotator modules, Apptainer for imported InterProScan app modules. |
| `singularity` | Container profile. Use with `conda` for imported InterProScan 6 runs unless every requested module has a container. |
| `apptainer` | Container profile. Use with `conda` for imported InterProScan 6 runs unless every requested module has a container. |
| `local_tools` | Developer/debug mode; no software is managed by Nextflow. |

Future development should add and test full-container support for all local
panAnnotator modules. Until then, `conda,singularity` is the recommended
profile combination for runs that include imported InterProScan 6.

DeepKOALA uses an external resources directory configured by
`--deepkoala_resources` and a source checkout configured by
`--deepkoala_workdir`. On the LABGeM filesystem these default to the shared WP3
DeepKOALA installation.

When using a Conda-backed profile, the conda installation must be able to write
to a package cache while creating environments. On clusters where the default
conda package directories are read-only, set a writable cache before launching:

```bash
export NXF_CONDA_CACHEDIR=/path/to/writable/nextflow-conda-envs
export CONDA_PKGS_DIRS=/path/to/writable/conda-pkgs
```

When using Singularity or Apptainer-backed profiles, set a persistent image
cache so containers are not repeatedly pulled into the work directory:

```bash
export NXF_SINGULARITY_CACHEDIR=/path/to/writable/singularity-cache
export NXF_APPTAINER_CACHEDIR=/path/to/writable/apptainer-cache
```

All DIAMOND clustering steps currently use DIAMOND 2.1.13. This pin is
deliberate: DIAMOND 2.1.24 fails in `reassign` with `Error: Block::ids()`, and
DIAMOND 2.2.4 reports that `reassign` has been temporarily removed. Do not
upgrade DIAMOND for this workflow without retesting `deepclust`, `recluster`,
and `reassign` together. The DIAMOND modules declare both a Conda environment
and a BioContainers/Singularity image for this pinned version.

By default, clustering runs `deepclust`, then the error-correction steps
`recluster` and `reassign`. Set `--run_cluster_correction false` to skip
`recluster` and `reassign`; in that mode, the initial `deepclust` clusters are
packaged directly as the final PANFAM clusters.

The workflow runs clustering by default. Add `--run_annotation` to run the
annotation stage after clustering. The current annotation stage supports
InterProScan 6, DeepKOALA, eggNOGMapper, and AMRFinder+.

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
`<outdir>/clustering/raw/diamond/clusters/`.

## Annotation Stage

Enable annotation after clustering with:

```bash
nextflow run . \
  --release v2.0.0 \
  --collection GTDB_all \
  --run_annotation \
  --annotation_tools interpro,deepkoala,eggnog,amrfinder \
  --outdir results/GTDB_all_v2.0.0 \
  -profile slurm,conda,singularity
```

By default, annotation input is `clustering/fasta/PANFAM_80.faa.gz`. Tools listed in
`--all_protein_tools` will instead run on all pangenome
representative proteins; this is intended for tools such as AMRFinder+ where
family representatives may lose relevant gene-level information.

Raw annotation outputs are gzipped in Nextflow `work/` and are not published by
default. Add `--keep_raw_annotations true` to publish them under
`<outdir>/annotation/raw/<tool>/`.

Run annotation only from an existing PANFAM clustering result with:

```bash
nextflow run . \
  --run_clustering false \
  --run_annotation true \
  --annotation_tools interpro,deepkoala,eggnog,amrfinder \
  --outdir results/GTDB_all_v2.1.0 \
  -profile slurm,conda,singularity
```

In annotation-only mode, `--outdir` must point to an existing panAnnotator
result directory. The workflow reads clustering results from `<outdir>/clustering`
and input metadata from `<outdir>/inputs`.

panAnnotator splits FASTA inputs for tools it runs directly. `--annotation_chunk_size`
controls the number of proteins per chunk for native InterPro, DeepKOALA,
eggNOG, and AMRFinder+. Imported InterProScan 6 uses its own internal
`--interproscan6_batch_size` and `--interproscan6_sub_batch_size` settings.

InterPro annotations run in `imported` mode by default with
`--interpro_apps Pfam,NCBIFAM`. This runs the vendored InterProScan 6 DSL2
workflow inside the parent panAnnotator Nextflow graph. Imported mode can use
InterProScan 6 applications beyond Pfam and NCBIFAM while keeping a single
Nextflow controller, normal process visibility, and normal `-resume` behavior.
Imported mode writes one annotation parquet per requested InterPro application,
using a normalized lowercase application name such as `pfam.parquet`,
`ncbifam.parquet`, or `superfamily.parquet`.

Use `--interpro_mode native` for the lightweight local HMMER implementation of
Pfam and NCBIFAM. Native mode supports `--interpro_apps Pfam,NCBIFAM`,
`--interpro_apps Pfam`, or `--interpro_apps NCBIFAM`.

Imported mode is the exception to the Conda-only recommendation: it requires a
container runtime because the vendored InterProScan app modules are
containerized. For current HPC use, run it with `-profile slurm,conda,singularity`
or `-profile slurm,conda,apptainer`. With `-profile local_tools`, imported
InterProScan apps run against commands available in the active environment and
are intended only for development.

### InterProScan 6 Submodule And Temporary Patch

panAnnotator tracks upstream InterProScan 6 as a Git submodule under
`subworkflows/interproscan6`. Imported InterProScan is run from inside the
parent panAnnotator workflow, so panAnnotator provides a small compatibility
layer:

- `lib` is a symlink to `subworkflows/interproscan6/lib`, allowing Groovy
  classes imported by InterProScan modules to resolve from the parent
  `projectDir`.
- selected InterProScan helper scripts are exposed in `bin/` as symlinks,
  because Nextflow adds the parent workflow `bin/` to task `PATH`.
- imported InterProScan container tasks bind-mount
  `subworkflows/interproscan6/bin`, so those symlink targets remain visible
  inside Singularity/Apptainer containers.

Until the upstream `sequences.db` staging/output issue is fixed in an
InterProScan release, panAnnotator also carries a local patch:

```text
patches/interproscan6/0001-imported-workflow-localize-sequences-db.patch
```

Apply it after checking out or updating submodules:

```bash
git submodule update --init --recursive
bin/apply_interproscan6_patches.sh
```

The patch modifies only InterProScan `SPLIT_FASTA` and `WRITE_TSV` so SQLite
reads use node-local temporary storage before outputs are moved back to the
Nextflow work directory. The parent panAnnotator repository should commit the
upstream submodule pointer and the patch file, but not a forked InterProScan
commit for these temporary changes.

DeepKOALA uses source code from `--deepkoala_workdir` and model files from
`--deepkoala_resources`. By default these point to
`/env/export/labgem_bank/WP3/deepkoala` and
`/env/export/labgem_bank/WP3/deepkoala/resources`. The resources directory must
contain model-date subdirectories such as `202502` or `202603`.

The container path is configured by `--deepkoala_container`, but it requires an
accessible image. Build the default CPU image with:

```bash
docker build -t ghcr.io/labgem/deepkoala:0.1-beta modules/local/deepkoala
```

For local development, override `--deepkoala_workdir` to point to another
DeepKOALA source checkout.

eggNOGMapper uses the shared database paths configured with
`--eggnog_data_dir` and `--eggnog_mapper_db`. Use Nextflow `-resume` when you
want to reuse completed eggNOGMapper process results from the same work
directory.

AMRFinder+ uses the database configured by `--amrfinder_db`. On the LABGeM
filesystem this defaults to `/env/export/labgem_bank/WP3/amrfinder`, which may
be a database root containing a `latest` symlink.

Before annotation starts, panAnnotator validates the database paths required by
the requested tools and writes `<outdir>/pipeline_info/database_manifest.yml`.
Use `--skip_db_validation true` only when a site-specific wrapper provides paths
that are not visible during the validation process.

The recommended shared database layout is:

```text
<db_root>/
  interproscan/interproscan6_data/
  eggnog/5.0.2/
  deepkoala/resources/
  amrfinder/
```

When `--db_root <path>` is set, panAnnotator derives the annotation database
paths from this layout:

- `--interproscan6_datadir <db_root>/interproscan/interproscan6_data`
- `--eggnog_data_dir <db_root>/eggnog/5.0.2`
- `--eggnog_mapper_db <db_root>/eggnog/5.0.2/eggnog_proteins.dmnd`
- `--deepkoala_resources <db_root>/deepkoala/resources`
- `--amrfinder_db <db_root>/amrfinder`

Use `--prepare_databases true --db_root <path>` to download or update the
databases needed by the requested annotation tools before validation. This is an
explicit opt-in step because the downloads can be large. The implemented setup
actions follow the existing WP3 notes:

- Pfam: `curl` Pfam-A HMM and metadata, then `hmmpress`.
- InterProScan 6 imported applications: download InterProScan 6 data archives
  from the EBI InterProScan 6 FTP layout and verify MD5 checksums.
- eggNOG: run `download_eggnog_data.py -y --data_dir <eggnog_data_dir>`.
- AMRFinder+: run `amrfinder_update --database <amrfinder_db>`.
- DeepKOALA: download model files from GenomeNet into the `resources/`
  directory when the requested model date is not already present.

Annotation outputs are:

- one parquet file per pangenome and annotation type:
  `<annotation_type>_p<pangenome_id>.parquet`
- one global parquet file per annotation type

For InterPro applications, DeepKOALA/KOfam, and AMRFinder+, annotation parquet
files keep only `Pangenome_id`, `Pangenome_family_id`, and `Annotation_id`.
For eggNOG, annotation parquet files keep `Pangenome_id`,
`Pangenome_family_id`, and the full `eggNOG_OGs` column.
