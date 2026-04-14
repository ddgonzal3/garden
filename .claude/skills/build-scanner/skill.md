---
name: build-scanner
description: Use when creating a new autonomous scan agent skill for Garden. Generates a complete scan-* skill with the standard 8-step structure (orient, explore, prove, fix, verify-build, commit, journal, report), backlog tracking, journal template, focus modes, and domain-specific investigation guidance.
user_invocable: true
---

# Build Scanner

Meta-skill that creates new autonomous scan agent skills for the Garden codebase. Generates a complete `scan-<domain>` skill following a battle-tested structure.

## How to Run

```
/build-scanner <domain> [description]
```

Examples:
- `/build-scanner accessibility` — creates `scan-accessibility`
- `/build-scanner state-sync "Find state desync between BacklogStore and UI"`
- `/build-scanner swiftui-performance`

## Step 1: Gather Requirements

Before generating anything, answer these questions. Ask the user if anything is unclear.

### Required

1. **Domain name** — becomes `scan-<domain>` (e.g., `accessibility`, `state-sync`, `swiftui-performance`)
2. **One-sentence purpose** — what does this scanner hunt for? (e.g., "SwiftUI performance issues", "data model inconsistencies", "unused code")
3. **User perspective** — who gets hurt by these issues, and how? This becomes the scanner's "think like a ___" framing.
   - User: "the app is laggy", "my items disappeared", "the sidebar doesn't update"
   - Developer: "the build is slow", "this file is 800 lines", "tests are missing"

### Optional

4. **Focus modes** — sub-categories the user can pass to narrow exploration (e.g., `views`/`services`/`models`). If the domain is narrow enough, skip this.
5. **Key investigation areas** — specific files, directories, or patterns to check. If unknown, the scanner will explore freely.
6. **Proof strategy** — how does the scanner prove a finding? **TDD is mandatory for all scanners.** Every scanner must write a failing test before fixing. Choose the appropriate approach:
   - **Unit test** (XCTest) — for logic bugs, state issues, service behavior, data model correctness. Most common.
   - **UI test** (XCUITest) — for user-facing behavior requiring real UI interactions, navigation flows, accessibility. Uses `GardenUITests/`.
   Structural checks (grep, doc comparison) are acceptable as **supplementary** evidence but never as the sole proof. If the finding is real, there exists a test that can fail.
7. **Fix scope** — what kinds of fixes are in scope? (e.g., "Swift only", "Swift + project config", "docs only")

## Step 2: Generate the Skill

Create `.claude/skills/scan-<domain>/skill.md` using the template below. Fill in all `{{placeholders}}` from the gathered requirements.

````markdown
---
name: scan-{{domain}}
description: Use when you want to autonomously explore the Garden codebase for {{one_sentence_purpose}}. Tracks progress in a journal. Designed for periodic runs via /loop.
user_invocable: true
---

# Scan {{Domain Title}}

Autonomous {{domain}} auditor for the Garden codebase. Each run, you {{user_perspective_framing}} — explore the codebase, find one real issue, prove it with a failing test, and fix it.

## How to Run

