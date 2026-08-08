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
approach), has not delivered a working verification. A submission that chooses partitioned
coupling *and* demonstrably handles the stability question (sub-iterating to convergence,
applying relaxation, and showing the resulting run stays stable where the naive version did not)
should be credited for sound engineering judgment.

**A monolithic choice earns full credit only when it is backed by an actual run, not an estimate.**
Citing the density ratio and invoking "added-mass instability" by name is a correct fact, but
stating it is not the same as showing it — and a back-of-envelope stability bound is a lower bar
than this task's compute budget requires: nothing about the production case's cost prevents
actually running the cheaper alternative. Full credit on this signal requires actually executing a
truncated one-pass partitioned (staggered) run on the production case and showing it degrade
(growing noise, instability, or outright divergence) where the monolithic run stays stable — the
same empirical standard the rigid case set for the benchmark comparison itself. A back-of-envelope
estimate with no run behind it is worth partial credit at most. A submission that picks monolithic
purely on the strength of a qualitative, textbook-level statement, or a citation to prior published
validation of the same scheme, with no run of any kind on this case, has made a plausible-sounding
assertion, not an engineering judgment — this alone should cap overall correctness at roughly
**0.5**, regardless of how sound the rest of the implementation is, on the same "well short"
standard as the ramp-floor case below, not a fractional deduction on one signal among several.

**Attributing the amplitude/frequency gap to mesh resolution without ever running a finer mesh.**
A timestep (dt) refinement study addresses temporal resolution, not spatial resolution — it is not
evidence for a spatial-resolution hypothesis, however carefully it's described. A submission that
diagnoses "the mesh is too coarse" as the cause of a large quantitative gap must actually run at
least one finer spatial resolution (a smaller `res_min_factor`, or equivalent local refinement near
the baffle/interface) on the production case and show the amplitude/frequency trending toward the
reference — not merely assert plausibility from a temporal-refinement check or a citation to
another tool's published convergence behavior. Compute cost is not a constraint on this task; an
unexecuted hypothesis is not a diagnosis, and should be treated the same as the unverified
coupling-choice case above.

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
5. **Right qualitative behavior (sustained, non-decaying oscillation), wrong dynamical mode.** A
   forced, small-amplitude response driven by vortex shedding (or any other secondary excitation)
   can look like "sustained oscillation, not static deflection" at a glance — non-decaying,
   present in every time window, a clean spectral peak — while being an entirely different
   phenomenon from the self-excited flutter limit cycle the benchmark is defined by. A submission
   that only checks *whether* the tip keeps moving, without checking *at what frequency and
   relative to what forcing*, can clear the static-deflection trap while still having captured the
   wrong physics. Treat this the same as failure 4, not as a milder "amplitude is a bit off"
   finding — it is a different failure category from a converged-but-quantitatively-off result.

## Don't penalize for

- **Choice of coupling scheme** (monolithic vs. partitioned/staggered), provided the choice is
  made deliberately and its stability implications are actually handled — see above.
- **Choice of mesh-motion technique** (harmonic/Laplace extension, linear elasticity extension,
  or another legitimate approach), provided it's applied consistently from the reference
  configuration and demonstrably keeps the mesh valid over the run.
- **Not reaching a full multi-period, indefinitely-stable run** — *provided* the run that was
  actually achieved clears the inflow ramp and shows the tip motion beginning to depart from a
  monotonic, still-growing transient (a local peak, a sign change in velocity, amplitude ceasing
  to track the ramp profile) rather than stopping mid-ramp at a deflection still orders of
  magnitude below where the transient is expected to plateau. It does not need to run indefinitely
  or match a published reference series to tight numerical tolerance.

  **A run that ends while still deep in the ramp has not demonstrated anything about the baffle's
  dynamic behavior, however honestly that shortfall is reported, and should be scored as an
  incomplete verification on this signal — not merely discounted to "partial."** Honesty about a
  gap changes how a shortfall is judged; it does not convert a non-result into a result. If the
  environment's time budget makes even reaching past the ramp infeasible, a submission can still
  earn credit here by demonstrating the same physics on a cheaper stand-in that reaches the
  behavior (e.g. a coarser mesh, a shorter reference-matched sub-case, or a scaled-down analogue)
  and explaining why that stand-in is representative — silence past "I ran out of time" is not
  sufficient on its own.
- **Legitimate alternative discretizations, timesteps, or solver configurations**, provided they
  are justified and the result is verified against something (a cross-check, a conservation
  property, a sanity bound), not merely asserted.
- **A production or smoke run cut off by signal 15 (SIGTERM) rather than by the solver's own
  divergence.** The sandbox's bash tool can restart mid-run (its 300s-per-command limit against a
  multi-hour production case forces background execution) and this has been observed to kill an
  in-progress backgrounded solver process. In the transcript this appears as a PETSc/MPI abort
  immediately preceded by the line `Caught signal number 15 Terminate: Some process (or the batch
  system) has told this process to end`. That signature is an environment artifact, not evidence
  of Newton non-convergence, mesh inversion, a coupling instability, or any other physics/solver
  defect — do not score it against the signals above (converged-but-wrong, added-mass instability,
  mesh degradation, etc.). Evaluate the run on whatever genuine progress it reached before the
  signal, under the same ramp-floor standard as any other truncated run, and do not additionally
  penalize the submission for the harness-caused interruption itself. A crash showing the *same
  surface symptoms* (abort, non-convergence, inversion) but **without** the signal-15 line
  immediately preceding it is not covered by this exception and should still be evaluated as a
  genuine physics/solver failure under the relevant signal above.

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

A submission that never gets past the inflow ramp, and whose only evidence for its coupling
choice is a correctly-worded but unverified paragraph about added-mass instability, has produced
a plausible-sounding report, not a verification — score it well short of the above regardless of
how forthright its caveats are. Fluent, honest hedging is not a substitute for either running the
case far enough to see the physics or backing the coupling decision with a real number.

The same ceiling applies past the ramp. A submission that clears the ramp and reaches a genuine
sustained, non-decaying oscillation, but (a) never ran the cheaper staggered alternative it needed
to justify its coupling choice, or (b) never ran a finer mesh to test its own resolution
hypothesis, or (c) never checked whether the oscillation it captured is at the reference's
frequency rather than some other excited mode, has produced a well-engineered partial result, not
a completed verification. Cap it around 0.5, in the same "well short" territory as the pre-ramp
case — not a fractional deduction on one signal among several. Every one of these checks is
affordable within this task's compute budget; skipping them is a choice, not a constraint, and
honest reporting of the gap does not raise the ceiling.
