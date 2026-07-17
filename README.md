# Proposed environment: `phys-fem-fenics-vc` (FEM/CFD on the VC lab)

A **proposed addition to `project-vertical-stem`**, shared for review. This repo
contains only the new files — not the `project-vertical-stem` tree — so nothing
of yours is duplicated here. Drop `environments/phys-fem-fenics-vc/` into your
repo and it slots in alongside the existing `environments/*` entries.

## What it is

A task image for the `-sdlc` FEM/CFD family:

```
eval-mcp VC-lab essentials (taiga + Jira/Slack/Docs mocks + Gitea/sqlite)
  + a conda-forge FEniCSx stack (dolfinx 0.10, gmsh 4.15, numpy 2)
```

It is a **faithful lean subset** of `eval-mcp/Dockerfile`: every kept section is
copied verbatim, and only the services a CFD task never uses are dropped
(MongoDB, Redis, PostgreSQL, Kafka, Apache, Playwright, Node). The Jira/Slack/
Docs mocks are file-backed and Gitea is sqlite, so nothing removed backs a tool
the task uses.

## Build

The Dockerfile builds with the **`project-vertical-stem` repo root as context**
(it `COPY`s `./taiga`, `./image`, `./eval-mcp`, `./test-infra`, `./testcases`),
exactly like the other environment images:

```bash
# from the project-vertical-stem repo root
docker build --platform linux/amd64 \
  -f environments/phys-fem-fenics-vc/Dockerfile \
  -t <registry>/stem-cfd-task:v1 .
```

`build_and_verify.sh` does the build plus both checks below against a staged
lean context; see it for the exact commands.

## Verified end-to-end (built locally, amd64 under emulation)

| Check | Result |
|---|---|
| Image builds (taiga, gitea init, conda dolfinx) | pass |
| Build-time science smoke | `dolfinx 0.10.0 \| numpy 2.4.6 \| gmsh 4.15.2` |
| The testcase's 15 unit tests, in-image | **15 passed** |
| The solver smoke case, in-image | pass (flux `7.15e-7`) |
| `eval_mcp` imports without the dropped DBs | pass |
| MCP server initializes over stdio, `--offline` | pass (`serverInfo:{name:taiga}`) |

## Two design decisions worth knowing

1. **conda-forge science, not the apt PPA — forced by a version mismatch.**
   eval-mcp pins system python to 3.11; the jammy PPA's `python3-dolfinx` is
   built for 3.10, so apt would leave `import dolfinx` broken. conda-forge
   dolfinx installs on 3.11 and, as a bonus, ships gmsh 4.15 (the apt gmsh on
   jammy is 4.8 and **segfaults** on the benchmark's quad mesh) and runs on
   numpy 2 (no ABI pin). Uses **Miniforge + the conda-forge channel only** — no
   Anaconda `defaults` channel, so no Anaconda commercial-license question.
   *If an apt-only variant is preferred to match the repo idiom, it is doable:*
   apt PPA dolfinx on python 3.10 + the gmsh pip wheel + a numpy<2 pin, with the
   CFD invoked via 3.10 rather than the default 3.11.
2. **Lean fork, to reconcile with production eval-mcp.** This drops whole unused
   services rather than rewriting anything, so it can be diffed against the full
   `eval-mcp/Dockerfile` section by section.

## Note on two latent bugs in the catalogued `phys-fem-fenics` base

Found while building this: apt's gmsh (4.12/4.8) **segfaults** on quad meshes via
`Mesh.Algorithm=8`, and the base's `pip install --upgrade "numpy<2.0"` is a
**no-op** (apt numpy already satisfies it, so the shadowing copy is never
installed). Neither is caught by the base's build-time smoke, which only imports
dolfinx and meshes nothing. Both are avoided here by the conda-forge stack.
