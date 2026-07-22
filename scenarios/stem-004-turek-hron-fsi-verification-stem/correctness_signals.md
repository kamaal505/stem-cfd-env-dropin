<!--
DRAFT, 2026-07-23. Written against grader-authoring-cheatsheet.md's five-section structure and
authentic-difficulty-principle.md's standard. Grounded in this session's own golden-solution
work (internal_tooling/stem-004-turek-hron-fsi/) — every trap named below is a real bug we hit,
not a hypothetical, and the acceptance bar reflects the scope decision confirmed 2026-07-23
(README.md): physically plausible over a demonstrable ~0.5s window, not tight multi-period
reference-matching. Not yet regraded against transcripts - a draft to iterate, per the correctness
loop's own stated bar ("brief quality, not a score threshold").
-->

## Domain & architecture context

`projects/flag-fsi/` extends the verified rigid cylinder-flow solver (`projects/cylinder-flow/`,
frozen, HLX-341) to a fluid-structure interaction case: a thin elastic baffle clamped to the
downstream side of the same cylinder, deflecting and moving under the flow rather than staying
rigid. `geometry.py` and `cases.py` are pre-built and pin the mesh (fluid and solid subdomains,
tagged boundaries including the fluid-solid interface) and the benchmark parameters (fluid
density/viscosity/inflow, solid density/stiffness, geometry) — these are fixed and not the
agent's to rederive or retune. Everything else — the ALE mesh-motion solver, the solid-mechanics
solver, the fluid solver, and the coupling between all three — is unimplemented. The production
case is expensive; a smoke case exists in `cases.py` to iterate against, the same relationship
`dfg2d3-smoke` had to `dfg2d3` in the rigid case.

## What to watch for

**Mesh motion solved incrementally on an already-deformed mesh, rather than always from the
reference configuration.** A vector-Laplace (or elasticity) extension of the interface
displacement into the fluid mesh is the standard approach, but if it's re-solved each step
starting from the *previous step's already-moved* mesh rather than always mapping from the
pristine undeformed reference, distortion compounds and the mesh degrades (cells shrink toward
inversion) far faster than the true displacement amplitude would predict — in our own
implementation this failed at roughly half the eventual required displacement before the fix.
The fix is a convention (always reset to reference before solving, apply the *total*, not
incremental, displacement), not a stronger mesh-stiffening parameter — an attempt that responds
to mesh degradation by cranking up stiffening without changing the reference convention is
solving the wrong problem and should not be credited as progress.

**A converged nonlinear solve that is nevertheless wrong.** A Newton/SNES solve reporting
"converged" is not sufficient evidence of correctness — in our own solid-mechanics
implementation, a bad line-search configuration converged smoothly but produced a static
deflection roughly 18x smaller than a from-scratch cross-check predicted, and mesh refinement
made the discrepancy *worse*, which is itself the tell (a real discretization/locking issue
improves with refinement; a solver-configuration bug does not). A submission that reports a
converged run without any independent cross-check of the result (a simplified-limit comparison,
a sanity bound, a conservation check) has not actually verified anything, regardless of what the
solver's own convergence flag says.

