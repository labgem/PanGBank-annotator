process DEEPKOALA {
    tag "$sample_id"
    label "process_high"
    conda "${projectDir}/modules/local/envs/deepkoala/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] ? 'docker://' + params.deepkoala_container : params.deepkoala_container}"
    publishDir "${params.outdir}/annotation/raw/deepkoala", mode: "copy", enabled: params.keep_raw_annotations, saveAs: { filename -> filename.startsWith("versions_") ? null : filename }

    input:
    tuple val(sample_id), path(faa), path(proteins)

    output:
    tuple val(sample_id), path("${sample_id}.deepkoala.tsv.gz"), emit: tsv
    path "${sample_id}.deepkoala.raw.csv.gz", emit: raw
    path "versions_deepkoala.yml", emit: versions

    script:
    """
    set -euo pipefail
    printf 'sample_id\tprotein_id\tannotation_id\tscore\tevalue\tsource\traw_annotation\n' > "${sample_id}.deepkoala.tsv"

    MANIFEST="${params.db_manifest}"
    if [[ -f "\$MANIFEST" ]]; then
      set -a
      source "\$MANIFEST"
      set +a
    fi

    DEEPKOALA_RESOURCES="${params.deepkoala_resources ?: ''}"
    DEEPKOALA_WORKDIR="${params.deepkoala_workdir ?: ''}"
    DEEPKOALA_CLI_MODULE="${params.deepkoala_cli_module}"
    DEEPKOALA_MODEL="${params.deepkoala_model}"
    DEEPKOALA_DATE="${params.deepkoala_date}"
    DEEPKOALA_BATCH_SIZE="${params.deepkoala_batch_size}"
    DEEPKOALA_NUM_WORKERS="${params.deepkoala_num_workers}"
    DEEPKOALA_TOPK="${params.deepkoala_topk}"
    DEEPKOALA_DETAIL="${params.deepkoala_detail}"

    if [[ -z "\$DEEPKOALA_CLI_MODULE" ]]; then
      echo "DeepKOALA CLI module is empty." >&2
      exit 1
    fi

    if [[ -n "\$DEEPKOALA_RESOURCES" ]]; then
      if [[ ! -d "\$DEEPKOALA_RESOURCES" ]]; then
        echo "DeepKOALA resources directory is missing or invalid: \$DEEPKOALA_RESOURCES" >&2
        exit 1
      fi
      export DEEPKOALA_RESOURCES="\$(readlink -f "\$DEEPKOALA_RESOURCES")"
      DEEPKOALA_RUN_PREFIX=()
    elif [[ -n "\$DEEPKOALA_WORKDIR" && -d "\$DEEPKOALA_WORKDIR" ]]; then
      export PYTHONPATH="\$(readlink -f "\$DEEPKOALA_WORKDIR"):\${PYTHONPATH:-}"
      DEEPKOALA_RUN_PREFIX=(env PYTHONPATH="\$PYTHONPATH")
    else
      echo "DeepKOALA requires either --deepkoala_resources for packaged/container execution or --deepkoala_workdir for legacy source-checkout execution." >&2
      exit 1
    fi

    DETAIL_ARG=()
    if [[ "\$DEEPKOALA_DETAIL" == "true" ]]; then
      DETAIL_ARG+=(--detail)
    fi

    export OMP_NUM_THREADS="${task.cpus}"
    export MKL_NUM_THREADS="${task.cpus}"
    export OPENBLAS_NUM_THREADS="${task.cpus}"
    export NUMEXPR_NUM_THREADS="${task.cpus}"
    export TORCH_NVML_DISABLE=1
    export PYTORCH_NVML_BASED_CUDA_CHECK=0
    if [[ "${params.deepkoala_use_gpu}" != "true" ]]; then
      export CUDA_VISIBLE_DEVICES=""
      export NVIDIA_VISIBLE_DEVICES="void"
    else
      # Reduce allocator fragmentation on GPU runs.
      export PYTORCH_CUDA_ALLOC_CONF="\${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True,max_split_size_mb:128}"
    fi

    TASK_DIR="\$PWD"
    INPUT_FAA="\$(readlink -f "${faa}")"
    RAW_CSV="\$TASK_DIR/${sample_id}.deepkoala.raw.csv"

    "\${DEEPKOALA_RUN_PREFIX[@]}" python -u -m "\$DEEPKOALA_CLI_MODULE" \
      -i "\$INPUT_FAA" \
      -o "\$RAW_CSV" \
      --model "\$DEEPKOALA_MODEL" \
      --date "\$DEEPKOALA_DATE" \
      --batch_size "\$DEEPKOALA_BATCH_SIZE" \
      --num_workers "\$DEEPKOALA_NUM_WORKERS" \
      --topk "\$DEEPKOALA_TOPK" \
      "\${DETAIL_ARG[@]}"

    python - "${sample_id}" "\$RAW_CSV" "${sample_id}.deepkoala.tsv" <<'PYTHON_EOF'
import csv
import sys

sample_id, in_csv, out_tsv = sys.argv[1:4]

with open(in_csv, newline='') as fin, open(out_tsv, 'a', newline='') as fout:
    reader = csv.DictReader(fin)
    for row in reader:
        protein_id = (row.get('name') or '').strip()
        annotation_id = (row.get('predict_label') or '').strip()
        annotate_flag = (row.get('annotate') or '').strip()

        if not protein_id or not annotation_id:
            continue

        if 'annotate' in row and annotate_flag != '*':
            continue

        score = (row.get('probability') or 'NA').strip() or 'NA'
        evalue = 'NA'

        raw_bits = []
        for key in ('predict_label', 'probability', 'threshold', 'annotate', 'start', 'end'):
            if key in row:
                raw_bits.append(f"{key}={row.get(key, '')}")
        raw_annotation = ';'.join(raw_bits)

        raw_annotation = raw_annotation.replace(chr(9), " ").replace(chr(10), " ").replace(chr(13), " ")
        print(sample_id, protein_id, annotation_id, score, evalue, 'deepkoala', raw_annotation, sep=chr(9), file=fout)
PYTHON_EOF

    gzip -f "${sample_id}.deepkoala.tsv" "${sample_id}.deepkoala.raw.csv"

    {
        printf '"%s":\n' "${task.process}"
        printf '    deepkoala: "%s"\n' "${params.deepkoala_date}"
        python - <<'PY' | sed 's/^/    /'
import importlib.metadata
try:
    print('deepkoala_package: "{}"'.format(importlib.metadata.version('deepkoala')))
except Exception:
    print('deepkoala_package: "unknown"')
PY
    } > versions_deepkoala.yml
    """

    stub:
    """
    printf 'sample_id\tprotein_id\tannotation_id\tscore\tevalue\tsource\traw_annotation\n' > "${sample_id}.deepkoala.tsv"
    printf '%s\ttiny_mock_1\tK00001\t0.99\tNA\tdeepkoala\tstub\n' "${sample_id}" >> "${sample_id}.deepkoala.tsv"
    printf 'name,predict_label,probability,annotate\n' > "${sample_id}.deepkoala.raw.csv"
    printf 'tiny_mock_1,K00001,0.99,*\n' >> "${sample_id}.deepkoala.raw.csv"
    gzip -f "${sample_id}.deepkoala.tsv" "${sample_id}.deepkoala.raw.csv"
    {
        printf '"%s":\n' "${task.process}"
        printf '    deepkoala: "stub"\n'
    } > versions_deepkoala.yml
    """
}
