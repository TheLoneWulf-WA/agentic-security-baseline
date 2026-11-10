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
   2: one compliance/CLAUDE.md agent and one bug agent). **Models by
   risk** (2026-11-10, to cut usage; replaces the earlier rule of the
   most capable model for every reviewer). Decided **mechanically, never
   by judgment**: run `~/.claude/scripts/pr-risk.sh <PR>` and use its
   `RISK=` line. It returns normal only when every changed file is docs,
   images or styles by file type and no added line has a risky word;
   anything else, or any error, is sensitive. Never treat a PR as lower
   risk than it says.
   - **RISK=sensitive (any PR with code):** bug agent **always on opus**,
     compliance agent on **sonnet**.
   - **RISK=normal (docs, images or styles only):** both on **sonnet**.
   - Record the script's output (RISK, SIZE, LINES and REASON lines) in the report.
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
   - **Only wording findings** (PR body, code comments, docs prose; no
     change to what the code does) → fix them in one batch, push, and go
     straight to step 5. They never trigger another loop pass by
     themselves; the step-5 code review at the new head is their check.

   **Pass cap** (2026-11-10, to cut usage): at most **3** loop
   passes. In pass 3, LOW code findings are fixed and go straight to
   step 5, not a 4th pass. Only a **MEDIUM or HIGH** code finding earns a
   4th pass. If a MEDIUM or HIGH is still open after pass 4, stop: report
   NOT CLEAN with the open findings and surface them to the user (or whoever
   coordinates the sessions) instead of looping on. Record the pass count and any cap
   decision in the report.

5. **Final gate: the code review, at this exact head.** A clean loop pass
   is not yet a clean PR: the diff-only code review must describe the
   same commit. Without changing the head since the clean pass:
   - Invoke `/code-review --comment` (the skill itself, never a comment
     written by hand) on the current head.
   - **It finds anything** → it is a finding like any other: fix (one
     commit per finding), push, **GOTO 3**. A loop pass and then the code
     review run again on the new head.
   - **It's clean** → continue. The PR's "Code review" comment and the
     loop's clean pass now name the same SHA.

6. **Record the clean pass** — only now, and only from inside this skill.
   - Write the marker consumed by the merge-gate backstop:
     `mkdir -p "$(git rev-parse --git-dir)/review-clean" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(git rev-parse --git-dir)/review-clean/$(git branch --show-current | tr '/' '_')"`
   - Write the report, the evidence that this loop ran:
     `~/.claude/reports/<project-name>/until-clean-<branch with / as _>-<YYYY-MM-DD>.md`.
     It records the branch, the PR, every pass run (with its head SHA),
     every finding ever raised and its outcome, the code review's result,
     and ends with the verdict line exactly as in step 7, naming the same
     SHA as the marker. A later run on the same branch and day appends a
     new dated section; it never overwrites an earlier one.
   - If the PR had review comments, post a short follow-up comment:
     re-review clean at `<sha>`, listing each prior finding as resolved.

7. **Report the verdict** — always this exact shape, so it's scannable
   across projects:

   ```
   Review loop: CLEAN (re-run after fixes at <sha>)
   ```
   or
   ```
   Review loop: NOT CLEAN — <n> open finding(s):
   1. <finding> (<awaiting fix | awaiting user decision>)
   ```

## Light lane (docs-only or look-only PRs)

When the global CLAUDE.md's light-lane test applies (and only then):
run step 3 once; fix any findings (one commit each); then go straight
to step 5's code review at the final commit. If the code review is
clean, record (step 6) with "light lane" stated in the report. If it
finds anything, fix and run step 5 again, not a new loop round. State
in the report which test made the PR light lane.

## Stop conditions

- A clean pass and a clean code review at the same head (step 6 reached).
- The user says "ship it" / "good enough" — record verdict as
  `OVERRIDDEN by user` instead of CLEAN; do not write the marker.
- A finding awaiting a user decision — report NOT CLEAN and stop looping
  until the decision lands.

## Rules

- Never mark a finding resolved without an agent verifying it on the
  pushed state. Self-assessment does not count.
- The marker is per-branch, local-only (lives under `<git-dir>/review-clean/`,
  worktree-accurate), and is invalidated by any new commit — the merge
  gate reports a stale marker as an explicit WARNING, distinct from a
  missing one.
- The marker, the report and the "Code review" comment are written only
  by this skill and `/code-review`. Never write a marker, a report or a
  code-review comment by hand, and never run a home-made set of review
  agents in place of this skill and call the result CLEAN. A
  hand-written marker has no report behind it whose verdict names the
  head, so a status check that looks for the report catches it (the
  merge gate itself reads only the marker). Found 2026-11-05: markers
  and comments written by hand on more than ten PRs.
- Any commit after the clean pass, other than bringing main in, makes
  the verdict stale: run the skill again.
- CLAUDE.md findings follow the carve-out: they are amendments to
  discuss, never auto-fixes, and never block silently — surface them.
