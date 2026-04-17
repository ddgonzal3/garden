# PR Review (Edit, Fix Loop & Stage)

You are a senior engineer orchestrating a thorough, iterative code review. Your goal is to leave the code **meaningfully better** than you found it.

**CRITICAL: All review work MUST be delegated to Task agents.** The main agent handles only orchestration (branch detection, merging findings, applying fixes, staging, and reporting). This keeps the main conversation context clean and unaffected by the volume of code read during review.

## Step 1: Determine the Base Branch (Main Agent)

This is lightweight — do it directly.

1. **If PR number provided**:

   ```bash
   gh pr view <number> --json baseRefName,headRefName,files
   ```

2. **If branch name provided**:

   ```bash
   gh pr list --head <branch-name> --json number,baseRefName
   # If no PR exists, ask the user for the target branch
   ```

3. **If "current branch" or no input**:
   ```bash
   gh pr view --json baseRefName,number 2>/dev/null
   # If no PR, detect default branch
   git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
   ```

Store: `BASE_BRANCH="<determined-base>"`

## Step 2: Collect Changed File List (Main Agent)

**IMPORTANT: Use the PR's actual diff, not the raw git diff against the base branch.** Long-lived branches may share a merge-base far back in history, causing `git diff $(git merge-base HEAD $BASE_BRANCH)...HEAD` to include hundreds of already-merged commits. Always prefer `gh pr diff` which shows exactly what the PR changes.

Run these commands to get the file list and stats — but do NOT read the files yourself:

```bash
# Use GitHub's PR diff — this is the authoritative set of changes for the PR
gh pr view <PR_NUMBER> --json files --jq '.files[] | "\(.path) +\(.additions) -\(.deletions)"'
gh pr diff <PR_NUMBER> --name-only

# Commit log for just the PR's commits (not the full branch history)
gh pr view <PR_NUMBER> --json commits --jq '.commits[].messageHeadline'
```

Use the file count to decide the review strategy in Step 3.

## Step 3: Delegate Review to Task Agents

**All code reading and review happens in subagents.** Never read changed files or diffs in the main context.

### Small PRs (1-4 files, single layer)

Launch **two** Task agents in parallel (subagent_type: `general-purpose`):

**Agent 1 — Code Review:** Standard code review with this prompt structure:

```
You are a senior engineer doing a thorough code review. Review the PR diff and changed files against the checklist below.

BASE_BRANCH: <base>
Changed files: <file list>

## Instructions

1. Run: gh pr diff <PR_NUMBER>
2. Read each changed file completely
3. Understand what the PR is trying to accomplish
4. Review against EVERY checklist category below
5. For each issue found, note: file, line, severity, description
6. Return your findings in the structured format at the bottom

<include checklist sections 1-8 from below>
<include the Severity Levels from below>
<include the Output Format from below>
```

**Agent 2 — Agent Implications:** Checks if the PR affects AI agent capabilities. Use the prompt structure from checklist section 9 below.

### Large PRs (5+ files or multiple layers)

Launch **four** Task agents in parallel (subagent_type: `general-purpose`), each with a focused perspective. Give each agent the same base context (branch, file list, instructions to read the diff and files) but different checklist sections:

| Agent      | Focus Areas                                                              | Checklist Sections |
| ---------- | ------------------------------------------------------------------------ | ------------------ |
| Reviewer A | Architecture, **file size & modularity**, patterns, DRY, service bounds  | 3, 3b, 4          |
| Reviewer B | Correctness, security, edge cases, resource cleanup                      | 1, 2, 6           |
| Reviewer C | Readability, type safety, PR hygiene, dead code                          | 5, 7, 8           |
| Reviewer D | **Agent implications** — checks if changes affect AI agent capabilities  | 9 (below)          |

Each agent prompt should include:
- The PR number and file list
- Instructions to run `gh pr diff <PR_NUMBER>` and read all changed files
- Only their assigned checklist sections
- The severity levels and output format

### Review Checklist (Include in Agent Prompts)

#### Severity Levels

- **Critical** — Must fix before merge. Bugs, security issues, data integrity risks, broken functionality. Also: files over 500 lines mixing distinct concerns (must be split).
- **Suggestion** — Should strongly consider. Readability improvements, better patterns, missing edge cases. Also: files over ~300 lines that could be split, or code that clearly belongs in its own module.
- **Nitpick** — Optional. Style preferences, minor naming improvements, cosmetic issues.

#### 1. Correctness (Critical priority)

- [ ] Logic handles all expected inputs correctly
- [ ] No off-by-one errors, nil hazards, or force-unwrap issues
- [ ] Error handling is present and appropriate (not swallowing errors silently)
- [ ] No race conditions in async code (MainActor usage, proper actor isolation)
- [ ] Resources are cleaned up (Combine subscriptions via `AnyCancellable`, file handles closed)
- [ ] State mutations happen at the right time (not in `init` for ObservableObjects, proper `@Published` usage)

#### 2. Security

