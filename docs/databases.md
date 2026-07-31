# Annotation Databases

PanGBank-annotator validates annotation database paths before running the
annotation stage and writes a manifest to:

```text
<outdir>/pipeline_info/database_manifest.yml
```

Validation runs for the tools requested with `--annotation_tools`. Tools listed
in `--all_protein_tools` are still validated only if they are also present in
`--annotation_tools`.

The recommended database layout is:

```text
<db_root>/
├── interproscan/
│   └── interproscan6_data/
├── eggnog/
│   └── 5.0.2/
├── deepkoala/
│   └── resources/
└── amrfinder/
```

Set `--db_root` to derive the standard database paths from this layout. This sets:

```text
--interproscan6_datadir <db_root>/interproscan/interproscan6_data
--eggnog_data_dir       <db_root>/eggnog/5.0.2
--eggnog_mapper_db      <db_root>/eggnog/5.0.2/eggnog_proteins.dmnd
--deepkoala_resources   <db_root>/deepkoala/resources
--amrfinder_db          <db_root>/amrfinder
```

On the server-side, defaults currently point to shared WP3 locations under: `/env/export/labgem_bank/WP3/`.

## Prepare Databases

Use:

```bash
--prepare_databases true --db_root /path/to/db_root
```

to download or update databases for the requested annotation tools before
validation, following the same layout as above.

Preparation currently supports:

| Tool                         | Preparation action                                                                    |
| ---------------------------- | ------------------------------------------------------------------------------------- |
| InterProScan 6 imported apps | Download InterProScan 6 data archives from EBI and verify MD5 checksums.              |
| Native Pfam                  | Download Pfam-A HMM and metadata, gunzip them, and run `hmmpress`.                    |
| Native NCBIFAM               | Download the NCBIFAM archive through the InterProScan 6 data layout.                  |
| eggNOGMapper                 | Run `download_eggnog_data.py -y --data_dir <eggnog_data_dir>`.                        |
| AMRFinder+                   | Run `amrfinder_update --database <amrfinder_db>`.                                     |
| DeepKOALA                    | Download the requested model files from GenomeNet into `deepkoala/resources/<date>/`. |

## Database Parameters

| Tool / database | Parameter(s)                                                                             | Default LABGeM path / value                                                                                  | Validation / preparation notes                                                                                                            |
| --------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| InterProScan 6  | `--interproscan6_datadir`, `--interproscan6_version`, `--interproscan6_interpro_version` | `/env/export/labgem_bank/WP3/interproscan/interproscan6_data`, `6.0.1`, `109.0`                              | Imported mode validates requested InterPro apps against the InterProScan 6 data layout and checks InterPro metadata files.                |
| Native Pfam     | `--interpro_pfam_version`                                                                | `38.2`                                                                                                       | Native Pfam requires a pressed Pfam HMM database.                                                                                         |
| Native NCBIFAM  | `--interpro_ncbifam_version`                                                             | `19.0`                                                                                                       | Native NCBIFAM is resolved from the InterProScan 6 data directory.                                                                        |
| DeepKOALA       | `--deepkoala_resources`, `--deepkoala_workdir`, `--deepkoala_model`, `--deepkoala_date`  | `/env/export/labgem_bank/WP3/deepkoala/resources`, unset, `full`, `latest`                                  | The DeepKOALA package is installed in the software environment/container; `--deepkoala_workdir` is only a development override. `latest` accepts the newest complete local model directory; preparation downloads the requested GenomeNet model release. |
| eggNOGMapper    | `--eggnog_data_dir`, `--eggnog_mapper_db`                                                | `/env/export/labgem_bank/WP3/eggnog/5.0.2/`, `/env/export/labgem_bank/WP3/eggnog/5.0.2/eggnog_proteins.dmnd` | Validation checks `eggnog_proteins.dmnd`, `eggnog.db`, and `eggnog.taxa.db`; preparation runs `download_eggnog_data.py`.                  |
| AMRFinder+      | `--amrfinder_db`                                                                         | `/env/export/labgem_bank/WP3/amrfinder`                                                                      | Validation accepts either `<amrfinder_db>/AMRProt.fa.phr` or `<amrfinder_db>/latest/AMRProt.fa.phr`; preparation runs `amrfinder_update`. |

## Database Manifest

The manifest records:

- `db_root`
- whether `--prepare_databases` was enabled
- whether validation was skipped
- every checked path
- whether each path exists

```yaml
panannotator_databases:
  db_root: "/path/to/db_root"
  prepare_databases: false
  skip_db_validation: false
  entries:
    - tool: "interpro"
      name: "data directory"
      path: "/path/to/db_root/interproscan/interproscan6_data"
      required: true
      status: "ok"
```

You may use `--skip_db_validation true` to skip database validation. The manifest will still be written, but
missing paths are marked as skipped instead of failing the workflow.
