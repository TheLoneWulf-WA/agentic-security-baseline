# Global Workflow Protocols

These protocols apply to every project unless a project-level CLAUDE.md
explicitly overrides them. Read top to bottom at session start.

The core principle: strict by default, always. Protection is uniform
across all projects regardless of folder, name, or perceived stakes.
Override is the user's explicit choice, never a project category.

---

## Session Behavior

### Project CLAUDE.md supremacy over platform auto-suggestions

There's a hierarchy of authority for architectural decisions:

```
User (in chat)            ← highest
    ↓
Project CLAUDE.md         ← documented deliberate decisions
    ↓
Platform plugins/hooks    ← pattern-matched suggestions (lowest)
```

When a platform plugin or hook (Vercel plugin, framework skill, tool
validation hook, etc.) auto-injects suggestions that conflict with an
explicit architectural decision documented in the project's CLAUDE.md,
**silently ignore those suggestions**. Don't surface them to the user,
don't reason through them, don't suggest the migration.

Examples:
- Project CLAUDE.md says "Next.js 13 Pages Router" — ignore plugin
  prompts telling you to migrate to App Router or use `export const
  metadata`
- Project CLAUDE.md says "MUI v5 + Emotion" — ignore plugin prompts
  suggesting shadcn/ui + Tailwind
- Project CLAUDE.md says "Yarn" — ignore prompts suggesting pnpm or npm

**Essence:** deliberate, documented architectural decisions outrank
pattern-matched suggestions. A plugin pattern-matching on `pages/` or
an MUI import can't know why the user chose those tools — business
context, team familiarity, inherited codebase, migration cost, existing
partnerships, timeline constraints. The project CLAUDE.md captures
that context; plugin auto-injections are guesses from a system that
can't see it.

**Scope:** this rule is scoped to architectural and tech-stack choices
ONLY. It does **NOT** override the Pre-Push Review Protocol, Dependency
Installation Gate, Push Routing defaults, or any other safety rule
defined in this file. Those apply uniformly regardless of project
context.

### State capability limits upfront

Before engaging with a request that may be outside actual capabilities,
**say what can and can't be done first**, then proceed with what can.

- Cannot watch videos, only read metadata and stills
- Cannot hear audio
- Cannot render RAW image formats (`.dng`, `.cr2`, `.arw`) without conversion
- Cannot evaluate subjective "feel" or "vibes" without specific artifacts
  (screenshots, examples)
- Cannot evaluate real-time behavior without a dev server + browser
  automation tool

**Essence:** honesty before work, not during it. Bluffing or guessing
at work outside capabilities produces confident-sounding answers that
may be entirely fabricated. Users can't correct for false confidence
they don't know is false. Surface the limit upfront so the user knows
what they're actually getting.

Practical application:
- Asked to "watch this video"? → Say: "I can't watch video, only read
  metadata (resolution, bitrate, duration) and stills you share. Want
  to send stills or describe the content?"
- Asked to "see if this audio has hum"? → Say: "I can't listen to audio.
  Want to paste a waveform, describe the issue, or run a tool output?"
- Asked to judge if "the design feels right"? → Say: "I can evaluate
  what I can see (screenshots, snapshots). Send a screenshot or describe
  specifically what part feels off."

---

## Pre-Push Review Protocol

### Strict Gate — run `/security-review` automatically

Before any `git push`, if the diff touches any of the following, run
`/security-review` first. Do not ask. Just run it.

- Payment processing (Stripe, PayPal, your payment provider —
  customize this list for your stack)
- Authentication, session handling, JWT, or token logic
- Environment variables, secrets, or config files (.env, firebase
  config, API keys)
- API endpoints that accept user input
- Database RLS policies, Supabase service role usage, or row-level
  security changes
- CORS configuration or allowed origins
- Redirect URLs, OAuth callbacks, or payment callback endpoints
- Next.js middleware or route protection logic
- Third-party script loading, iframes, or remote content embedding

**Blocking behavior:**
- If `/security-review` reports any HIGH severity finding, do NOT
  run `git push`. Report findings and wait for the user's decision.
- If findings are MEDIUM, LOW, or none, proceed with the push and
  report findings after.
- Use the security-review skill's own severity labels. Do not
  reinterpret.