- **Freeform:** `/scan-{{domain}}`
{{#if focus_modes}}
{{#each focus_modes}}
- **Focused:** `/scan-{{domain}} {{this}}`
{{/each}}
{{/if}}
- **Recurring:** `/loop 1h /scan-{{domain}}`

## Step 1: Orient

Read these to get your bearings and avoid retreading old ground:

1. `docs/scan-journals/{{domain}}-scan-journal.md` — past investigations
2. `CLAUDE.md` — architecture and conventions
3. `Garden/Services/BacklogStore.swift` — single source of truth for state
{{#each extra_orient_files}}
4. `{{this.path}}` — {{this.description}}
{{/each}}

Check the **Backlog** section of the journal. If there are unaddressed items, consider working on the highest-priority one instead of fresh exploration — unless recent git history (`git log --oneline -20`) reveals changes in a more promising area.

If the journal doesn't exist, create it:

```markdown
# {{Domain Title}} Scan Journal

{{journal_description}}

| Date | {{journal_columns}} |
|------|{{journal_separators}}|

## Backlog

Suspected issues found during exploration, not yet addressed. Check here before fresh exploration.

| Date Found | Area | Suspected Issue | Priority | Notes |
|------------|------|-----------------|----------|-------|
```

## Step 2: Explore

{{#if focus_modes}}
**If the user passed a focus mode, stay in that lane. Otherwise, roam free.**
{{/if}}

### How to think

**{{user_perspective_instruction}}** Don't scan for code quality issues in the abstract. Ask yourself:

{{#each think_like_questions}}
- "{{this}}"
{{/each}}

### What to look for

{{investigation_checklist}}

**Key files:**
{{#each key_files}}
- `{{this}}`
{{/each}}

### How to investigate

1. Pick an entry point — {{entry_point_examples}}
2. Trace the full path: {{trace_description}}
3. Ask adversarial "what if" questions at each step
4. When something looks suspicious, verify by checking callers and edge cases

**Spend no more than ~15 minutes investigating a dead end.** If the area looks clean, move on.

### Log All Findings

After exploration, log ALL suspected issues to the journal's **## Backlog** section — not just the one you'll fix this run. This prevents losing findings between runs:

```markdown
| 2026-04-01 | area-name | Suspected issue description | P1/P2/P3 | Context |
```

Priority: **P1** = user-facing, normal usage. **P2** = edge case. **P3** = theoretical.

Then pick the highest-priority item (from backlog or freshly found) to prove and fix.

## Step 3: Prove It (TDD — mandatory)

**Every finding must be proven with a failing test before any fix is attempted.** Choose the right test tier:

### Tier 1: Unit test (XCTest)
For logic bugs, state issues, service behavior, and data model correctness. Write a test that exercises the buggy path.

```bash
xcodebuild test -scheme Garden -destination 'platform=macOS' -only-testing "GardenTests/<TestClass>/<testMethod>" 2>&1 | tail -20
```

### Tier 2: UI test (XCUITest)
For user-facing behavior requiring real UI interactions — navigation flows, sidebar selection, inline editing, drag-and-drop.

```bash
xcodebuild test -scheme Garden -destination 'platform=macOS' -only-testing "GardenUITests/<TestClass>/<testMethod>" 2>&1 | tail -20
```

{{proof_strategy_section}}

Run the test and confirm it **fails**. If the test passes — your suspicion was wrong. Log it in the journal and explore something else.

## Step 4: Fix It

Minimal change that fixes the root cause.

1. Fix the bug
2. Run the test — confirm it passes
3. Run the full test suite to check for regressions:
   ```bash
   xcodebuild test -scheme Garden -destination 'platform=macOS' 2>&1 | tail -20
   ```

## Step 5: Verify Build

```bash
xcodebuild -scheme Garden -destination 'platform=macOS' build 2>&1 | tail -5
```

Do NOT proceed to the next step if the build is broken — fix or revert first.

## Step 6: Commit, PR, Review

1. Update the journal **before** committing (see Step 7 below for format)
2. Commit **all changes together** — code fix, test, AND journal update: `fix: <description> ({{domain}}-scan)`
3. Push: `git push origin HEAD`
4. Check for existing PR: `gh pr view --json state,url 2>/dev/null`
   - Open PR exists -> reuse it
   - No PR -> create one with `gh pr create`
5. Run `/review-pr` on the PR — if the review surfaces problems, fix them before reporting
6. **After review fixes:** if the review added commits, check for any unstaged changes (journal updates, doc tweaks) and commit+push them too. Never leave tracked changes uncommitted after review.
7. Print the PR link

## Step 7: Journal Format

The journal update in Step 6 should follow this format. Append a row to `docs/scan-journals/{{domain}}-scan-journal.md`:

```markdown
| 2026-04-01 | {{example_journal_entry}} |
```

For false positives or clean areas:

```markdown
| 2026-04-01 | {{example_false_positive_entry}} |
```

When you fix a backlog item, remove it from the Backlog table. Prune backlog items where the code has been refactored away or another scan already addressed the issue.

## Step 8: Report

```
## {{Domain Title}} Scan — [date]

{{report_template}}
```

## Principles

{{#each principles}}
- **{{this.name}}.** {{this.description}}
{{/each}}
````

## Step 3: Customize the Template

The template above uses handlebars-style placeholders for illustration. When generating the actual skill, replace every placeholder with concrete content. Follow these rules:

### User perspective framing

Every scanner opens with a persona-driven framing. Match the pattern:

| Scanner | Framing |
|---------|---------|
| scan-bugs | "think like a user trying to break Garden" |
| scan-performance | "think like a user whose app is laggy and unresponsive" |
| scan-state-sync | "think like a user who adds an item and expects it to appear everywhere" |
| scan-accessibility | "think like a user navigating with keyboard and VoiceOver" |
| scan-dead-code | "think like a developer maintaining a clean, lean codebase" |

The new scanner needs its own version of this. Always frame from the **affected user's perspective**, not the developer's.

### "Think like" questions

Write 4-6 questions the scanner should ask itself. These drive the exploration. Examples:

- "I just added a task — does it appear in All Items AND the category view?" (state-sync)
- "I'm navigating purely by keyboard — can I reach every action?" (accessibility)
- "I've been using Garden for hours — is it still responsive?" (performance)

### Journal columns

Match the domain. Common patterns:

| Scanner | Columns |
|---------|---------|
| Most scanners | `Mode \| Area \| Finding \| Verdict \| Fix Commit` |
| scan-test-gaps | `Service/Component \| Existing Coverage \| Tests Added \| Fix Commit \| Notes` |

Pick the simplest format that captures the scanner's findings.

### Proof strategy — TDD is mandatory

**Every scanner must write a failing test before fixing.** This is non-negotiable. If a finding is real, there exists a test that can fail. Choose the right tier:

#### Tier 1: Unit test (XCTest) — default for most scanners

```markdown
If you suspect an issue, **write a failing unit test before fixing anything.**

1. Create or update the test file for the affected code in `GardenTests/`
2. Write a test that demonstrates the issue
3. Run it and confirm it **fails**:
   \`\`\`bash
   xcodebuild test -scheme Garden -destination 'platform=macOS' -only-testing "GardenTests/<TestClass>/<testMethod>"
   \`\`\`
```

Best for: logic bugs, state issues, service behavior, data model correctness, BacklogStore mutations.

#### Tier 2: UI test (XCUITest) — for user-facing behavior

```markdown
If the issue involves real user interaction (sidebar navigation, inline editing, drag-and-drop), **write a failing UI test.**

1. Create or update a test in `GardenUITests/`
2. Use XCUIApplication and accessibility identifiers for element lookup
3. Run it and confirm it **fails**:
   \`\`\`bash
   xcodebuild test -scheme Garden -destination 'platform=macOS' -only-testing "GardenUITests/<TestClass>/<testMethod>"
   \`\`\`
```

Best for: navigation flows, sidebar selection, inline editing, context menus, keyboard shortcuts.

#### Choosing the right tier

| Finding type | Primary tier | Secondary tier |
|---|---|---|
| Logic bug in BacklogStore | Unit test | — |
| Missing data validation | Unit test | — |
| Sidebar navigation broken | UI test | — |
| Inline editing doesn't save | UI test | Unit test (store) |
| Dead code / unused property | Unit test (compilation) | — |
| JSON persistence issue | Unit test | — |
| Agent tool schema mismatch | Unit test | — |

Structural checks (grep, doc comparison) are acceptable as **supplementary investigation** but never as the sole proof.

### Principles

Every scanner needs 4-6 principles. Always include these three (adapted to the domain):

1. **User perspective first.** Frame the principle from the affected user's POV.
2. **TDD is non-negotiable.** A failing test (unit or UI) must exist before any fix. No exceptions. Structural checks are supplementary, never sufficient alone.
3. **Move on fast.** ~15 minutes max on a dead end.

Then add 2-3 domain-specific principles. Examples:

- "State is sacred." (state-sync) — Every mutation must flow through BacklogStore and persist correctly.
- "Calm over clever." (design) — Match Garden's minimal aesthetic; never add visual noise.
- "Separability over size." (modularity) — Extract the most separable piece, not the biggest.

## Step 4: Create the Journal

Create the journal file at `docs/scan-journals/<domain>-scan-journal.md` using the template defined in the skill's Step 1. Pre-populate the Backlog section if any issues are already known.

## Step 5: Verify

Run through the generated skill mentally as a checklist:

- [ ] Frontmatter has `name` and `description` (description starts with "Use when")
- [ ] "How to Run" section with freeform, focused (if modes exist), and `/loop` examples
- [ ] Step 1 reads journal, reads CLAUDE.md, checks backlog, has journal template with Backlog section
- [ ] Step 2 has persona-driven "how to think", investigation guidance, key files, 15-min dead-end limit, "Log All Findings" subsection
- [ ] Step 3 has concrete proof strategy with a **failing test** (unit or UI — structural checks alone are insufficient)
- [ ] Step 4 has fix + regression test instructions
- [ ] Step 5 has Verify Build (`xcodebuild -scheme Garden`), with "fix or revert" gate
- [ ] Step 6 has journal-before-commit, commit all together, push, PR reuse check, `/review-pr`, post-review unstaged check
- [ ] Step 7 has journal format (reference only — the action is in Step 6) with example entries + backlog maintenance
- [ ] Step 8 has structured report template
- [ ] Principles section with 4-6 items including user-perspective, prove-before-fix, move-on-fast
- [ ] No handlebars placeholders remain
- [ ] Commit tag matches: `fix: <desc> (<domain>-scan)` or `refactor:` / `test:` as appropriate

## Step 6: Register

Tell the user the skill is ready and how to invoke it:

```
New scanner created: /scan-<domain>

Run it: /scan-<domain>
Focus:  /scan-<domain> <mode>
Loop:   /loop 1h /scan-<domain>
```

## Principles

- **TDD is the law.** Every scanner proves findings with a failing test (unit or UI) before fixing. Structural checks supplement but never replace tests. No exceptions.
- **Consistency is the point.** Every scanner should feel like a sibling of the others. Same step numbers, same commit tags, same journal format, same backlog mechanism.
- **User perspective is non-negotiable.** If you can't articulate who gets hurt by the issues this scanner finds, the scanner has no focus.
- **Choose the right test tier.** Unit tests for logic/state. UI tests for user-facing behavior and real interactions. See the tier table in the Proof strategy section.
- **Backlog prevents amnesia.** Every scanner must log all findings, not just the one it fixes. The backlog is how scanners build knowledge across runs.
- **Don't over-scope.** A scanner should find and fix ONE issue per run. Depth over breadth. The `/loop` pattern handles coverage over time.
