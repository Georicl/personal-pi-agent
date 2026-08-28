---
name: project-start
description: Inspect an unfamiliar or newly selected project, identify its structure and constraints, and produce a bounded, verifiable execution plan. Use before implementing work when repository context, commands, risks, or completion criteria are not yet clear.
compatibility: Pi coding agent with read-only file and Git inspection tools.
---

# Project Start

Use this workflow to establish reliable project context before changing anything.

## 1. Establish the objective

- Restate the requested outcome in concrete terms.
- Identify whether the user asked for analysis, diagnosis, implementation, review, or planning.
- Do not infer authorization for implementation from a review-only or diagnosis-only request.

## 2. Inspect without mutation

Check only what is relevant:

- current working directory and canonical project root;
- Git branch and working-tree state;
- global and project context files;
- top-level structure and primary entry points;
- README, package manifests, dependency files, and build configuration;
- documented build, test, lint, and formatting commands;
- generated, protected, or user-owned paths.

Prefer fast targeted search over broad file dumping. Do not install dependencies or rewrite configuration during this phase.

## 3. Separate evidence from assumptions

Record:

- **Observed:** directly verified from files or commands.
- **Inferred:** likely but not yet verified.
- **Unknown:** information still needed for a safe implementation.

Resolve cheap, read-only unknowns before asking the user.

## 4. Define the smallest useful plan

Create ordered steps that each produce a verifiable result. Include:

- files or subsystems likely in scope;
- validation for each meaningful change;
- external actions that need authorization;
- rollback or preservation concerns when relevant.

Do not propose architecture expansion that is not needed for the requested outcome.

## 5. Define completion

State observable acceptance criteria. A criterion should describe behavior or evidence, not effort.

## Output format

```markdown
## Current state

## Relevant constraints

## Proposed plan

## Validation strategy

## Risks or unknowns

## Completion criteria
```

If the user requested implementation and the plan is safe and unambiguous, continue with the relevant implementation workflow. Otherwise stop after the plan.