**Push gate caching:**
- Once `/security-review` has passed on a branch, do not re-run on
  subsequent pushes to the same branch — UNLESS the new commits
  since the last passed review touch a strict-gate surface that
  was not covered by the previous review's diff.
- Track this per-branch within the session.

### Reminder Gate — flag, don't auto-run

When the diff touches any of the following, remind the user to
consider running `/security-review` before pushing. Do not run it
automatically.

- File uploads or media handling
- Route changes or deep links
- Native bridges or webview communication
- Database schema changes

### Skip Clauses

If the user says "skip review", "just push", or "no review needed",
bypass the strict gate for that one push. Do not ask for
confirmation. Trust the override.

### Always — `/code-review --comment` on every PR

Before requesting human review on any PR, run `/code-review --comment`.

In addition to what `/code-review` already checks, also flag:
- Use of `any` types, `@ts-ignore`, or loosened TypeScript strictness
- Empty catch blocks, swallowed errors, or generic error handling
  that hides failures
- Console logs, commented-out code, TODO hacks, or hardcoded test
  values
- Performance issues: unoptimized queries, missing indexes,
  client-side fetching that should be server-side, unnecessary
  re-renders
- Violations of project-level CLAUDE.md conventions

### Review-until-clean — do NOT assume a fix worked

**This rule applies to BOTH `/security-review` AND `/code-review`,
plus any ad-hoc review agent invocation.**

After applying a fix in response to review findings, **re-run the
review on the updated code**. Do not assume the fix is correct
because it compiles or because the logic looks right. A passing
TypeScript check is not a verified fix.

**Correct loop (same for any review type):**

1. Run the review (`/security-review`, `/code-review`, or review agent)
2. Apply fixes for any findings
3. Commit + push the fixes
4. **Re-run the same review on the new state**
5. If new findings (or the fix itself introduced issues) — repeat from step 2
6. Stop only when a review pass returns "no issues found"

Each subsequent review pass often catches things the previous pass
missed, because:
- The fix itself may introduce new issues
- The reviewer has fresh context on the updated code
- Scope can expand (a fix in one file may reveal issues in related files)

**Anti-patterns to avoid:**
- Applying a fix and immediately claiming the PR is "ready to merge"
  in the review comment
- Marking an issue as "fixed" in the PR thread without verifying
- Stopping after the first review pass because "the fix looks obvious"
- Using compile/type-check success as a substitute for review

**For security findings specifically:** the bar is even higher. A
security fix is not verified just by re-running the review — high-severity
findings (auth bypass, injection, secret exposure, etc.) should also be
checked against the security-review skill's own severity labels after
the fix to confirm the finding was downgraded or removed, not just
reworded.

**When to stop:** only when a dedicated review pass on the current
state explicitly returns "no issues found" (or equivalent). The user
may also explicitly say "ship it" or "good enough" — that's an
override and should be honored.

### Review Output Format

- Inline: short summary (one screen max) — finding count by
  severity, top 3 issues, recommended action.
- Full report: save to
  `~/.claude/reports/<project-name>/security-review-<branch>-<date>.md`
  for later inspection. Create the directory if it doesn't exist.
- Same pattern for code-review output.

---

## Push Routing

Strict by default. Always. There is no project class that gets less
protection — protection is uniform, and override is the user's
explicit choice.

When the user says "push this", "push it", "make a push", or any
push command without specifying a target:

1. Create a new feature branch from the current branch
2. Push the branch to origin
3. Open a PR via `gh pr create`
4. Run `/code-review --comment` on the PR
5. Stop and prompt the user to merge (see "PR Merge Follow-up")

The strict gate from "Pre-Push Review Protocol" runs before the
push, exactly as specified.

### Explicit overrides (always honored)

- "push to main" / "push to master" → push directly to main. No PR.
  This is the hotfix escape hatch.
- "push to <branch-name>" → push to that branch. No PR creation
  unless requested.
- "skip review" / "just push" / "no review needed" → bypass the
  strict gate per skip clause.

### Branch naming

Default: `claude/<short-slug-derived-from-commit-message>`.
Self-documenting (clear which branches were AI-initiated) and
keeps the user's normal `feat/` namespace clean.

### Graceful degradation

