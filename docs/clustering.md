# Clustering Stage

The clustering stage fetches pangenome family representative proteins from a
PanGBank collection release, clusters them with DIAMOND, applies the DIAMOND
`recluster` and `reassign` correction steps, and packages PANFAM deliverables.

The implementation assumes each record in a pangenome
`all_protein_families.faa.gz` is one pangenome family representative and uses
the FASTA record ID as `Pangenome_family_id`.

Cluster IDs use the PanGBank API collection release ID, not the release version
string:

```text
PANFAM_<cluster_level>_r<collection_release_api_id>_<incremental_cluster_id>
```

Later annotation can consume:

```text
clustering/fasta/PANFAM_deep.faa.gz
clustering/fasta/PANFAM_50.faa.gz
clustering/fasta/PANFAM_80.faa.gz
clustering/parquet/*.parquet
```
