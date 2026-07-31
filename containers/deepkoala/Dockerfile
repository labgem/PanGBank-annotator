FROM python:3.11-slim

ARG DEEPKOALA_REPO=https://github.com/zhaoxi120/deepkoala.git
ARG DEEPKOALA_REF=bebbe0c43f50a26488f7092f6b355aae870a4ed9

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git gzip procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone "${DEEPKOALA_REPO}" deepkoala \
    && cd deepkoala \
    && git checkout "${DEEPKOALA_REF}" \
    && python - <<'PY'
from pathlib import Path

replacement = (
    'resources_dir = Path(__import__("os").environ.get('
    '"DEEPKOALA_RESOURCES", '
    'Path(__file__).resolve().parent.parent / "resources"))'
)

for relpath in ("deepkoala/infer.py", "deepkoala/infer_multi.py"):
    path = Path(relpath)
    text = path.read_text()
    text = text.replace(
        'resources_dir = Path(__file__).resolve().parent.parent / "resources"',
        replacement,
    )
    path.write_text(text)
PY

RUN pip install numpy==1.26.3 pandas==2.2.2 tqdm==4.66.4 \
    && pip install torch==2.4.1 --index-url https://download.pytorch.org/whl/cpu \
    && pip install /opt/deepkoala

CMD ["deepkoala", "--help"]
