---
name: until-clean
description: Close the review on the current branch's PR — run the one full review (/code-review --comment), see that every finding ever raised is answered (fixed, filed as an issue, or closed with a reason), have a fresh agent check every commit made since, then report a single CLEAN / NOT CLEAN verdict and write the marker. Use when the user asks "is it clean?", "reviewed until clean?", "/until-clean", or after applying review fixes.
---

# until-clean — one review, every finding answered, the fixes checked

The question this skill answers with one word: **has this PR had its
full review, is every finding answered, and has every commit since been
read by someone other than its author?**

Until 2026-11-23 this skill looped fresh full reviews until one came
back empty, then ran `/code-review` on top. Measured on about 30 PRs in
one project: the first review and the adversarial review found the real
problems; later passes found what the fixes broke, or wording; and the
second full review at the same commit found something about once in 30.
So the fresh passes are gone. What stays is the part that earned its
keep: **a fix is never trusted until another agent has looked at it.**

## The covered commit

One idea holds the procedure together. The **covered commit** is the
newest commit that a reviewer has actually read: the "Reviewed at" SHA
of the PR's "Code review" comment, or the head a later check (step 5)
ran at, whichever is newer. It is recorded in this skill's report and
in its follow-up comment on the PR. **The marker is only ever written
when nothing but wording separates the covered commit from the head.**

## Procedure

1. **Locate the work.**
   - Branch: `git branch --show-current`; head: `git rev-parse HEAD`.
   - PR: `gh pr view --json number,state,isDraft,headRefOid,comments`
     (the PR for the current branch). No PR: open one first; the review
     posts to it. **A draft or closed PR stops here**: `/code-review`
     will not review it. Say so, and write nothing.
   - Confirm the local head is pushed (`headRefOid` matches local HEAD);
     if not, push first. A verdict on unpushed state is stale.
   - Run `~/.claude/scripts/pr-risk.sh <PR>` and record its output
     (RISK, SIZE, LINES and REASON lines) in the report. `RISK=` picks
     the model in step 5. Never treat a PR as lower risk than the
     script says.

2. **Collect the state.** From wherever it exists: this skill's earlier
   report for the branch and its follow-up comments on the PR, the
   `/security-review` and `/adversarial-review` reports in
   `~/.claude/reports/<project-name>/`, earlier review comments on the
   PR, and findings mentioned in the session. Build:
   - the **checklist**: every finding ever raised, the commit it was
     raised at, how it was answered, and whether a check has confirmed
     that answer;
   - the **covered commit** (none yet if the PR has no "Code review"
     comment);
   - the number of checks (step 5) already run since the last CLEAN
     marker, for the cap in step 6.

3. **The one full review.** If the PR has no "Code review" comment,
   invoke `/code-review --comment` (the command itself, never a comment
   written by hand) at the current head. Then confirm the comment
   exists and its "Reviewed at" SHA is the head. **If it does not, the
   review did not run: stop, NOT CLEAN, and say why.** Add its findings
   to the checklist; the covered commit is now the head.

   A PR that already has that comment is not reviewed in full again for
   fix commits: those go to the check in step 5. The exception is new
   work: if commits since the covered commit add something that answers
   no finding (a new feature, a wider change), run
   `/code-review --comment` again on the new head. Once per PR is the
   limit for fixes, not a way for new code to skip its review.

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
     goes in the judgment ledger, and the check is asked whether it
     agrees.
   - **Awaiting the user.** Findings that are the user's to decide
     (CLAUDE.md amendments, product or design calls, anything in an
     always-ask class) are surfaced with a recommendation, never
     auto-fixed. The verdict is NOT CLEAN until they are decided.

   Push.

