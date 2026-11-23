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
   A finding already filed as an issue (a Pre-existing problem, or a
   LOW filed at the pass cap) stays on the list with its issue number
   and is marked **filed**: reviewers are told not to judge it again,
   and it never counts as unresolved or makes a pass unclean.

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
   of the current diff including the fix commits. Each new finding is
   tagged HIGH, MEDIUM or LOW, and marked **Pre-existing** when it is
   equally true on the default branch and this PR does not make it
   worse. Only a reviewer applies that tag; the session running the
   loop never does, and never re-tags a finding. The compliance agent also
   applies the "Always flag at review" list in the global CLAUDE.md,
   and the bug agent reads test changes before source.

4. **Branch on the outcome.**
   - **New or unresolved findings** → apply fixes, push, **GOTO 3**. One
     commit per MEDIUM or HIGH finding; LOW findings, wording in files
     included, share one batch commit. Findings that are the user's to decide (CLAUDE.md
     amendments, product/design calls, anything in an always-ask class)
     are surfaced, not auto-fixed — they make the verdict NOT CLEAN
     (awaiting user) until decided.
   - **Pre-existing findings** (tagged so by a reviewer in step 3,
     never by the session running the loop) → file an issue (`gh issue create`) and record its
     number. They are not fixed in this PR and do not make a pass
     unclean.
   - **All resolved, nothing new** → the pass is clean. Continue.
   - **Only findings about the PR's title or description** → edit
     them (`gh pr edit`) and go straight to step 5. That is not a
     commit: the reviewed code is unchanged. Record each as "PR text
     edited, not re-reviewed". On a public repo the new text still goes
     through the sanitization scan the global CLAUDE.md requires for PR
     bodies.

   **Every commit is read by a pass.** There is no kind of fix small
   enough to skip one: a wording fix in a README, a comment or a skill
   is a fix like any other (**GOTO 3**). Until 2026-11-23 wording
   batches skipped the next pass and the final code review read them;
   with that review gone, nothing else would.

   **Pass cap** (2026-11-10, to cut usage): at most **3** loop
   passes. In pass 3 (or 4), a LOW finding is **not fixed**, whether it
   is in code or in wording in a file: file the LOW findings in one
   issue, record its number, and treat the pass as clean of them. A fix
   pushed after the last pass would be a commit no reviewer reads. Only
   a **MEDIUM or HIGH** finding earns a 4th pass. If a MEDIUM or HIGH
   is still open after pass 4, stop: report NOT CLEAN with the open
   findings and surface them to the user (or whoever coordinates the
   sessions) instead of looping on. Record the pass count and any cap
   decision in the report.

   **No second review on top** (2026-11-23, to cut usage). Until then a
   clean pass was followed by `/code-review --comment` at the same
   commit, four more agents re-reading a diff two had just passed.
   Measured on about 30 PRs in one project, it found something real
   about once. The clean pass is now the last review. `/code-review`
   is still there to run by hand; it is not part of this procedure.

5. **Record the clean pass** — only now, and only from inside this skill.
   - Write the marker consumed by the merge-gate backstop:
     `mkdir -p "$(git rev-parse --git-dir)/review-clean" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(git rev-parse --git-dir)/review-clean/$(git branch --show-current | tr '/' '_')"`
   - Write the report, the evidence that this loop ran:
     `~/.claude/reports/<project-name>/until-clean-<branch with / as _>-<YYYY-MM-DD>.md`.
     It records the branch, the PR, every pass run (with its head SHA),
     every finding ever raised and its outcome (fix commit, issue
     number, or "PR text edited"), and ends with the verdict line exactly as in step 6,
     naming the same SHA as the marker. A later run on the same branch and day appends a
     new dated section; it never overwrites an earlier one.
   - When there is a PR, post a comment on it headed `## Review loop`:
     the verdict line, the passes run, and each finding with its
     outcome. It is the PR's visible record of the review, on every PR,
     findings or not.

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

## Light lane (docs-only or look-only PRs)

When the global CLAUDE.md's light-lane test applies (and only then):
run step 3 once. If it finds nothing, or only something about the PR's
title or description, record (step 5) with "light lane" stated in the
report. If a fix was committed, one more pass is the re-check; if that
pass finds something, the normal loop and its cap apply. State in the report which test made the PR light lane.

## Stop conditions

- A clean pass (step 5 reached).
- The user says "ship it" / "good enough" — record verdict as
  `OVERRIDDEN by user` instead of CLEAN; do not write the marker.
- A finding awaiting a user decision — report NOT CLEAN and stop looping
  until the decision lands.

## Rules

- Never mark a finding resolved without an agent verifying it on the
  pushed state. Self-assessment does not count. The one exception is an
  edit to the PR's title or description (step 4): it changes no file,
  and is recorded as edited, not as verified.
- The marker is per-branch, local-only (lives under `<git-dir>/review-clean/`,
  worktree-accurate), and is invalidated by any new commit — the merge
  gate reports a stale marker as an explicit WARNING, distinct from a
  missing one.
- The marker, the report and the "Review loop" comment are written only
  by this skill. Never write any of them by hand, and never run a home-made set of review
  agents in place of this skill and call the result CLEAN. A
  hand-written marker has no report behind it whose verdict names the
  head, so a status check that looks for the report catches it (the
  merge gate itself reads only the marker). Found 2026-11-05: markers
  and comments written by hand on more than ten PRs.
- Any commit after the clean pass, other than bringing main in, makes
  the verdict stale: run the skill again.
- CLAUDE.md findings follow the carve-out: they are amendments to
  discuss, never auto-fixes, and never block silently — surface them.