**Static deflection reported as the answer for a case whose defining behavior is sustained
oscillation.** The protocol/ticket context establishes (via the vendor bench-test observation,
not a numeric hint) that the baffle does not settle to a fixed position — it keeps moving. A
submission that runs only long enough to see the baffle deflect and hold, and reports that as
the verification result, has not captured the case's actual physics, however clean the numbers
look. Mirrors the smoke-case trap from the rigid benchmark (`stem-003`'s "reporting smoke output
as the verification result is cheap, plausible, and wrong") in a new form.

**Interface traction/velocity sign or direction errors at the fluid-solid boundary.** Newton's
third law requires the solid's load from the fluid and the fluid's boundary condition from the
solid to be consistent (opposite tractions, matching velocities) at the shared interface. A sign
error here often still produces a solution that runs to completion and looks physically
plausible at a glance (some deflection, some flow) while being quantitatively and often
qualitatively wrong (e.g., the baffle deflecting the wrong direction, or the coupling appearing
far stiffer or softer than the pinned material parameters imply).

**Coupling-scheme choice treated as free of consequence.** Monolithic and partitioned
(staggered) coupling are both legitimate, real techniques — this is not a case where only one
"correct" answer exists. But a naive one-pass partitioned scheme (no sub-iteration within a
timestep) is known to risk the added-mass instability at density ratios like this baffle's
(solid notably denser than the fluid it sits in) — our own implementation of exactly this
scheme reproduced that instability empirically: stable and smooth at first, then increasingly
noisy growth, then outright solver failure, well before covering the case's required duration.
A submission that chooses a one-pass partitioned scheme and either doesn't notice it becomes
unstable, or notices and doesn't address it (via sub-iteration, relaxation, or switching
approach), has not delivered a working verification — but a submission that chooses partitioned
coupling *and* handles the stability question (sub-iterating to convergence, applying
relaxation, or explicitly justifying a monolithic choice instead) should be credited for sound
engineering judgment, not penalized for not defaulting to monolithic.

**Reference comparison that isn't a real, reproducible computation.** Same standard the rigid
case set: the deviation numbers in the PR/report must come from loading the actual reference
series and computing against the actual production run, not hardcoded or asserted values.

## Wrong-but-plausible failures

1. **One-pass staggered coupling presented as the final verification result**, without
   sub-iteration or any acknowledgment of stability risk. Produces a real run, real numbers, and
   a plausible-looking (if short-lived) trajectory before failing or being cut off early — easy
   to mistake for a working result if the run isn't carried far enough to see the instability.
2. **Mesh-motion solved incrementally rather than from the reference configuration**, as
   described above — silently degrades mesh quality over many steps rather than failing loudly
   on step one, so it can pass a short smoke test while being unsound for the production case.
3. **A "converged" solid or fluid solve that is quantitatively wrong** due to solver
   configuration (e.g., an unglobalized or badly-globalized nonlinear solve), with no
   independent sanity check to catch it.
4. **Reporting static-deflection behavior as the verified result** for a case whose defining
   behavior is sustained oscillation, because the run wasn't carried far enough in time to see
   the oscillation establish.

## Don't penalize for

- **Choice of coupling scheme** (monolithic vs. partitioned/staggered), provided the choice is
  made deliberately and its stability implications are actually handled — see above.
- **Choice of mesh-motion technique** (harmonic/Laplace extension, linear elasticity extension,
  or another legitimate approach), provided it's applied consistently from the reference
  configuration and demonstrably keeps the mesh valid over the run.
- **Not reaching a full multi-period, indefinitely-stable run.** The verified window only needs
  to be physically plausible and demonstrably stable over a reasonable duration — it does not
  need to run indefinitely or match a published reference series to tight numerical tolerance.
  A submission that is honest about the extent of what it validated, and why, should not be
  penalized for not chasing indefinite stability.
- **Legitimate alternative discretizations, timesteps, or solver configurations**, provided they
  are justified and the result is verified against something (a cross-check, a conservation
  property, a sanity bound), not merely asserted.

## Feel of a correct answer

A correct submission implements all three physics pieces (mesh motion, solid mechanics, fluid)
and a coupling between them, runs the production case far enough in time to see the baffle begin
a real, sustained oscillation rather than settling to a static deflection, and reports that
result alongside some form of independent verification (a cross-check against a simplified
limit, a conservation property, or a comparison against the published reference series' order of
magnitude and qualitative character) — not just "it ran and didn't crash." It does not need to
reproduce the published reference series to tight numerical tolerance, and legitimate
engineering choices (coupling scheme, mesh-motion technique, timestep) can differ from any
particular reference implementation provided they're deliberate and the result is verified, not
asserted. A PR/report that names what was and wasn't validated, and why, reads as trustworthy in
the same way the rigid-case verification report did.
