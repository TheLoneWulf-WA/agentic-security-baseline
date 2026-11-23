---
name: until-clean
description: Close the review on the current branch's PR — run the one full review (/code-review --comment), see that every finding ever raised is answered (fixed, filed as an issue, or closed with a reason), check the fixes with one targeted agent, then report a single CLEAN / NOT CLEAN verdict and write the marker. Use when the user asks "is it clean?", "reviewed until clean?", "/until-clean", or after applying review fixes.
---

# until-clean — one review, every finding answered, the fixes checked

The question this skill answers with one word: **has this PR had its
full review, is every finding answered, and were the fixes checked by
someone other than their author?**

Until 2026-11-23 this skill looped fresh full reviews until one came
back empty, then ran `/code-review` on top. Measured on about 30 PRs in
one project: the first review and the adversarial review found the real
problems; later passes found what the fixes broke, or wording; and the
second full review at the same commit found something about once in 30.
So the fresh passes are gone. What stays is the part that earned its
keep: **a fix is never trusted until another agent has looked at it.**

## Procedure

1. **Locate the work.**
   - Branch: `git branch --show-current`; head: `git rev-parse HEAD`.
   - PR: `gh pr view --json number,state,headRefOid,comments` (the PR for
     the current branch). No PR: open one first; the review posts to it.
   - Confirm the local head is pushed (`headRefOid` matches local HEAD);
     if not, push first. A verdict on unpushed state is stale.
   - Run `~/.claude/scripts/pr-risk.sh <PR>` and record its output
     (RISK, SIZE, LINES and REASON lines) in the report. `RISK=` picks
     the fix-check model in step 5. Never treat a PR as lower risk than
     the script says.

2. **Collect the findings so far.** From wherever they exist: the
   `/security-review` and `/adversarial-review` reports in
   `~/.claude/reports/<project-name>/`, earlier review comments on the
   PR, and findings mentioned in the session. This is the checklist.
   Note, for each, the commit it was raised at.

3. **The one full review.** If the PR has no "Code review" comment yet,
   invoke `/code-review --comment` (the command itself, never a comment
   written by hand) at the current head. It runs **once per PR**. A PR
   that already has one is not reviewed in full again: later commits are
   the fix check's job (step 5). Add its findings to the checklist.

4. **Answer every finding.** Each one ends in exactly one of:
   - **Fixed.** Important findings (and HIGH or MEDIUM from the earlier
     reviews): one commit per finding, building between each. Nits, LOW
     and wording findings: one batch commit for the lot.
   - **Filed.** A problem this PR did not introduce becomes an issue
     (`gh issue create`), not a fix here. Record the issue number.
   - **Closed with a reason.** A finding that is wrong, or deliberately
     not acted on, is closed with the reason written down: in the report,
     and as a reply on the PR where the finding was posted. Closing an
     Important, HIGH or MEDIUM finding this way is a judgment call: it
     goes in the judgment ledger, and the fix check is asked whether it
     agrees.
   - **Awaiting the user.** Findings that are the user's to decide
     (CLAUDE.md amendments, product or design calls, anything in an
     always-ask class) are surfaced with a recommendation, never
     auto-fixed. The verdict is NOT CLEAN until they are decided.

   Push. If the checklist is empty (the review found nothing and nothing
   was raised earlier), skip to step 7.

5. **The fix check.** One fresh-context agent, read-only. **Opus** when
   `RISK=sensitive` (any PR with code), **Sonnet** when `RISK=normal`.
   It is given:
   - the checklist, with how each finding was answered;
   - the diff from the commit the oldest unchecked finding was raised at
     to the current head (`git diff <sha>..HEAD`), and the paths to read
     around it. **Not the whole PR diff again**;
   - three jobs: (a) a verdict per finding: RESOLVED or NOT RESOLVED
     (resolved means actually fixed, not reworded; for a security
     finding the severity must be gone or downgraded), and AGREE or
     DISAGREE for each one closed with a reason; (b) what did these
     fix commits break or leave untested? Fixes are where the next bug
     is; (c) nothing else. It does not re-review code the fixes did not
     touch, and does not repeat a finding already on the checklist.
   - never the author's conclusions about the fixes.

   **A batch that changed only wording** (PR body, code comments, docs
   prose; no change to what the code does) needs no fix check of its
   own. If nothing else is unchecked, go to step 7.

