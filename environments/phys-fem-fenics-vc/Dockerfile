# syntax=docker/dockerfile:1.4
#
# stem-003 / FEM-CFD task image — LEAN variant.
#
# = eval-mcp's VC-lab essentials (the world our -sdlc task needs)
#   + a conda-forge FEniCSx stack (the science the task runs on)
#
# Built FROM ubuntu:22.04 to match eval-mcp exactly, so taiga / gitea / the
# mock MCP tools behave identically to production. This is a faithful SUBSET of
# eval-mcp/Dockerfile: the sections our task uses, verbatim; the sections it
# does not, dropped.
#
# DROPPED vs. full eval-mcp (none of which a CFD task touches):
#   MongoDB, Redis, PostgreSQL, Kafka, Apache2 reverse-proxy, Playwright/
#   Chromium, Node.js. All serve web-app deploy / DB / browser testcases.
#   Gitea keeps its own sqlite3 backend; the Jira/Slack/Docs mocks are
#   file-backed (they read the testcase JSON), so nothing dropped is needed.
#
# SCIENCE via conda-forge, not the apt PPA, on purpose: eval-mcp pins the
# system python to 3.11, while the jammy PPA's python3-dolfinx targets 3.10 —
# a version mismatch that would leave `import dolfinx` broken. conda-forge
# dolfinx 0.10 installs cleanly on 3.11 and, as a bonus, ships gmsh 4.15 (no
# 4.12 quad-mesh segfault) and works on numpy 2 (no ABI pin) — the exact stack
# stem-003 was verified against locally.
#
# BUILD CONTEXT MUST BE the project-vertical-stem repo root (it COPYs ./taiga,
# ./image, ./eval-mcp, ./test-infra, ./testcases):
#   docker build --platform linux/amd64 \
#     -f Dockerfile.task -t stem-cfd-task:test  /path/to/project-vertical-stem

FROM ubuntu:22.04

ARG USERNAME="model"
ENV DEBIAN_FRONTEND=noninteractive

# ── model user (uid/gid 1000) ────────────────────────────────────────────────
RUN groupadd -g 1000 ${USERNAME} && \
    useradd -m -u 1000 -g 1000 ${USERNAME} && \
    gpasswd -d ${USERNAME} root || true

# ── core system deps (eval-mcp §2, minus node) ───────────────────────────────
WORKDIR /mcp_server
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo procps bash build-essential ca-certificates curl wget ssh \
    git git-lfs jq vim unzip gnupg lsb-release software-properties-common \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Python 3.11 (default) + 3.12, matching eval-mcp so taiga/eval-mcp resolve the