5. **The check.** Run it whenever the head is not the covered commit,
   unless every commit in between changed **only wording** (PR body,
   code comments, docs prose; nothing that changes what the code does),
   or is a merge of the default branch that needs no check (see "When
   main moves"). Run it also, on an unchanged head, when a finding was
   closed with a reason and no check has yet agreed.

   One fresh-context agent, read-only. **Opus** when `RISK=sensitive`,
   **Sonnet** when `RISK=normal`. It is given:
   - `git diff <covered commit>..HEAD` and the paths to read around it.
     **Not the whole PR diff again.** A merge of the default branch
     inside that range is not read whole: see "When main moves";
   - the checklist items no check has confirmed yet, with how each was
     answered;
   - two jobs: (a) a verdict per item: RESOLVED or NOT RESOLVED
     (resolved means actually fixed, not reworded; for a security
     finding the severity must be gone or downgraded), and AGREE or
     DISAGREE for each one closed with a reason; (b) what is wrong in
     these commits: what did they break, and what did they leave
     untested? Fixes are where the next bug is. It reports each new
     problem as Important or Nit. It does not re-review code these
     commits did not touch, and does not repeat a finding already on the
     checklist;
   - never the author's conclusions about the fixes.

   Record the check and the head it ran at: that head is now the
   covered commit.

6. **Branch on the check.**
   - **Everything resolved, nothing new** → step 7.
   - **Something not resolved, or a new Important problem** → answer it
     (step 4), push, and run step 5 again on the new commits.
   - **Only new Nits** → fix them in one batch and run step 5 again if
     the batch changed code and the cap allows; otherwise leave them
     unfixed and file them in one issue. Never push a code fix that no
     check will read.
   - **Cap: two checks since the last CLEAN marker** (or since the full
     review, if there has been no marker), counted across runs of this
     skill; the report holds the count. If anything is still open after
     the second, stop. Report NOT CLEAN and surface it to the user (or
     whoever coordinates the sessions) with the question that matters by
     then: is the approach wrong? A third round of the same fix rarely
     answers it. Only the user's go-ahead resets the count.

7. **Record the outcome.** Always write the report; write the marker
   only on CLEAN.

   **CLEAN requires all of:** the PR has a "Code review" comment; no
   finding is open, unconfirmed or awaiting the user; and nothing but
   wording, or a merge that needed no check, separates the covered
   commit from the head. Anything else is NOT CLEAN: no marker.

   - The report, the evidence that this ran:
     `~/.claude/reports/<project-name>/until-clean-<branch with / as _>-<YYYY-MM-DD>.md`.
     It records the branch, the PR, the `pr-risk.sh` output, the commit
     the full review ran at, each check and the commits it covered, the
     covered commit, every finding ever raised with how it was answered
     (commit, issue number or reason), and ends with the verdict line
     exactly as in step 8. A later run on the same branch and day
     appends a new dated section; it never overwrites an earlier one.
   - On CLEAN, the marker read by the merge gate:
     `mkdir -p "$(git rev-parse --git-dir)/review-clean" && printf '%s %s\n' "$(git rev-parse HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$(git rev-parse --git-dir)/review-clean/$(git branch --show-current | tr '/' '_')"`
   - If there were findings or a check, post a short follow-up comment
     on the PR: the verdict line, the covered commit, and each finding
     with its answer.

8. **Report the verdict** — always one of these shapes, so it is
   scannable across projects. `<head>` is the commit the marker names.

   ```
   Review loop: CLEAN at <head> (reviewed at <sha>, no findings)
   Review loop: CLEAN at <head> (reviewed at <sha>, checked at <sha>)
   ```
   After the closing bracket, add what separates the last SHA from the
   head when they differ: `; wording only since` or
   `; main merged since, no check needed`. Otherwise:
   ```
   Review loop: NOT CLEAN — <n> open finding(s):
   1. <finding> (<awaiting fix | awaiting user decision>)
   Review loop: OVERRIDDEN by user at <head>
   ```

## When main moves under the PR

Merge the default branch in, push, and run this skill. In step 5, a
merge commit `<m>` of the default branch is handled by a file test, not
by reading everything it brought in:

- What the merge brought in: `git diff --name-only <m>^1 <m>`. What the
  PR changes: `gh pr diff --name-only`. The **overlap** is the files in
  both lists.
- **No overlap**, or overlap only in Markdown files (`.md`) other than
  `CLAUDE.md`, `AGENTS.md` and `SKILL.md`: the merge needs no check.
  Say so in the report, with the two lists' overlap.
- **Any other overlap:** the check in step 5 covers it. The agent is
  given `git diff <m>^1 <m> -- <the overlapping files>` and the PR's
  own diff of those files, and one more job: what did the merge break
  in the PR's code, or the PR in what came in? It is not a fresh full
  review, and there is no new adversarial round: nothing that was
  reviewed changed, only what it sits on. It counts toward the cap like
  any check.

## Light lane (docs-only or look-only PRs)

When the global CLAUDE.md's light-lane test applies (and only then),
the procedure is the same and usually costs less: most findings are
wording and need no check. The models are whatever `pr-risk.sh` says,
as for any PR: Sonnet when it says `RISK=normal`, which most docs-only
PRs do; Opus when a docs-only PR touches files the script treats as
sensitive (a `CLAUDE.md`, a `SKILL.md`, comments inside code files).
State in the report which test made the PR light lane.

## Stop conditions

- The outcome is recorded (step 7 reached), CLEAN or NOT CLEAN.
- The user says "ship it" / "good enough": record the verdict as
  `OVERRIDDEN by user` instead of CLEAN; write the report, not the
  marker.
- A draft or closed PR (step 1), or a full review that did not run
  (step 3).

## Rules

- Never mark a finding resolved without the check confirming it on the
  pushed state. Self-assessment does not count. The one exception is a
  wording-only change, which no check needs to read.
- No code reaches a CLEAN marker unread: every commit that changes what
  the code does is covered by the full review or by a check.
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
  again. Step 5 reads whatever was added since the covered commit.
- CLAUDE.md findings follow the carve-out: they are amendments to
  discuss, never auto-fixes, and never block silently. Surface them.
