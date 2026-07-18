#!/bin/bash
#
# Prune git worktrees whose branch is already merged into origin/main.
#
# Conservative and deterministic. A worktree is removed only when ALL hold:
#   - it is NOT the main working tree and NOT the worktree this script runs in
#   - its branch is an ANCESTOR of origin/main (a real merge — squash/rebase
#     merges are not ancestors and are left alone for manual review)
#   - its working tree is clean (no uncommitted changes)
# Locked worktrees that otherwise qualify are auto-unlocked first (the current
# and main worktrees are never touched, lock or no lock).
#
# Usage:
#   scripts/prune-worktrees.sh          # dry run: print the plan, change nothing
#   scripts/prune-worktrees.sh go       # actually unlock/remove the prunable ones
#
# After removing a worktree, its branch is deleted with `git branch -d` (safe:
# only deletes if merged). Never force-removes, never touches an unmerged branch.
set -euo pipefail

MODE="${1:-dry}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
# The worktree this script is executing in — never remove it.
CURRENT="$REPO_ROOT"
# The main working tree (first entry of `git worktree list`) — never remove it.
MAIN_WT="$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)"

cd "$MAIN_WT"
git fetch origin main --quiet

# --- parse `git worktree list --porcelain` into parallel arrays ---
paths=(); heads=(); branches=(); locks=()
p=""; h=""; b=""; l="-"
flush() { [ -n "$p" ] && { paths+=("$p"); heads+=("$h"); branches+=("$b"); locks+=("$l"); }; p=""; h=""; b=""; l="-"; }
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    "worktree "*) flush; p="${line#worktree }" ;;
    "HEAD "*)     h="${line#HEAD }" ;;
    "branch "*)   b="${line#refs/heads/}"; b="${b#branch refs/heads/}" ;;
    "detached")   b="(detached)" ;;
    "locked"*)    l="LOCKED" ;;
  esac
done < <(git worktree list --porcelain)
flush

printf '%-52s %-42s %s\n' "WORKTREE" "BRANCH" "VERDICT"
prune_paths=(); prune_branches=(); prune_locked=()
for i in "${!paths[@]}"; do
  wp="${paths[$i]}"; wh="${heads[$i]}"; wb="${branches[$i]}"; wl="${locks[$i]}"
  name="${wp##*/}"
  if [ "$wp" = "$MAIN_WT" ]; then                                   v="main worktree (skip)"
  elif [ "$wp" = "$CURRENT" ]; then                                 v="current (skip)"
  elif [ "$wb" = "(detached)" ]; then                               v="detached HEAD (skip)"
  elif ! git merge-base --is-ancestor "$wh" origin/main 2>/dev/null; then v="not merged / squash (skip)"
  elif [ -n "$(git -C "$wp" status --porcelain 2>/dev/null)" ]; then v="dirty (skip)"
  else
    v="PRUNABLE"; [ "$wl" = "LOCKED" ] && v="PRUNABLE (auto-unlock)"
    prune_paths+=("$wp"); prune_branches+=("$wb"); prune_locked+=("$wl")
  fi
  printf '%-52s %-42s %s\n' "$name" "$wb" "$v"
done

echo ""
echo "Prunable: ${#prune_paths[@]}"
if [ "${#prune_paths[@]}" -eq 0 ]; then exit 0; fi

if [ "$MODE" != "go" ] && [ "$MODE" != "--force" ]; then
  echo "(dry run — pass 'go' to remove)"
  exit 0
fi

echo "=== removing ==="
for i in "${!prune_paths[@]}"; do
  wp="${prune_paths[$i]}"; wb="${prune_branches[$i]}"
  if [ "${prune_locked[$i]}" = "LOCKED" ]; then
    git worktree unlock "$wp" && echo "unlocked: ${wp##*/}"
  fi
  if git worktree remove "$wp"; then
    echo "removed worktree: ${wp##*/}"
    if git branch -d "$wb" >/dev/null 2>&1; then
      echo "  deleted branch: $wb"
    else
      echo "  branch kept (not safe-deletable): $wb"
    fi
  else
    echo "SKIP (remove failed): ${wp##*/}"
  fi
done
git worktree prune
echo "=== done ==="
git worktree list