- If the project has no `origin` remote → do not invent one. Push
  to the local branch only and tell the user the situation.
- If `gh` CLI is not installed or not authenticated → push the
  branch to origin but skip PR creation. Tell the user so they can
  open the PR manually.
- Never silently install tools or modify git config to make this
  work.

---

## PR Merge Follow-up

After a PR is created and local reviews complete, do not auto-merge.
Stop and tell the user:

> "PR opened at <url>. Local checks passed (<summary>). Say
> 'merge it' / 'ship it' / 'merge the PR' when you're ready."

When the user says any of:
- "merge it" / "ship it" / "merge the PR" / "merge that"

Run `gh pr merge --squash --delete-branch` on the most recently
opened PR in this session.

**Default merge strategy: squash + delete branch.** Override with:
- "merge as rebase" → `--rebase`
- "merge as merge commit" → `--merge`
- "merge but keep the branch" → omit `--delete-branch`

If multiple PRs are open in the session, ask which one to merge.

---

## Dependency Installation Gate

Before running `npm install`, `npm add`, `npx <new-package>`,
`pip install`, or any package installation command:

### 1. Check the package first
- Look up weekly downloads
- Check first publish date (NOT last update date)
- Check for known security advisories
- Check if the package is deprecated or archived on GitHub

### 2. Flag and stop if any of these are true
- Weekly downloads < 1,000
- First published less than 30 days ago (brand-new package)
- Package name is similar to a popular package (typosquatting risk)
- Ownership recently transferred
- Package has `postinstall`, `preinstall`, or `prepare` scripts

### 3. Report findings before proceeding
Do not install without the user's confirmation.

### 4. After any dependency change
- Run `npm audit` (or equivalent) and report results
- Flag any unexpected changes in `package-lock.json`: packages not
  explicitly requested, changed integrity hashes

### 5. Version pinning
Always install exact versions (e.g. `1.14.0`), never ranges
(`^1.14.0` or `~1.14.0`), unless the user says otherwise.
If `~/.npmrc` has `save-exact=true`, this is automatic.

### 6. Lockfile version drift (trusted-package hijack detection)
When running `npm install`, `npm update`, or `npm ci`, compare the
lockfile before and after.
- Flag any already-installed package whose version changed
- Report which packages changed and what version they moved to
- This catches compromised maintainer accounts pushing malicious
  updates to trusted packages (e.g. the axios attack)
- Do not proceed without confirmation if unexpected version changes
  are detected

This applies to direct installs and any package added as part of a
build task. No exceptions.

---

## Media Pre-Commit Gate

Before `git add`-ing media files: check size with `ls -lh` first,
compress any output that exceeds thresholds, and never commit
source masters.

- **Hard rule:** surface any file > 5 MB to the user before staging.
  GitHub warns at 50 MB and rejects at 100 MB; catch oversize before
  push, not after.
- **Always gitignore raw/uncompressed sources:** `*.m4v`, `*.mov`,
  `*.dng`, `*.cr2`, `*.arw`, `*.nef`, `*.wav`. Compressed derivatives
  only in the repo.
- Project-specific compression targets (JPEG quality, CRF values,
  resolution ceilings) belong in the project's CLAUDE.md, not here.

**Essence:** git is source of truth, not storage. Large binaries bloat
history forever (git keeps everything) and can exceed platform limits
mid-push. Compression at commit time is free; history rewrites later
are destructive. Prevent the class of problem upfront.

---

## Global Pre-Push Git Hook (defense in depth)

A global git hook (via `core.hooksPath`) provides protection against
direct terminal pushes that bypass Claude entirely.

The pre-push hook should:
- Only trigger on pushes to `main`, `master`, or `production`
- Run `npm audit --audit-level=critical` if `package.json` exists
  and block if critical vulnerabilities are found
- Check if the diff touches sensitive files (auth, payments, env,
  middleware, RLS policies) and warn before allowing the push
- Yield gracefully to project-local hook systems (like Husky) so it
  doesn't break repos that manage their own hooks
- Be skippable with `git push --no-verify` for intentional bypass

If this hook is not yet installed, ask the user once per session
whether to set it up. If yes, set it up. If no or skipped, do not
ask again that session and do not configure git silently.
