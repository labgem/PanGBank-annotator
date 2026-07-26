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
is the supported standalone mode for full default runs. `singularity` and
`apptainer` are kept as container-only profiles, but they should be considered
experimental until every local panAnnotator utility module has a container.
Use `conda_singularity` or `conda_apptainer` only as a temporary bridge when
you need Conda-managed panAnnotator steps together with imported InterProScan 6
containerized app modules.

Runtime profile summary:

| Profile | Purpose |
| --- | --- |
| `slurm` | Submit processes to Slurm. Combine with a software profile. |
| `conda` / `mamba` | Primary supported software profile. Use only Conda environments. |
| `conda_singularity` | Temporary mixed profile: Conda for panAnnotator modules, Singularity for imported InterProScan app modules. |
| `conda_apptainer` | Temporary mixed profile: Conda for panAnnotator modules, Apptainer for imported InterProScan app modules. |
| `singularity` | Container-only profile. No Conda environments are created. Experimental for full panAnnotator runs. |
| `apptainer` | Container-only profile. No Conda environments are created. Experimental for full panAnnotator runs. |
| `local_tools` | Developer/debug mode; no software is managed by Nextflow. |

Future development should replace the temporary mixed profiles with full
container support for all panAnnotator modules. That requires adding and testing
containers for the local Python/reporting utilities, PanGBank fetch step,
native InterPro HMMER mode, AMRFinder+, and any other local module that
currently has only a Conda environment.

DeepKOALA uses a dedicated container image plus an external resources directory
configured by `--deepkoala_resources`. The legacy `--deepkoala_workdir` source
checkout mode is kept for local development only.

When using a Conda-backed profile, the conda installation must be able to write
to a package cache while creating environments. On clusters where the default
conda package directories are read-only, set a writable cache before launching:

```bash
export CONDA_PKGS_DIRS=/path/to/writable/conda-pkgs
```

All DIAMOND clustering steps currently use DIAMOND 2.1.13. This pin is
deliberate: DIAMOND 2.1.24 fails in `reassign` with `Error: Block::ids()`, and
DIAMOND 2.2.4 reports that `reassign` has been temporarily removed. Do not
upgrade DIAMOND for this workflow without retesting `deepclust`, `recluster`,
and `reassign` together. The DIAMOND modules declare both a Conda environment
and a BioContainers/Singularity image for this pinned version.

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
  -profile slurm,conda
```

By default, annotation input is `clustering/fasta/PANFAM_80.faa.gz`. Tools listed in
`--all_protein_tools` will instead run on all pangenome
representative proteins; this is intended for tools such as AMRFinder+ where
family representatives may lose relevant gene-level information.

Raw annotation outputs are gzipped in Nextflow `work/` and are not published by
default. Add `--keep_raw_annotations true` to publish them under
`<outdir>/annotation/raw/<tool>/`.

InterPro annotations run in `native` mode by default. This directly runs the
Pfam and NCBIFAM HMMER searches used by InterProScan 6 and avoids launching a
nested Nextflow workflow. Native mode supports `--interpro_apps Pfam,NCBIFAM`,
`--interpro_apps Pfam`, or `--interpro_apps NCBIFAM`.

Use `--interpro_mode imported` to run the vendored InterProScan 6 DSL2 workflow
inside the parent panAnnotator Nextflow graph. This mode can use InterProScan 6
applications beyond Pfam and NCBIFAM while keeping a single Nextflow controller,
normal process visibility, and normal `-resume` behavior.
Imported mode writes one annotation parquet per requested InterPro application,
using a normalized lowercase application name such as `pfam.parquet`,
`ncbifam.parquet`, or `superfamily.parquet`.

Imported mode is the exception to the Conda-only recommendation: it requires a
container runtime because the vendored InterProScan app modules are
containerized. For current HPC use, run it with `-profile
slurm,conda_singularity` or `-profile slurm,conda_apptainer`. With `-profile
local_tools`, imported InterProScan apps run against commands available in the
active environment and are intended only for development.

DeepKOALA uses the image configured by `--deepkoala_container` and model files
from `--deepkoala_resources`. The resources directory must contain model-date
subdirectories such as `202502` or `202603`. Build the default CPU image with:

```bash
docker build -t ghcr.io/labgem/deepkoala:0.1-beta modules/local/deepkoala
```

For local development without a container, `--deepkoala_workdir` can point to a
DeepKOALA source checkout.

eggNOGMapper uses the shared database paths configured with
`--eggnog_data_dir` and `--eggnog_mapper_db`. Use Nextflow `-resume` when you
want to reuse completed eggNOGMapper process results from the same work
directory.

AMRFinder+ can use the database configured in its installation. To pin a
specific database directory for reproducibility, set `--amrfinder_db`.

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