- [ ] No hardcoded secrets, API keys, or credentials
- [ ] File paths from user input are validated before filesystem calls
- [ ] JSON data is properly validated before parsing
- [ ] Keychain usage follows best practices (no plaintext storage of sensitive data)

#### 3. Architecture

- [ ] Changes follow existing patterns (Views for UI, Services for logic, Store for state)
- [ ] Correct layer separation (Views don't contain business logic, Services don't contain UI code)
- [ ] No DRY violations — check if similar code already exists in shared services
- [ ] New utilities are placed in the correct location (shared service vs. local to feature)
- [ ] No circular dependencies introduced
- [ ] State flows through BacklogStore as single source of truth

#### 3b. File Size & Modularity (High Priority)

**Check every changed file for size and cohesion.** This is a first-class review concern, not an afterthought.

1. **Measure the TOTAL line count** of each changed file (the whole file on disk, not just the diff). Run `wc -l` on every changed source file.
2. **Flag files over ~300 lines** as candidates for splitting into smaller, focused modules. Consider:
   - Can logically distinct sections (e.g., separate view components, utility helpers) be extracted into their own files?
   - Are there groupings of related functions that form a natural module boundary?
   - Is a single struct/class doing too many things (violating Single Responsibility)?
3. **Flag code that belongs in its own file regardless of file length.** Examples:
   - Large blocks of constants or config inlined in a service/view file
   - Utility/helper functions mixed into a view that aren't specific to it
   - Multiple distinct concerns crammed into one file
   - Model definitions that have grown large enough to warrant their own file
4. **Severity:**
   - **Critical** — Files over 500 lines that mix clearly distinct concerns. These MUST be split before merge.
   - **Suggestion** — Files over ~300 lines, or shorter files with code that obviously belongs elsewhere. Should strongly consider splitting.
5. **In the report**, include a dedicated **File Size & Modularity Report** section listing every file over 300 lines with its line count and what could be extracted.

#### 4. Code Cleanliness

- [ ] Functions are small and focused
- [ ] Naming is clear and descriptive (follows project conventions)
- [ ] No dead code, commented-out code, or TODOs without context
- [ ] No magic numbers — constants are extracted and named
- [ ] Complex logic is extracted into well-named helper functions
- [ ] No unused imports, variables, or properties

#### 5. Readability

- [ ] Code intent is clear without excessive comments
- [ ] Comments explain "why", not "what"
- [ ] Consistent style with the rest of the codebase
- [ ] React components are readable (complex logic extracted to helper functions or sub-components)
- [ ] Prop chains and hook dependencies are clear (not deeply threaded without justification)

#### 6. Performance

- [ ] No unnecessary re-renders (proper use of `useMemo`, `useCallback`, stable refs)
- [ ] Large lists are virtualized where needed
- [ ] No N+1 patterns in data access (repeated filtering in loops)
- [ ] File I/O is async and not blocking UI (Tauri `fs` plugin calls)
- [ ] Expensive computations are cached or memoized where appropriate
- [ ] No stale closures in effect handlers

#### 7. Type Safety

- [ ] No non-null assertions (`!`) unless truly safe with a comment explaining why
- [ ] No `as unknown as T` casts — use proper type guards
- [ ] Proper handling of optional/undefined values (no hidden logic errors)
- [ ] JSON parsing handles all edge cases (missing keys, wrong types) via `normalizeProject`
- [ ] Unions/enums preferred over stringly-typed values where appropriate

#### 8. PR Hygiene

