# Hermes Release Workflow Rollout Plan

> Goal: operationalize the new `theperch-release-workflow` skill so future ThePerch work consistently follows Bancada-grade framing, verification, visual QA, and release discipline.

## Why this exists

We now have a reusable Hermes skill that captures the best parts of Bancada's release discipline.
The next step is not building more process theater.
It is using the workflow consistently enough that it becomes muscle memory.

## Rollout outcome

For future ThePerch work, Hermes should reliably do the following:
- classify scope before coding
- run a CEO/product framing pass when the task is product-significant
- create or update an implementation plan when the task is multi-step
- enforce build/test verification before claiming done
- enforce visual QA for UI changes
- end with an explicit release verdict: `not release-ready`, `alpha-ready`, or `beta-ready`
- require the user approval before TestFlight deploys
- require explicit lane choice for deploys

## Rollout policy

### Default execution rules

1. Tiny non-UI fix
- no CEO pass by default
- no formal plan by default
- targeted verification required
- release verdict required

2. Medium or large feature
- CEO/product framing first
- written implementation plan required
- implementation can be direct or delegated
- verification and release verdict required

3. Any UI-touched change
- visual QA required
- screenshot evidence strongly preferred
- release verdict must mention visual inspection explicitly

4. Any deploy
- the user approval required
- lane must be explicit
- `alpha` is default recommendation unless evidence clearly supports `beta`

## Operating checklist for Hermes

### Stage 1: Scope classification
For every meaningful ThePerch task, decide:
- tiny fix / feature / UI change / release-sensitive patch
- product framing needed or not
- plan needed or not
- visual QA needed or not

### Stage 2: Product framing
Run a concise CEO-style recommendation when the task changes:
- user-facing behavior
- UI structure
- navigation
- product scope
- release posture

The framing should answer:
- what we are building
- why this shape
- what not to build
- what success looks like

### Stage 3: Planning
If the task is multi-step, create or update a plan in `docs/plans/`.
Preferred plan structure:
- goal
- architecture
- tech stack
- file map
- small tasks
- testing steps
- release concerns if relevant

### Stage 4: Execution
Execution can be done by:
- Hermes directly
- Codex worker
- Claude Code worker

But Hermes remains responsible for:
- exact task definition
- review
- build/test verification
- visual QA
- final release verdict

### Stage 5: Verification
Minimum verification expectations:
- relevant tests run
- build succeeds
- runtime smoke check passes where applicable
- explicit note if anything could not be verified

Preferred tools/scripts:
- `bash ~/.openclaw/workspace/scripts/run-tests.sh`
- `bash ~/.openclaw/workspace/scripts/readiness-gate.sh ~/Documents/Apps/ThePerch`
- `bash ~/.openclaw/workspace/scripts/qa-predeploy.sh ~/Documents/Apps/ThePerch`
- XcodeBuildMCP build/test/run/screenshot commands when better suited

### Stage 6: Visual QA
For UI work, inspect the actual changed surface.
Do not stop at "the app launched".
Check for:
- layout issues
- truncation
- spacing drift
- color mistakes
- empty/loading/error states
- flow readability
- interaction sanity

Use screenshot evidence where possible.

### Stage 7: Release verdict
Every meaningful task ends with one of:
- `not release-ready`
- `alpha-ready`
- `beta-ready`

### Stage 8: Deploy handling
If the user asks to deploy and approves it:
- choose lane explicitly
- use `deploy-testflight.sh --lane=alpha` or `--lane=beta`
- do not silently skip tests or QA for beta-grade recommendations

## Beta policy

Beta should be rare enough to mean something.

Do not recommend `beta-ready` unless all or nearly all of the following are true:
- relevant tests passed
- build passed
- runtime smoke check passed
- visual QA happened for changed UI
- screenshot evidence exists for UI work
- the changed flow was exercised end-to-end
- no blocker/regression/known UX concern remains
- skipped verification is not being hidden behind vague wording

If there is hesitation, recommend `alpha-ready`.

## Reporting template

For meaningful work, Hermes should prefer the Release Evidence block from:
- `theperch-release-workflow`
- `references/release-evidence-template.md`

Required reporting shape:
- scope
- product framing status
- files touched
- build result
- test result
- runtime verification
- visual QA result
- evidence
- gaps
- verdict
- deploy recommendation

## First live usage policy

For the next 3 meaningful ThePerch tasks:
- explicitly load `theperch-release-workflow`
- use the evidence block in the final report
- err toward `alpha-ready` unless the case for beta is boringly obvious
- call out any friction in the workflow so the skill can be tightened further

## Success criteria

This rollout is working if, over the next few ThePerch tasks:
- Hermes stops saying vague "done"
- UI work consistently includes visual verification
- release recommendations are explicit and evidence-backed
- deploys feel intentional, not casual
- the skill reduces improvisation instead of adding ceremony

## Non-goals

Do not add:
- extra queue bureaucracy
- mandatory CEO passes for tiny fixes
- beta recommendations without evidence
- deploy automation that bypasses approval

## Next step

Use this workflow on the next real ThePerch coding task and treat that as the first live trial.