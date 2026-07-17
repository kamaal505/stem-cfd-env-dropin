# stem-003 environment — how it composes, and the one dependency we don't hold

> **Update 2026-07-17 (build #2) — the lean task image is BUILT and VERIFIED.**
> `Dockerfile.task` built to `stem-cfd-task:test` (3.38 GB) and passed
> end-to-end. Reproduce with `./build_and_verify.sh <project-vertical-stem path>`.
>
> | Check | Result |
> |---|---|
> | Image builds (all 38 steps: taiga, gitea init, conda dolfinx) | ✅ |
> | Build-time science smoke | `dolfinx 0.10.0 \| numpy 2.4.6 \| gmsh 4.15.2` |
> | Task tests in-image (conda env, py 3.11) | ✅ **15 passed** |
> | Task smoke case in-image | ✅ flux `7.15e-7` |
> | `eval_mcp` imports without the dropped DBs | ✅ |
> | MCP server initializes over stdio, `--offline` | ✅ `serverInfo:{name:taiga}` |
>
> So dropping Mongo/Redis/Postgres/Kafka/Apache/Playwright/Node is confirmed
> safe: the Jira/Slack/Docs mocks are file-backed and Gitea is sqlite, so nothing
> removed backs a tool the task uses. The `Dockerfile.task` now also bakes a
> `uv sync` pre-warm so the production `--offline` launch needs no network — a
> rebuild folds that in (the already-built image needs one `uv --directory
> /mcp_server sync` first).

> **Update 2026-07-17 — we now build our own task image.** `Dockerfile.task` in
> this folder is a **lean, self-contained** build: eval-mcp's VC-lab essentials
> (taiga + Jira/Slack/Docs mocks + Gitea/sqlite) **+** a conda-forge FEniCSx
> stack, dropping every eval-mcp service a CFD task doesn't touch (Mongo, Redis,
> Postgres, Kafka, Apache, Playwright, Node). It needs the `project-vertical-stem`
> repo as build context but **no prebuilt image and no eval-mcp base** — so we no
> longer wait on anyone. The `Dockerfile` alongside it (24.04, apt PPA) remains
> the *spec* of the science layer; `Dockerfile.task` is the runnable article.
>
> **Reusable for the whole FEM/CFD family**, not just stem-003: only the final
> `COPY ./testcases` and the conda package list are task/domain-specific.
>
> Two design calls, both forced by facts we verified:
> - **conda-forge science, not apt PPA.** eval-mcp pins system python to 3.11;
>   the jammy PPA's `python3-dolfinx` is built for 3.10, so apt would leave
>   `import dolfinx` broken. conda-forge dolfinx 0.10 installs on 3.11 and, as a
>   bonus, ships gmsh 4.15 (no 4.12 segfault) and runs on numpy 2 (no ABI pin) —
>   so both original "deltas" evaporate. It is exactly our verified local stack.
> - **Faithful subset, not a rewrite.** Every section kept is copied from
>   `eval-mcp/Dockerfile` unchanged, so taiga/gitea/mocks behave as in
>   production; only whole unused services are removed.


Resolved by reading the source repo (`project-vertical-stem`, main branch, 2026-07-17).

## There are two tracks, and our task needs the heavier one

| | **stem-swi track** | **eval-mcp track (VC lab)** |
|---|---|---|
| Image | `environments/<env>/Dockerfile` = science base + `generic_server` | `eval-mcp/Dockerfile` = Ubuntu 22.04 + the full lab |
| MCP tools | **two**: `setup_problem`, `grade_problem` | Jira, Slack, Docs, **Gitea**, email, deploy, … |
| Serves Jira/Slack/Docs? | **No** | **Yes** |
| Fits our `-sdlc` package | **No** | **Yes — this is the one** |

Our `prompt.txt` opens *"The relevant information is in Jira, Slack, and the lab
documentation"* and asks for a reviewed **pull request**. That world —
Jira + Slack + Docs + a Gitea repo the agent branches and PRs against — exists
**only** in `eval-mcp`. `generic_server` is 57 lines with two tools and none of
it. So the `-sdlc` track is `eval-mcp`, and both inherited worked examples
(`testcases/stem-00{1,2}-*-sdlc`) confirm it: they carry exactly our file set.

## The composition, and why the base version is not a blocker

Task images are **one base + layers**, not two containers: the science images
`COPY --from` `taiga-core` and the server into a science base; eval-mcp does the
analogous thing on its own base.

eval-mcp's base is **Ubuntu 22.04** (jammy) where the catalogued science bases
are 24.04. That looked like a conflict; it isn't. **Verified on a jammy image:**
the FEniCS PPA has a jammy release —

- `fenicsx` -> `2:0.10.0.1~ppa1~jammy1`
- `python3-dolfinx` -> `1:0.10.0.post3-2~ppa2~jammy9`

so DOLFINx 0.10 installs on the eval-mcp base directly. Jammy's default
`python3` is **3.10** (eval-mcp also installs 3.11/3.12); our `pyproject.toml`
is `requires-python >= 3.10`, so we are fine.

## The two deltas that survive, unchanged — and are corroborated by the repo

We arrived at both independently, then found the source already doing the same:

1. **gmsh from the pip wheel, not apt.** On jammy apt's `python3-gmsh` is
   **4.8.4** — older still than the 4.12.1 that segfaults on our quad mesh. The
   repo's own `environments/phys-fem-gmsh/Dockerfile.base` uses
   `pip install gmsh` (the 4.15 wheel) for exactly this reason. Self-contained
   wheel, base-independent.
2. **A real numpy<2 constraint.** `environments/phys-fem-fenics/Dockerfile`
   pins it with `uv pip install --constraint /tmp/numpy-pin.txt`, its comment
   giving the same ABI reason we found — and the difference from the *base*'s
   no-op `pip install --upgrade "numpy<2.0"` is exactly the gap we flagged. Our
   `Dockerfile` uses `PIP_CONSTRAINT`; either mechanism works.

`Dockerfile` in this folder is the FEniCSx science layer, verified end to end
(15 tests, smoke case, full production run). It is the **science half** to graft
onto the eval-mcp base — not a standalone task image, and never was: it has no
`/mcp_server`.

## The one dependency we don't hold

We cannot build the eval-mcp base from our authoring checkout — it needs the
`eval-mcp/`, `taiga/`, `scripts/`, `image/` trees and `build_docker.sh`, which
live in the source repo. So the task image is:

```
eval-mcp base (jammy + gitea + jira/slack/docs mocks + taiga)
  + FEniCS PPA (jammy: dolfinx 0.10 available)
  + pip gmsh 4.15 wheel        (delta 1)
  + numpy<2 constraint         (delta 2)
  + testcases/stem-003-cfd-cylinder-verification-sdlc/
```

Everything after the first line is ours and ready. The first line is what the
boss is assembling.

## The risk to watch in that assembly

The boss's note said he would *"start removing all the SDLC/VC stuff and make
this more specific to your needs."* **Our task depends on the VC-lab machinery**
— Jira, Slack, Docs and Gitea all come from `eval-mcp`, the "VC stuff." If that
is stripped rather than kept-and-renamed, the `-sdlc` world our package is built
around has no host. Worth confirming explicitly that the Jira/Slack/Docs/Gitea
tools survive whatever consolidation happens.
