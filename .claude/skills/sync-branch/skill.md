---
name: sync-branch
description: Safely sync a feature branch with main. Dry-runs to assess conflicts, chooses merge vs rebase based on complexity, verifies the build after, and auto-rolls back on failure. Use instead of manual git rebase/merge when integrating upstream changes.
user_invocable: true
---

# Sync Branch with Main

Safely integrate upstream changes from `main` into the current feature branch. This skill replaces manual `git rebase main` / `git merge main` with a structured process that prevents silent regressions.

## Step 1: Pre-flight checks

**CRITICAL: Update local main first.** All comparisons use the local `main` ref, so it MUST match the remote before anything else. Run this before any other command:

```bash
git fetch origin main:main
```

This fetches the latest remote main and fast-forwards the local `main` branch. If it fails (e.g., local main has diverged), fall back to:

```bash
git fetch origin main && git branch -f main origin/main
```

Then run these in parallel:

```bash
# Current branch info
git branch --show-current
git status --short

# How many commits on this branch since diverging from main
git log main..HEAD --oneline

# How many commits on main since we diverged
git log HEAD..main --oneline

# Files changed on this branch
git diff main...HEAD --name-only
```

**Abort if:**
- Working tree is dirty (uncommitted changes) — ask the user to commit or stash first
- Already on `main` — nothing to sync
- No new commits on main since divergence — already up to date, tell the user

Record:
- `BRANCH_COMMITS` = number of commits on this branch
- `BRANCH_FILES` = number of files changed on this branch
- `MAIN_COMMITS` = number of new commits on main

## Step 2: Dry-run conflict assessment

```bash
# Attempt a no-commit merge to see what conflicts arise
git merge --no-commit --no-ff main 2>&1
```

Capture the output. Then **always abort** the dry-run:

```bash
git merge --abort 2>/dev/null || true
```

Parse the dry-run output:
- Count the number of conflicting files
- List which files conflict
- Note if any conflicts are in "high-risk" files (services, large shared files, config files, project.pbxproj, project.yml)

## Step 3: Choose strategy

Use this decision matrix:

| Condition | Strategy |
|---|---|
| 0 conflicts | **Rebase** (clean history) |
| 1-2 conflicts in simple files, AND branch has ≤ 3 commits | **Rebase** (manageable) |
| 1-2 conflicts but branch has 4+ commits | **Merge** (too many replay steps for rebase) |
| 3+ conflicting files | **Merge** (less risky) |
| Any conflict in project.pbxproj | **Merge** then regenerate: `xcodegen` |
| 5+ branch files AND 3+ conflicts | **Stop and ask the user** — too risky for automated resolution |

**Tell the user which strategy you're choosing and why before proceeding.** Example:
> "3 files conflict and your branch has 7 commits — I'll merge main in (safer than replaying 7 commits through conflicts). Conflicting files: `Foo.swift`, `Bar.swift`, `ContentView.swift`."

## Step 4: Execute the integration

### If rebasing:

```bash
git rebase main
```

If a conflict occurs during rebase that you didn't expect from the dry-run, or if you're unsure about the resolution:

```bash
git rebase --abort
```

Then fall back to merge strategy. **Never guess at conflict resolution during rebase** — a bad resolution is invisible and causes regressions.

### If merging:

```bash
git merge main
```

Resolve conflicts one file at a time. For each conflict:
1. Read both sides of the conflict carefully
2. If the conflict is in generated files (project.pbxproj, build output), regenerate rather than manually resolving
3. If you're uncertain about intent of either side, **stop and ask the user**
4. After resolving, stage the file

Complete the merge:
```bash
git commit  # Accept default merge message, or write a descriptive one
```

## Step 5: Build verification

```bash
xcodebuild -scheme Garden -destination 'platform=macOS' build 2>&1 | tail -5
```

If the build **fails**:

```bash
# Undo the merge/rebase
git reset --hard HEAD~1   # for merge (one merge commit)
# OR
git rebase --abort         # if rebase was in progress
```

Report to the user:
- The build failed after integration
- Show the build error
- The integration has been rolled back
- Suggest they investigate the build failure before trying again

## Step 6: Summary

Report to the user:

```
**Branch synced with main**

**Strategy:** merge/rebase (reason)
**Conflicts resolved:** N files (list them)
**Build:** passed / failed (rolled back)
**Commits integrated:** N commits from main
```

## Important rules

- **Never force-push** without explicit user approval
- **Never silently resolve conflicts** — if you're uncertain about either side of a conflict, ask
- **Never skip build verification**
- **Always roll back on build failure** — a broken build means the resolution was wrong
- If the user says "just rebase" but the heuristics say merge is safer, explain why and let them override if they insist