6. **Branch on the fix check.**
   - **Everything resolved, nothing new** → continue to step 7.
   - **Something not resolved, or something new** → answer it (step 4),
     push, and run **one more** fix check, given only the new commits
     and the open items.
   - **Cap: two fix checks.** If anything Important, HIGH or MEDIUM is
     still open after the second, stop. Report NOT CLEAN and surface it
     to the user (or whoever coordinates the sessions) with the
     question that matters by then: is the approach wrong? A third
     round of the same fix rarely answers it. LOW or Nit items found by
     the second check are fixed in one batch and recorded; they do not
     earn a third check.

7. **Record the clean state** — only now, and only from inside this
   skill.
   - Write the marker read by the merge gate:
     `mkdir -p "$(git rev-parse --git-dir)/review-clean" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(git rev-parse --git-dir)/review-clean/$(git branch --show-current | tr '/' '_')"`
   - Write the report, the evidence that this ran:
     `~/.claude/reports/<project-name>/until-clean-<branch with / as _>-<YYYY-MM-DD>.md`.
     It records the branch, the PR, the `pr-risk.sh` output, the commit
     the full review ran at, each fix check and the commits it covered,
     every finding ever raised with how it was answered (commit, issue
     number or reason), and ends with the verdict line exactly as in
     step 8, naming the same SHA as the marker. A later run on the same
     branch and day appends a new dated section; it never overwrites an
     earlier one.
   - If there were findings, post a short follow-up comment on the PR:
     fixes checked at `<sha>`, each finding listed with its answer.

8. **Report the verdict** — always one of these shapes, so it is
   scannable across projects:

   ```
   Review loop: CLEAN (reviewed at <sha>, no findings)
   Review loop: CLEAN (reviewed at <sha>, fixes checked at <sha>)
   ```
   or
   ```
   Review loop: NOT CLEAN — <n> open finding(s):
   1. <finding> (<awaiting fix | awaiting user decision>)
   ```

## When main moves under the PR

Merge main in, then decide mechanically what the merge needs:

- `git diff --name-only <head before the merge>..HEAD` lists what the
  merge brought in. If **none** of those files is one the PR changes
  (`gh pr diff --name-only`), no review is needed: run this skill's
  step 7 to re-stamp the marker at the new head, and say in the report
  that the merge did not overlap.
- If they overlap only in docs, a decision log or a changelog (files
  `pr-risk.sh` would call safe), the same: re-stamp, and say so.
- Otherwise: **one fix check** (step 5) on the merge's changes to the
  overlapping files. Not a fresh full review, and no new adversarial
  round: nothing that was reviewed changed, only what it sits on.

## Light lane (docs-only or look-only PRs)

When the global CLAUDE.md's light-lane test applies (and only then),
the procedure is the same and simply costs less: `/code-review` runs
its two Sonnet agents, most findings are wording and need no fix
check, and a fix check that is needed runs on Sonnet. State in the
report which test made the PR light lane.

## Stop conditions

- The marker is written (step 7 reached).
- The user says "ship it" / "good enough": record the verdict as
  `OVERRIDDEN by user` instead of CLEAN; do not write the marker.
- A finding awaiting a user decision, or the fix-check cap: report NOT
  CLEAN and stop until the decision lands.

## Rules

- Never mark a finding resolved without the fix check verifying it on
  the pushed state. Self-assessment does not count. The one exception
  is a wording-only batch (step 5).
- The session that wrote a fix never checks it, and a reviewer that
  raised a finding is never asked to check its own fix.
- The marker is per-branch, local-only (lives under
  `<git-dir>/review-clean/`, worktree-accurate), and is invalidated by
  any new commit. The merge gate reports a stale marker as an explicit
  WARNING, distinct from a missing one.
- The marker, the report and the "Code review" comment are written only
  by this skill and `/code-review`. Never write a marker, a report or a
  code-review comment by hand, and never run a home-made set of review
  agents in place of this skill and call the result CLEAN. A
  hand-written marker has no report behind it whose verdict names the
  head, so a status check that looks for the report catches it (the
  merge gate itself reads only the marker). Found 2026-11-05: markers
  and comments written by hand on more than ten PRs.
- Any commit after the marker makes the verdict stale: run the skill
  again. It will not repeat the full review; it checks the new commits.
- CLAUDE.md findings follow the carve-out: they are amendments to
  discuss, never auto-fixes, and never block silently. Surface them.
