# Clustering Stage

The clustering stage fetches pangenome family representative proteins from a
PanGBank collection release, clusters them with DIAMOND, applies the DIAMOND
`recluster` and `reassign` correction steps, and packages PANFAM deliverables.

The implementation assumes each record in a pangenome
`all_protein_families.faa.gz` is one pangenome family representative and uses
the FASTA record ID as `Pangenome_family_id`.

Later annotation can consume:

```text
PANFAM/fasta/PANFAM_deep.faa.gz
PANFAM/fasta/PANFAM_50.faa.gz
PANFAM/fasta/PANFAM_80.faa.gz
PANFAM/parquet/*.parquet
```
