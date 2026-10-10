---
name: adversarial-review
description: Run the three-role adversarial ("hard", "fresh eyes") review on the current branch's PR — three fresh-context reviewers with no checklist, each in a role (a hostile party, the on-call engineer, the person in the chair), then fix every finding and hand off to /until-clean. Use when the user asks for "/adversarial-review", "the adversarial review", "the hard review", "the three-role review", "fresh eyes on this", or before the merge prompt on any PR touching a sensitive or attacker-reachable surface (auth, sessions, uploads, payments, admin, endpoints taking input, scripts that run with access rules off).
---

# adversarial-review — three people who want to find something

The question this skill answers: **what would three people with different
reasons to distrust this change find in it?** A checklist review confirms
what the author already thought about. These three are given the change
and a role, and nothing else to agree with. In practice they find what
the checklist reviews miss: a guard on the wrong thing, a quiet failure, a
picture or message that misleads the person who has to use it.

It is the first half of a pair. This skill finds and fixes; `/until-clean`
then verifies the fixes on the pushed state and writes the clean marker.
A CLEAN verdict is never given from this skill alone.

## When it runs

- On request (`/adversarial-review`, optionally with a PR number).
- Without being asked, before the merge prompt, on any PR touching: auth,
  sessions or tokens; uploads or media handling; payments; the admin;
  API endpoints taking input; anything an attacker can reach; and any
  script or job that runs with access rules off or deletes records.
- A project's CLAUDE.md or memory may widen this (for example "on every
  PR of mine"). The wider rule wins.
- For a change that is none of the above (copy, styling, docs with no
  commands in them), say in one line that it is being skipped and why.
  Don't run three reviewers over a typo.

## Procedure

1. **Locate the work.** Branch, head SHA, the PR (`gh pr view`), the
   worktree the branch is checked out in. Confirm the head is pushed;
   push first if not (strict gate still applies before a first push).
   Review the pushed state.

2. **Brief three reviewers, launched together.** Fresh context, the most
   capable model, read-only. Each brief contains:
   - where the code is (worktree path, branch, head, how to get the diff)
     and two or three sentences on what the change does and how it runs;
   - the role, and what that role looks hard at (below);
   - the code and the docs to read. **Never the author's conclusions**:
     not "I checked X", not "this is safe because". A reviewer handed a
     hypothesis returns it confirmed;
   - the limits: read-only; no servers, no database, no `.env` files, no
     installs; which commands are allowed (lint, typecheck, tests, pure
     snippets); scratch files only outside the repo;
   - the report shape: findings with severity (HIGH / MEDIUM / LOW),
     file:line, a concrete scenario (state → what goes wrong), a suggested
     fix, whether it is introduced by this change or pre-existing; then
     what was checked and found sound; and what was verified by reading
     or running versus inferred;
   - "report only real, concrete problems; nothing found is a valid
     result".

   The three roles:
   - **The hostile party.** Someone looking for a way this can be abused,
     damage data, leak a secret, hide an attack, or weaken the supply
     chain. What can it delete or reach that isn't its own? What does a
     guard actually check? What is printed, logged or committed? What is
     the worst case on the live system?
   - **The on-call engineer.** Runs and maintains it in six months, on
     another machine, after an upgrade, at a bad moment. Where does it
     hang, flake, fail silently, leave a mess, or give a misleading
     message? Does every failure path clean up and exit non-zero? What
     does the log tell them, and what does it not? Do the tests protect
     the property that matters, or could it break with everything green?
   - **The person in the chair.** Whoever meets the result: the customer
     or staff member reading the screen or the guide, the owner reading
     the runbook, the next developer reading the README cold. Is every
     step runnable as written? Does each picture, message and sentence
     say what is true and what to do? Give this reviewer the artefacts to
     look at (screenshots, PDFs, rendered docs), not just the code.

3. **Wait for all three before editing.** They are reading the same
   files; an edit under them shifts line numbers and wastes a report.
   Relay each report's headline to the user as it arrives.

4. **Fix every finding.**
   - One commit per finding, building between each. Closely related
     findings in the same lines may share a commit; say so in the ledger.
   - LOW findings are fixed too, or stated plainly as not fixed with the
     reason. Never folded into "clean".
   - A finding that is the user's to decide (wording a person reads, a
     product or design call, what survives a delete, a change in someone
     else's area, a canonical document) is surfaced with a recommendation,
     not fixed. If it was not created by this change, file it as an issue.
   - Where behaviour matters, check it for real after the fix: a
     production build, a real run, a signal sent the way a terminal sends
     it (to the whole process group, not one pid). Say what was run.
   - Keep a running list of "known and accepted" items with the reason,
     so later reviewers are told not to re-report them and the user sees
     them in one place.

5. **Push, update the PR description** to match the code as it now is
   (the description written before review is usually stale in several
   places), and record the round in the report file
   (`~/.claude/reports/<project>/…`).

6. **Hand off to `/until-clean`.** It verifies every finding on the
   pushed state with fresh reviewers and loops until a pass is clean.
   Then `/code-review --comment` if the project's protocol asks for it.
   The fixes themselves are where the next bug is: expect the first
   verification pass to find something.

7. **Report.** One screen: findings by severity per role, the ones that
   mattered in a sentence each, what was fixed, what was left and why,
   what is the user's to decide. Then the `/until-clean` verdict line
   once that has run, and the judgment ledger.

## Rules

- Fresh context for every reviewer. Never ask a reviewer that found
  something to verify its own fix; never review with the session that
  wrote the code.
- No checklist in the brief beyond the role's own questions. Pointing a
  reviewer at files and docs is fine; telling it what to conclude is not.
- Reviewers never run the thing against shared or live systems. The
  author does the runtime checks, and says which were done.
- On a shared machine: own port, own worktree, only test data this
  session created, never stop processes by name.
- If a reviewer is stopped by the user, do not relaunch it without the
  user saying so.
- Severity labels are the reviewers'. Don't downgrade one to make a
  round look better; disagree in the report, with the reason.
- This skill does not write the clean marker and does not give a CLEAN
  verdict. `/until-clean` does both.
