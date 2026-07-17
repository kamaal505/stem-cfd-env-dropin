#!/bin/bash
# Build the lean stem-003 / FEM-CFD task image and verify both halves.
#
#   ./build_and_verify.sh /path/to/project-vertical-stem [image_tag]
#
# The repo is the build context (the Dockerfile COPYs ./taiga, ./image,
# ./eval-mcp, ./test-infra, ./testcases). Only those trees are needed; the
# script stages a lean context so a big .git isn't shipped to the daemon.
set -euo pipefail

REPO="${1:?usage: build_and_verify.sh <project-vertical-stem path> [tag]}"
TAG="${2:-stem-cfd-task:test}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$HERE/../../deliverables/stem-003-cfd-cylinder-verification-sdlc"
CTX="$(mktemp -d)"

echo "== staging lean build context =="
for p in taiga image eval-mcp test-infra testcases; do cp -R "$REPO/$p" "$CTX/$p"; done
find "$CTX" -name node_modules -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$CTX" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
cp "$HERE/Dockerfile.task" "$CTX/Dockerfile.task"

echo "== building $TAG (long under amd64 emulation; conda dolfinx + gitea init) =="
docker build --platform linux/amd64 -f "$CTX/Dockerfile.task" -t "$TAG" "$CTX"
rm -rf "$CTX"

echo "== verify 1/2: task science on the in-image conda env =="
V="$(mktemp -d)"; tar xzf "$PKG/repos/a-vc-stem-lab.tar.gz" -C "$V"
git clone -q "$V/repo_dump/testorg/a-vc-stem-lab/git" "$V/work"
docker run --rm --platform linux/amd64 -v "$V/work:/home/model/a-vc-stem-lab" "$TAG" bash -lc '
  source /opt/conda/etc/profile.d/conda.sh && conda activate fenicsx-env
  cd /home/model/a-vc-stem-lab && pip install -e . -q
  python -m pytest -q | tail -1
  cd projects/cylinder-flow && python run_case.py --case dfg2d3-smoke | tail -1'
rm -rf "$V"

echo "== verify 2/2: MCP server initializes over stdio (--offline) =="
docker run --rm -i --platform linux/amd64 "$TAG" bash -lc '
  printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"probe\",\"version\":\"0\"}}}" \
  | timeout 25 uv --offline --directory /mcp_server run eval_mcp mcp 2>/dev/null \
  | tr "," "\n" | grep -iE "protocolVersion|serverInfo" | head -3'

echo "== OK =="
