<!-- describe-v1 -->

# Describe: Fresh-Eyes Bug Handoff Prompt

Generate a prompt that can be given to a fresh Claude context to debug the issue you've been stuck on. The goal is to describe the problem from the **user's point of view** without prescribing a technical solution — let the fresh context approach it with no assumptions.

## Rules

1. **User POV only.** Describe what the user sees, does, and expects. No implementation details about what's wrong in the code.
2. **No technical diagnosis.** Don't say "the state isn't updating" or "React memoized the view." The fresh context needs to form its own hypothesis.
3. **Include file path hints.** List the key files/components involved so the fresh context knows where to start reading. But don't say what's wrong in those files.
4. **Include reproduction steps.** Step-by-step what the user does to trigger the bug.
5. **Include what was already tried.** Briefly list approaches that were attempted and didn't fully resolve the issue, so the fresh context doesn't repeat them.
6. **End with a clear ask.** The output should be a single copy-pasteable prompt ready to give to a new Claude session.

## Output Format

```
## Bug: [one-line summary]

### What happens
[2-3 sentences describing the visual/behavioral problem from the user's perspective]

### Steps to reproduce
1. ...
2. ...
3. ...

### Expected behavior
[What should happen instead]

### Key files to investigate
- `src/App.tsx` — [brief role, e.g., "handles sidebar navigation"]
- `src/lib/backlog.ts` — [brief role]

### What was already tried (didn't fully fix it)
- [approach 1 — brief description of what was done and why it wasn't sufficient]
- [approach 2]

### Ask
[Clear instruction: "Find the root cause of X and fix it. Don't just suppress the symptom."]
```

## Process

1. Review the conversation to identify the unresolved problem
2. Strip out all technical hypotheses and implementation details
3. Write the prompt in the format above
4. Present it as a fenced code block the user can copy

$ARGUMENTS
