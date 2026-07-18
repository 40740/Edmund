---
description: Remove git worktrees whose branch is already merged into main (runs scripts/prune-worktrees.sh)
argument-hint: [go] (omit for a dry run; pass "go" to actually remove)
allowed-tools: Bash(scripts/prune-worktrees.sh:*)
---

Run the hardcoded prune script from the repository root and report its output
verbatim. The logic lives entirely in the script — do not reimplement it.

```
scripts/prune-worktrees.sh $ARGUMENTS
```

- No argument ⇒ dry run: prints the plan (which worktrees are prunable and why
  each other is skipped), changes nothing.
- `go` ⇒ removes every prunable worktree (auto-unlocking locked ones first) and
  deletes its merged branch.

The script only removes worktrees whose branch is merged into `origin/main`, are
clean, and are neither the current nor the main worktree. It never force-removes
and never deletes an unmerged branch. After running, relay exactly what it
removed and what it skipped.
