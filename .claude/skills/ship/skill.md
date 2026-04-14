---
name: ship
description: Use when work is done and ready to ship — commits, pushes, opens a PR against main, and runs PR review. One command to go from local changes to reviewed PR.
user_invocable: true
---

# Ship

Commit, push, open a PR, and review it — all in one command.

## Workflow

Execute these steps sequentially:

1. **Commit** all staged/unstaged changes with a conventional commit message (follow repo commit style)
2. **Push** the current branch to origin (with `-u` if no upstream is set)
3. **Open a PR** against `main` using `gh pr create`
4. **Review the PR** by invoking the `/review-pr` skill on the newly created PR
