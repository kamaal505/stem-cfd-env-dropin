# stem-cfd-env-dropin — hand-off vehicle for `project-vertical-stem`

We (the STEM domain expert workspace) lack write access to
`toloka-partners/project-vertical-stem`, so this personal-fork repo is how our CFD
environment and scenario packages get to Leo for review/merge — one branch per
piece, each branched fresh off `main`. **This branch (`stem-004-testcase`) carries
two things:** the `phys-fem-fenics-vc` environment (below) and the
`stem-004-turek-hron-fsi-verification-stem` scenario package
(`scenarios/stem-004-turek-hron-fsi-verification-stem/`).

**What actually made `stem-004` run on Taiga was a separate, manual step** — the
scenario's files (`prompt.txt`, `jira_issues.json`, `slack.json`, `docs.json`,
`repos/a-vc-stem-lab.tar.gz`) were uploaded directly through Taiga's Preloaded
Files field at registration time, and the grading prompts pasted into each
grader's `override_grader_prompt`; none of that depends on this branch being
merged. Merging `scenarios/stem-004-turek-hron-fsi-verification-stem/` into the
live repo's own `scenarios/` tree keeps the canonical catalog in sync (and is
presumably what any future automated-registration path will read from), but it is
not what's currently serving the running problem. Full mechanics, including how
this reconciles with the older "everything is baked into the image" assumption
this repo's original README was written under: `knowledge_docs/taiga-deployment.md`
in the main workspace.

## The environment: `phys-fem-fenics-vc` (FEM/CFD on the VC lab)

A task image for `stem-company`-type scenarios (Jira/Slack/Docs/Gitea mocks —
the same profile `vstem-mcp` calls `image_profile: "company"`):

```
vstem-mcp company-profile essentials (taiga + Jira/Slack/Docs mocks + Gitea/sqlite)
  + a conda-forge FEniCSx stack (dolfinx 0.10, gmsh 4.15, numpy 2)
```

It is a **faithful lean subset** of `platform/vstem-mcp/Dockerfile`: every kept
section is copied verbatim, and only the services a CFD task never uses are
dropped (MongoDB, Redis, PostgreSQL, Kafka, Apache, Playwright, Node). The
Jira/Slack/Docs mocks are file-backed and Gitea is sqlite, so nothing removed
backs a tool a scenario actually uses. This image is **generic across scenarios**
— it carries the conda/FEniCSx stack and the `vstem-mcp` server code, not any
particular scenario's content (see the hand-off note above).

### Build

The Dockerfile builds with the **`project-vertical-stem` repo root as context**
(it `COPY`s `./taiga`, `./image`, `./platform/vstem-mcp`, `./test-infra`), the
same as the other environment images under `labs/pool/`:

```bash
# from the project-vertical-stem repo root
docker build --platform linux/amd64 \
  -f labs/pool/phys-fem-fenics-vc/Dockerfile \
  -t <registry>/vstem-mcp:phys-fem-fenics-vc-<tag> .
```

`build_and_verify.sh` does the build plus both checks below against a staged
lean context; see it for the exact commands. A rebuild is only needed when this
environment's own code changes (conda/FEniCSx stack, `vstem-mcp` server code) —
never for a scenario's prompt/world-file/grader-prompt content.

### Verified end-to-end (built locally, amd64 under emulation)

| Check | Result |
|---|---|
| Image builds (taiga, gitea init, conda dolfinx) | pass |
| Build-time science smoke | `dolfinx 0.10.0 \| numpy 2.4.6 \| gmsh 4.15.2` |
| A scenario's unit tests, in-image | pass |
| A solver smoke case, in-image | pass |
| `vstem_mcp` imports without the dropped DBs | pass |
| MCP server initializes over stdio, `--offline` | pass (`serverInfo:{name:taiga}`) |

### Two design decisions worth knowing

1. **conda-forge science, not the apt PPA — forced by a version mismatch.**
   The platform pins system python to 3.11; the jammy PPA's `python3-dolfinx` is
   built for 3.10, so apt would leave `import dolfinx` broken. conda-forge
   dolfinx installs on 3.11 and, as a bonus, ships gmsh 4.15 (the apt gmsh on
   jammy is 4.8 and **segfaults** on the benchmark's quad mesh) and runs on
   numpy 2 (no ABI pin). Uses **Miniforge + the conda-forge channel only** — no
   Anaconda `defaults` channel, so no Anaconda commercial-license question.
2. **Lean fork, to reconcile with the production `vstem-mcp` image.** This drops
   whole unused services rather than rewriting anything, so it can be diffed
   against the full `platform/vstem-mcp/Dockerfile` section by section.

### Two latent bugs in the catalogued `phys-fem-fenics` base

Found while building this: apt's gmsh (4.12/4.8) **segfaults** on quad meshes via
`Mesh.Algorithm=8`, and the base's `pip install --upgrade "numpy<2.0"` is a
**no-op** (apt numpy already satisfies it, so the shadowing copy is never
installed). Neither is caught by the base's build-time smoke, which only imports
dolfinx and meshes nothing. Both are avoided here by the conda-forge stack.
Fix deferred to a separate issue against the catalogued base, not fixed in place
here.

## The scenario: `stem-004-turek-hron-fsi-verification-stem`

`scenarios/stem-004-turek-hron-fsi-verification-stem/` — a `stem-company`-type
scenario (Turek–Hron FSI verification), currently registered and running on Taiga
via manual Preloaded Files upload (see the hand-off note above for why this
branch being merged isn't what makes it run). Package anatomy, grading strategy,
and current calibration status: `DELIVERED_TASKS.md` and
`internal_tooling/stem-004-turek-hron-fsi/README.md` in the main workspace.