- [ ] Changes are focused on a single concern (not mixing features with unrelated refactors)
- [ ] No unrelated formatting or whitespace-only diffs
- [ ] No temporary debug logging left in (`console.log`, `debugger` calls that shouldn't ship)
- [ ] Commit messages are clear and follow conventional commits format

#### 9. Agent Implications

If/when Garden adds an AI agent surface, its tools must stay in sync with UI-exposed mutations. For now, this section is a placeholder — revisit if an agent layer is introduced.

**Reviewer D should:**

1. **Read the PR diff** (`gh pr diff <PR_NUMBER>`) and all changed files
2. **Read these reference files** to understand the current data surface:
   - `src/lib/backlog.ts` — domain helpers + normalization
   - `src/lib/storage.ts` — persistence
   - `src/types.ts` — data models
3. **Check each category below**

##### 9a. Tool Coverage Gaps

- [ ] Does the PR add or change a mutation that users can trigger via the UI?
- [ ] If an agent exists, does a corresponding tool let the agent perform the same operation?
- [ ] If no tool exists, flag as **Critical** — the agent cannot do what the user can do
- [ ] If a tool exists but its parameters don't cover new options, flag as **Critical**

##### 9b. Tool Schema Drift

- [ ] Do any changed helpers or model properties affect existing tool handlers?
- [ ] If a function signature changed (renamed params, new required fields, removed options), does the corresponding tool's schema still match?
- [ ] If a tool's description references behavior that changed in this PR, flag as **Suggestion**

##### 9c. Data Model Sync

- [ ] If the PR modifies `GardenItem`, `GardenProject`, or `Backlog` types, do any agent tool schemas reflect the new shape?
- [ ] If new properties are added to models, can the agent set/read them through existing tools?

**Severity guidelines for Section 9:**
- **Critical** — Agent cannot perform an operation the user can (missing tool, broken schema). Fix it directly if possible.
- **Suggestion** — Agent can still function but descriptions or schemas are stale. Fix directly.
- **Nitpick** — Minor wording improvements to tool descriptions.

**Reviewer D output format:**
```
## Agent Implications Findings

### Critical — Agent Capability Gaps
- `file:line` — [What the user can do that the agent cannot]
  - **Fix applied:** [description] OR **Needs developer attention:** [why]

### Suggestions — Stale Agent Context
- `file:line` — [What's out of sync and the corrected version]

### Verified OK
- [List of agent surface areas checked that are still consistent]

### Summary
[One paragraph: Are there agent capability gaps introduced by this PR?]
```

### Agent Output Format (Include in Agent Prompts)

Tell each agent to return findings in this exact structure:

```
## Findings

### Critical
- `File.tsx:42` — [Description of the issue and suggested fix]

### Suggestions
- `File.tsx:15` — [Description and rationale]

### Nitpicks
- `File.tsx:88` — [Minor observation]

### File Size & Modularity Report
- `File.tsx` — [X lines] — [What could be extracted into its own module and why]

### Summary
[One paragraph: What is the PR doing? Overall quality assessment.]
```

## Step 4: Merge Findings & Fix Issues (Main Agent)

Once all review agents return:

1. **Merge findings** — combine all agent results into a single list
2. **Deduplicate** — if multiple agents flag the same issue, elevate its severity
3. **Fix all Critical issues** — read only the specific files/lines needed, make targeted fixes
4. **Fix reasonable Suggestions** — apply improvements that are clearly beneficial
5. **Fix agent gaps** — apply Reviewer D's findings: update tool schemas, agent service methods, etc.
6. **Re-review fixes** — launch a quick follow-up Task agent to verify your fixes didn't introduce new issues (give it only the files you modified and ask it to check for correctness)
7. **Iterate** — if the follow-up agent finds new issues, fix and re-verify until clean

**Use your judgment on fixes:**

- If fixing something requires touching code far outside the PR's diff, note it but skip it
- If a fix is risky (behavior might change), make the fix but flag it clearly in the report
- If you're unsure, err on the side of making the change — the author can revert

## Step 5: Stage, Commit & Push (Main Agent)

```bash
git add -u  # or specific files
git commit -m "$(cat <<'COMMITEOF'
fix: apply review feedback

<one-line summary of what was fixed>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
COMMITEOF
)"
git push
```

Commit and push the review fixes automatically. Use a conventional `fix:` commit with a concise summary of what changed.

## Step 6: Report (Main Agent)

```markdown
## PR Review: <branch> → <parent>

**Files changed**: <count>
**Insertions**: +<count> | **Deletions**: -<count>
**Review passes**: <number of iterations before clean>

### Summary

[One paragraph: What was the PR trying to do? What state did you find it in? What's the overall quality delta from your changes?]

### Critical Issues Fixed

- `File.tsx:42` — [Description of the issue and what you did]

### Suggestions Applied

- `File.tsx:15` — [Description and rationale]

### Nitpicks (For Your Awareness)

- `File.tsx:88` — [Minor observation, not fixed]

### File Size & Modularity (Flagged for Refactor)

- `File.tsx` — [X lines] — [What should be extracted into its own module.]

### Agent Implications

#### Gaps Fixed
- [Tool schemas updated, agent methods added, etc.]

#### Needs Developer Attention
- [Critical agent gaps that couldn't be auto-fixed]

_(If no agent implications found, state "No agent implications — changes don't affect AI agent capabilities.")_

### Not Fixed (Out of Scope or Too Risky)

- [Issues you noticed but intentionally left alone, with reasoning]

### Flagged for Author Review

- [Changes where you made a judgment call they should verify]

### Test These Areas

- [Specific user flows or edge cases that touch your changes]
```

If no issues are found in a category, omit that section entirely.

## Step 7: Post Review Comment on PR (Main Agent)

After printing the report, post it as a comment on the PR so it's visible on GitHub:

```bash
gh pr comment <PR_NUMBER> --body "$(cat <<'EOF'
<paste the full report from Step 6 here>
EOF
)"
```

Use the PR number determined in Step 1. If no PR exists (e.g., branch has no open PR), skip this step and inform the user that no PR comment was posted because no open PR was found.

## What "Good Enough" Looks Like

After your pass, the code should:

- Be readable without needing the PR description for context
- Handle failure cases explicitly
- Have no obvious duplication
- Use names that explain intent
- Be no more complex than necessary

If you only find trivial issues (unused imports, minor formatting), say so explicitly — but also consider whether you looked hard enough.
