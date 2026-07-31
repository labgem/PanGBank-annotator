FROM mambaorg/micromamba:2.0.5

COPY --chown=$MAMBA_USER:$MAMBA_USER modules/local/envs/panfam/environment.yml /tmp/panfam.yml

RUN micromamba install -y -n base -f /tmp/panfam.yml \
    && micromamba clean --all --yes

ENV PATH=/opt/conda/bin:$PATH