# same interpreter they do in production.
RUN add-apt-repository ppa:deadsnakes/ppa && apt-get update && \
    apt-get install -y python3.11 python3.11-venv python3.11-dev \
                       python3.12 python3.12-venv python3.12-dev python3-pip && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 2 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.11 2 && \
    update-alternatives --install /usr/bin/python  python  /usr/bin/python3.12 1 && \
    rm -rf /var/lib/apt/lists/*

RUN pip install uv ruff mypy psutil && rm -rf /root/.cache

# ── taiga package (eval-mcp §6) ──────────────────────────────────────────────
COPY ./taiga /mcp_server
RUN uv pip install --system -e . && rm -rf /root/.cache

# ── Gitea, sqlite backend (eval-mcp §7, verbatim) ────────────────────────────
RUN groupadd gitea && useradd -m -g gitea gitea && gpasswd -d gitea root || true
WORKDIR /gitea
RUN wget -O gitea https://github.com/go-gitea/gitea/releases/download/v1.24.0-rc0/gitea-1.24.0-rc0-linux-amd64 && \
    chmod +x gitea && mkdir -p custom/conf data log /var/lock/subsys
COPY ./image/gitea_conf.ini /gitea/custom/conf/app.ini
COPY ./image/gitea_service.sh /etc/init.d/gitea
COPY ./image/init_gitea.sh ./image/migrate_repoes.sh ./image/dump_diff_hook.sh /gitea/
RUN dos2unix /etc/init.d/gitea /gitea/init_gitea.sh /gitea/migrate_repoes.sh /gitea/dump_diff_hook.sh && \
    chown -R gitea:gitea /gitea && chmod -R 0700 /gitea && \
    chmod +x /etc/init.d/gitea /gitea/init_gitea.sh /gitea/migrate_repoes.sh /gitea/dump_diff_hook.sh
RUN /bin/bash /etc/init.d/gitea start && sleep 5 && \
    sudo -u gitea /gitea/init_gitea.sh && \
    /bin/bash /etc/init.d/gitea stop
RUN cp /gitea/model_access_token /home/model/.gitea_access_token && \
    chown model:model /home/model/.gitea_access_token && chmod 0600 /home/model/.gitea_access_token
COPY ./image/init_git_config.sh /home/model/
RUN dos2unix /home/model/init_git_config.sh && chmod +x /home/model/init_git_config.sh && \
    chown model:model /home/model/init_git_config.sh && \
    /bin/bash /etc/init.d/gitea start && sleep 3 && \
    sudo -u model /home/model/init_git_config.sh && \
    /bin/bash /etc/init.d/gitea stop && rm /home/model/init_git_config.sh

# ── eval-mcp app + test-infra + testcases (eval-mcp §9) ───────────────────────
WORKDIR /mcp_server/eval-mcp
COPY ./eval-mcp/src /mcp_server/eval-mcp/src
COPY ./eval-mcp/pyproject.toml /mcp_server/eval-mcp/pyproject.toml
COPY ./eval-mcp/uv.lock /mcp_server/eval-mcp/uv.lock
COPY ./eval-mcp/README.md /mcp_server/eval-mcp/README.md
RUN uv pip install --system -e . && rm -rf /root/.cache
COPY ./test-infra /mcp_server/test-infra
WORKDIR /mcp_server/test-infra
RUN uv pip install --system -e . && rm -rf /root/.cache
WORKDIR /mcp_server/eval-mcp
COPY ./testcases /testcases

# ============================================================
# Science layer — conda-forge FEniCSx (the stem-003 stack)
# ============================================================
# Installed as the model user's own conda so the agent gets dolfinx/gmsh/mpi on
# a python that actually imports them, independent of the system 3.11 that runs
# the eval-mcp server. Mirrors the locally-verified `fenicsx-env`.
ENV CONDA_DIR=/opt/conda
RUN arch="$(uname -m)" && \
    curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-${arch}.sh" -o /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p ${CONDA_DIR} && rm /tmp/miniforge.sh && \
    ${CONDA_DIR}/bin/conda config --system --set channel_priority strict
RUN ${CONDA_DIR}/bin/mamba create -y -n fenicsx-env -c conda-forge python=3.11 \
        fenics-dolfinx=0.10 mpich \
        numpy scipy pandas matplotlib gmsh python-gmsh meshio pytest && \
    ${CONDA_DIR}/bin/conda clean -afy
# Make the fenics env the model user's default python: login shells activate it.
RUN echo ". ${CONDA_DIR}/etc/profile.d/conda.sh && conda activate fenicsx-env" >> /home/model/.bashrc && \
    chown -R model:model ${CONDA_DIR}/envs/fenicsx-env 2>/dev/null || true

# Build-time science smoke: the whole stack imports together on one python.
RUN ${CONDA_DIR}/envs/fenicsx-env/bin/python -c "\
import dolfinx, gmsh, numpy, pandas, scipy, mpi4py; \
gmsh.initialize(); v=gmsh.option.getString('General.Version'); gmsh.finalize(); \
print('dolfinx', dolfinx.__version__, '| numpy', numpy.__version__, '| gmsh', v)"

# Pre-warm the uv project venv so the production launch command works with
# --offline (Taiga runs `uv --offline --directory /mcp_server run … mcp`, and
# with the Domain Allowlist empty the container has no network to resolve deps).
RUN uv --directory /mcp_server sync && rm -rf /root/.cache

# ── permissions + entrypoint (eval-mcp §9/§10) ───────────────────────────────
RUN chmod -R 0700 /testcases /mcp_server && \
    chgrp -R gitea /mcp_server && chmod -R g+rX /mcp_server
WORKDIR /home/model
CMD ["uv", "run", "eval_mcp", "mcp"]
COPY ./image/entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh
ENV HOME=/home/model
ENV GIT_AUTHOR_NAME="Claude"
ENV GIT_AUTHOR_EMAIL="noreply@anthropic.com"
ENV GIT_COMMITTER_NAME="Claude"
ENV GIT_COMMITTER_EMAIL="noreply@anthropic.com"
