# Clustering Stage

The clustering stage fetches pangenome family representative proteins from a
PanGBank collection release, clusters them with DIAMOND, applies the DIAMOND
`recluster` and `reassign` correction steps, and packages PANFAM deliverables.

The implementation uses the `all_protein_families.faa.gz` records of each
PanGBank pangenome, and uses the FASTA record ID as `Pangenome_family_id`.

## PanGBank Access

The clustering stage uses the PanGBank API to validate the selected collection
release and resolve its numeric API release ID. That ID is written as `r<id>`
and used in PANFAM cluster identifiers:

```text
PANFAM_<cluster_level>_r<collection_release_api_id>_<incremental_cluster_id>
```

Protein sequence data are read from the local PanGBank mirror:

```text
<pangbank_root>/collections/<collection>/release_<release>/data/pangenomes
```

## Clustering-specific Parameters

| Parameter                  | Default                          | Values / example                            | Purpose                                                                |
| -------------------------- | -------------------------------- | ------------------------------------------- | ---------------------------------------------------------------------- |
| `--pangbank_root`          | `/env/export/pangbank_data/prod` | `/path/to/pangbank/prod`                    | Local PanGBank mirror root.                                            |
| `--levels`                 | `deep,50,80`                     | `80`, `50,80`, `deep,50,80`                 | Cluster levels to generate.                                            |
| `--deep_approx_id`         | `0`                              | `0`                                         | DIAMOND approximate identity for the deep clustering level.            |
| `--member_cover`           | `80`                             | `80`                                        | DIAMOND member coverage threshold.                                     |
| `--evalue`                 | `0.00001`                        | `1e-5`                                      | DIAMOND E-value threshold.                                             |
| `--diamond_memory`         | `200G`                           | `100G`, `200G`                              | Memory passed to DIAMOND clustering steps.                             |
| `--run_cluster_correction` | `true`                           | `true`, `false`                             | Run DIAMOND `recluster` and `reassign`; if false, package `deepclust`. |
| `--keep_raw_clusters`      | `false`                          | `true`, `false`                             | Publish gzipped raw DIAMOND cluster tables.                            |
| `--compression`            | `zstd`                           | `zstd`, `snappy`, depending on environment. | Parquet compression codec.                                             |

## Packaged PANFAM Outputs Structure

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

Global clustering parquet files contain:

```text
Pangenome_id
Pangenome_family_id
Cluster_id
is_representative
```

Per-pangenome parquet files contain:

```text
Pangenome_family_id
Cluster_level
Cluster_id
```

Representative FASTA files use PANFAM cluster IDs as FASTA record IDs.
`PANFAM_report.txt` is a compact clustering summary.

## Notes

- Normal runs validate `--collection` and `--release` through the PanGBank API,
  then read protein FASTA files from the local mirror configured by
  `--pangbank_root`.

- If annotation is enabled and level `80` is requested, the workflow prioritizes
  the 80-level package so annotation can start before the other levels finish.

- By default, clustering runs: `deepclust -> recluster -> reassign -> package`

- When correction is disabled, the initial DIAMOND `deepclust` tables are
  packaged directly as final PANFAM clusters.

- DIAMOND cluster tables are gzipped in the Nextflow `work/` directory. They are
  published only when `--keep_raw_clusters true`, under:
  `clustering/raw/diamond/clusters/`.

- All DIAMOND clustering steps currently use DIAMOND 2.1.13. For the time
  being, DIAMOND 2.1.24 fails in `reassign`, and DIAMOND 2.2.4 temporarily
  removed `reassign`.
