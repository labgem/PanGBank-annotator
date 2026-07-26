FROM python:3.11-slim

ARG DEEPKOALA_REPO=https://github.com/zhaoxi120/deepkoala.git
ARG DEEPKOALA_REF=412a179a14e5254cb40b205a64f3e45b70cec9be

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN git clone "${DEEPKOALA_REPO}" deepkoala \
    && cd deepkoala \
    && git checkout "${DEEPKOALA_REF}" \
    && python - <<'PY'
from pathlib import Path

for rel in ("deepkoala/infer.py", "deepkoala/infer_multi.py"):
    path = Path(rel)
    text = path.read_text()
    text = text.replace(
        'resources_dir = Path(__file__).resolve().parent.parent / "resources"',
        'resources_dir = Path(__import__("os").environ.get("DEEPKOALA_RESOURCES", Path(__file__).resolve().parent.parent / "resources"))',
    )
    path.write_text(text)
PY

RUN pip install numpy==1.26.3 pandas==2.2.2 tqdm==4.66.4 \
    && pip install torch==2.4.1 --index-url https://download.pytorch.org/whl/cpu \
    && pip install /opt/deepkoala

CMD ["deepkoala", "--help"]
