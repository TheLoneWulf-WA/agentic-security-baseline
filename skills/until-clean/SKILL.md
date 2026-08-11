---
name: until-clean
description: Run the review-until-clean loop on the current branch's PR — re-review the CURRENT state, verify every prior finding is resolved (not reworded), fix-and-loop until a pass returns no findings, then report a single CLEAN / NOT CLEAN verdict. Use when the user asks "is it clean?", "reviewed until clean?", "/until-clean", or after applying review fixes.
---

# until-clean — close the review loop, mechanically

The question this skill answers with one word: **is the current branch
state verified clean by a re-review that ran AFTER the last fix?**
"Findings were fixed" is not the same as "a re-run came back clean" —
this skill exists because fixes themselves can introduce or reveal new
findings (this has happened in practice).

## Procedure

1. **Locate the work.**
   - Branch: `git branch --show-current`; head: `git rev-parse HEAD`.
   - PR: `gh pr view --json number,state,headRefOid,comments` (the PR for
     the current branch). If no PR exists, the loop runs on the pending
     diff vs the default branch instead.
   - Confirm the local head is pushed (`headRefOid` matches local HEAD);
     if not, push first — reviewing unpushed state produces a stale verdict.

2. **Collect prior findings.** From, wherever they exist:
   - earlier review comments on the PR (summary + inline),
   - the report file in `~/.claude/reports/<project-name>/`,
   - findings mentioned in the session so far.
   Build the checklist of every finding ever raised on this branch.

3. **Re-review the CURRENT state.** Launch review agents per the
   project's convention (project CLAUDE.md may specify a count; default
   2: one compliance/CLAUDE.md agent (sonnet), one bug agent (opus)).
   Each agent gets: the full current diff, the prior-findings checklist,
   and two jobs — (a) verdict per prior finding: RESOLVED / NOT RESOLVED
   (resolved means actually fixed, not reworded; for security findings the
   severity must be downgraded/removed), and (b) a fresh high-signal scan
   of the current diff including the fix commits.

4. **Branch on the outcome.**
   - **New or unresolved findings** → apply fixes (one commit per finding,
     per PR-decomposition rules), push, **GOTO 3**. Findings that are the
     user's to decide (CLAUDE.md amendments, product/design calls,
     anything in an always-ask class) are surfaced, not auto-fixed — they
     make the verdict NOT CLEAN (awaiting user) until decided.
   - **All resolved, nothing new** → the pass is clean. Continue.

5. **Record the clean pass.**
   - Write the marker consumed by the merge-gate backstop:
     `mkdir -p "$(git rev-parse --git-dir)/review-clean" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(git rev-parse --git-dir)/review-clean/$(git branch --show-current | tr '/' '_')"`
   - If the PR had review comments, post a short follow-up comment:
     re-review clean at `<sha>`, listing each prior finding as resolved.

6. **Report the verdict** — always this exact shape, so it's scannable
   across projects:

   ```
   Review loop: CLEAN (re-run after fixes at <sha>)
   ```
   or
   ```
   Review loop: NOT CLEAN — <n> open finding(s):
   1. <finding> (<awaiting fix | awaiting user decision>)
   ```

## Stop conditions

- A clean pass (step 5 reached).
- The user says "ship it" / "good enough" — record verdict as
  `OVERRIDDEN by user` instead of CLEAN; do not write the marker.
- A finding awaiting a user decision — report NOT CLEAN and stop looping
  until the decision lands.

## Rules

- Never mark a finding resolved without an agent verifying it on the
  pushed state. Self-assessment does not count.
- The marker is per-branch, local-only (lives under `.git/`), and is
  invalidated by any new commit — a stale marker is treated as absent.
- CLAUDE.md findings follow the carve-out: they are amendments to
  discuss, never auto-fixes, and never block silently — surface them.
