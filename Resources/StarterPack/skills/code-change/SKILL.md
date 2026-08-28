---
name: code-change
description: Implement a bounded code, configuration, script, or GUI change with preservation checks, proportional validation, Git branching, Pull Request review, merge, and local synchronization when authorized. Use for fixes, features, refactors, and repository changes.
compatibility: Git project with project-specific instructions and available build or validation commands.
---

# Code Change

Use this workflow for repository mutations. Project-local instructions determine the exact Git and validation policy.

## 1. Confirm scope and authorization

- Confirm that the user requested a change, not only an explanation or diagnosis.
- Read the active project's instructions.
- Identify whether push, Pull Request creation, and merge are authorized for this repository.

## 2. Protect existing work

- Inspect branch, upstream, staged files, unstaged files, and untracked files.
- Preserve unrelated changes and do not clean, reset, checkout, or overwrite them.
- If the requested change overlaps unsafe uncommitted work, stop and explain the conflict.

## 3. Establish the branch

When the project requires branch-based development:

1. synchronize the remote default branch using the project's approved method;
2. create a descriptive feature branch from the verified baseline;
3. confirm that implementation occurs on the feature branch, not directly on the default branch.

Do not perform external Git writes unless authorized by the project or user.

## 4. Implement incrementally

- Inspect the relevant code path before editing.
- Prefer the smallest coherent patch.
- Follow existing architecture and style unless the task explicitly requests a redesign.
- Avoid unrelated cleanup, speculative abstraction, dependency additions, or broad formatting.
- Keep blocking file scans, Git work, and expensive parsing away from GUI main threads.

## 5. Validate proportionally

Use the strongest relevant evidence available:

- static checks and diff validation;
- focused tests for changed behavior;
- full build when compilation or packaging is affected;
- signing or packaging checks for desktop delivery;
- real UI interaction for GUI behavior;
- runtime/API compatibility checks when interfaces are version-sensitive.

Do not claim test coverage that was not executed.

## 6. Review before integration

- Inspect the complete branch diff against the target branch.
- Check for credentials, private paths, generated artifacts, and unintended files.
- Record findings by severity; fix blocking findings on the same branch.
- Re-run affected validation after review fixes.

## 7. Integrate when authorized

For repositories that require Pull Requests:

1. commit the validated change;
2. push the feature branch;
3. create a Pull Request with outcome and validation evidence;
4. inspect remote diff, checks, and review state;
5. merge only after review passes;
6. synchronize the local default branch and confirm a clean state.

## Output format

```markdown
## Changed

## Validation

## Review findings

## Pull request and merge

## Local repository state
```

If integration is not authorized, stop after the local commit or validated working tree and state exactly what remains.
