# Annotation Stage

The annotation stage consumes PANFAM clustering outputs and writes one global
parquet file per annotation type, as well as one parquet file per pangenome and
annotation type.

By default, annotation uses: `clustering/fasta/PANFAM_80.faa.gz`.

Tools listed in `--all_protein_tools` use: `inputs/all_protein_families.faa.gz`.

The default is `--all_protein_tools amrfinder`, so only AMRFinder+ runs on all
pangenome proteins while InterProScan 6, DeepKOALA, and eggNOGMapper run on
PANFAM_80 representatives.

## Annotation-specific Parameters

| Parameter                        | Default                                                         | Values / example                                  | Purpose                                                                                 |
| -------------------------------- | --------------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `--annotation_tools`             | `interpro,deepkoala,eggnog,amrfinder`                           | Any comma-separated subset of those four tools.   | Annotation tools to run.                                                                |
| `--all_protein_tools`            | `amrfinder`                                                     | `none`, `amrfinder`, or selected requested tools. | Tools that should run on all proteins instead of `PANFAM_80`.                           |
| `--interpro_mode`                | `imported`                                                      | `imported`, `native`                              | Imported InterProScan 6 subworkflow or lightweight native Pfam/NCBIFAM.                 |
| `--interpro_apps`                | `Pfam,NCBIFAM`                                                  | `Pfam,NCBIFAM,CATH-Gene3D,SUPERFAMILY,PANTHER`    | InterProScan applications to run.                                                       |
| `--annotation_chunk_size`        | `80000`                                                         | `1000000`                                         | Protein records per chunk for native InterPro, DeepKOALA, eggNOGMapper, and AMRFinder+. |
| `--interproscan6_batch_size`     | `100000`                                                        | `100000`                                          | Imported InterProScan 6 batch size.                                                     |
| `--interproscan6_sub_batch_size` | `5000`                                                          | `5000`                                            | Imported InterProScan 6 sub-batch size.                                                 |
| `--keep_raw_annotations`         | `false`                                                         | `true`, `false`                                   | Publish gzipped raw annotation outputs.                                                 |
| `--interproscan6_datadir`        | `/env/export/labgem_bank/WP3/interproscan/interproscan6_data`   | `/path/to/interproscan6_data`                     | InterProScan 6 database directory.                                                      |
| `--deepkoala_workdir`            | `/env/export/labgem_bank/WP3/deepkoala`                         | `/path/to/deepkoala`                              | DeepKOALA source checkout.                                                              |
| `--deepkoala_resources`          | `/env/export/labgem_bank/WP3/deepkoala/resources`               | `/path/to/deepkoala/resources`                    | DeepKOALA model resources.                                                              |
| `--eggnog_data_dir`              | `/env/export/labgem_bank/WP3/eggnog/5.0.2/`                     | `/path/to/eggnog/5.0.2`                           | eggNOGMapper data directory.                                                            |
| `--eggnog_mapper_db`             | `/env/export/labgem_bank/WP3/eggnog/5.0.2/eggnog_proteins.dmnd` | `/path/to/eggnog_proteins.dmnd`                   | eggNOGMapper DIAMOND database.                                                          |
| `--amrfinder_db`                 | `/env/export/labgem_bank/WP3/amrfinder`                         | `/path/to/amrfinder`                              | AMRFinder+ database root or versioned database directory.                               |


## InterProScan 6

InterPro supports two modes: imported and native. The native mode is a lightweight local HMMER implementation that supports only Pfam and NCBIFAM.
Whereas the imported mode uses the full InterProScan 6 DSL2 workflow as a standalone subworkflow.

The default behavior is set to:

```bash
--interpro_mode imported
--interpro_apps Pfam,NCBIFAM
```

All applications available in the vendored InterProScan 6 [`applications.config`](../subworkflows/interproscan6/conf/applications.config) are supported.

The imported mode writes one parquet per requested InterPro application using a
normalized lowercase application name, for example:

```text
annotation/parquet/pfam.parquet
annotation/parquet/ncbifam.parquet
annotation/parquet/cathgene3d.parquet
annotation/parquet/superfamily.parquet
```

Imported mode requires a container runtime profile such as `singularity`,
`apptainer`, or `docker`, unless using `local_tools` for development. 

PanGBank-annotator tracks upstream InterProScan 6 as a Git submodule under `subworkflows/interproscan6`.
Initialize it after checkout:

```bash
git submodule update --init --recursive
```

Imported InterProScan runs inside the parent workflow, so PanGBank-annotator
provides a small compatibility layer:

- `lib` is a symlink to `subworkflows/interproscan6/lib`
- selected InterProScan helper scripts are exposed in `bin/` as symlinks
- imported InterProScan container tasks bind-mount `subworkflows/interproscan6/bin`

Until the upstream `sequences.db` staging/output issue is fixed in an
InterProScan release, PanGBank-annotator also carries a local patch that
modifies the `SPLIT_FASTA` and `WRITE_TSV` modules, so SQLite
reads use node-local temporary storage before outputs are moved back to the
Nextflow work directory.

```text
patches/interproscan6/0001-imported-workflow-localize-sequences-db.patch
```

Apply it after initializing or updating the submodule:

```bash
bin/apply_interproscan6_patches.sh
```

## DeepKOALA

DeepKOALA uses source code from `--deepkoala_workdir` and model files from
`--deepkoala_resources`. On the LABGeM filesystem these default to:

```text
/env/export/labgem_bank/WP3/deepkoala
/env/export/labgem_bank/WP3/deepkoala/resources
```

The resources directory must contain model-date subdirectories such as `202607`.

See [Annotation Databases](databases.md#deepkoala) for validation and
preparation details.

## Packaged Output Structure

For InterPro applications, DeepKOALA/KOfam, and AMRFinder+, parquet files keep:

```text
Pangenome_id
Pangenome_family_id
Annotation_id
```

For eggNOG, `Annotation_id` is taken as the  `eggNOG_OGs` column.
For AMRFinder+, `Annotation_id` is taken as the `Element Symbol` column.

When multiple annotations are assigned to the same protein, rows are sorted by
their position on the protein sequence when the raw tool output provides
coordinates, in order to preserve domain order. 

## Notes 

- Tools listed in `--all_protein_tools` but not listed in `--annotation_tools` are
ignored. Use `--all_protein_tools none` to force all requested tools to run on
`PANFAM_80`.

- Raw annotation outputs are gzipped in the Nextflow `work/` directory and are not
published by default. When `--keep_raw_annotations true`, published raw outputs
are written under: `annotation/raw/<tool>/`.

- The `test` profile defaults to `--interpro_mode native`.