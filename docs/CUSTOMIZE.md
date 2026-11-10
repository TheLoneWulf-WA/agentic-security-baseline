# Customize for your stack

The baseline ships with sensible defaults, but a handful of places need adapting before the system reflects *your* threat model. Here's what to change and where.

## 1. The strict gate list (`~/.claude/CLAUDE.md`)

Find the **Strict Gate** section. The list of sensitive surfaces ships with generic examples (Stripe, PayPal). Replace these with the specific systems *your* projects use:

- **Your payment processor(s)** — Stripe, Adyen, Paystack, Flutterwave, your local provider
- **Your auth system** — Auth0, Clerk, NextAuth, Supabase Auth, custom
- **Your database** — Supabase, PlanetScale, Postgres, Firebase
- **Any third-party integration critical to your stack** — Twilio, SendGrid, Plaid, etc.

The strict gate fires `/security-review` automatically when these surfaces are touched. Adding the right names here is the difference between catching things and missing them. If you ship payment code with a processor not in this list, the gate won't fire.

## 2. The sensitive-file pattern (`~/.config/git/hooks/pre-push`)

Find the `sensitive_pattern` regex. The default:

```
sensitive_pattern='\.env|auth|middleware|payment|stripe|jwt|secret|credential|rls|service[_-]role|cors|callback|oauth'
```

Add your stack-specific keywords. If you use `clerk` for auth, add it. If your payment processor is `paystack` or `flutterwave`, add it. If your codebase has filenames that contain `webhook`, `signing`, or `kms`, consider adding those.

The regex is case-insensitive (it's used with `grep -iE`).

## 3. The branch naming convention (`~/.claude/CLAUDE.md`)

Push Routing creates feature branches with the prefix `claude/<short-slug>`. If you prefer `feat/<slug>` or your team's own convention, edit the **Branch naming** section. Change the prefix in two more places too, or your pushes will prompt every time: the `claude/` allow entries in `~/.claude/settings.json`, and `safe_re` in `~/.claude/hooks/push-routing-gate.sh`.

## 4. The protected branches list (`~/.claude/hooks/push-routing-gate.sh`)

The PreToolUse hook treats `main`, `master`, and `production` as protected. Pushes to them always ask, because the hook only lets the plain `git push [-u] origin claude/<name>` shape through. Naming them in the script changes the prompt's wording to the protected-branch warning: add them to the `(main|master|production)` pattern in the push gate.

## 5. Skip clauses (`~/.claude/CLAUDE.md`)

If the default skip phrases ("skip review", "just push", "no review needed") don't match how *you* talk, change them in the **Skip Clauses** section to match your actual phrasing. The phrases need to be unambiguous so Claude Code recognizes the override.

## 6. Reports directory (`~/.claude/CLAUDE.md`)

Reports save to `~/.claude/reports/<project-name>/...` by default. Change the path in the **Review Output Format** section if you want them somewhere else (e.g. inside each project, or under your Documents folder).

## 7. The merge default (`~/.claude/CLAUDE.md`)

The default merge strategy is `squash + delete branch`. If your team prefers rebase or merge commits, change it in the **PR Merge Follow-up** section.

## 8. Review risk lists (`~/.claude/risk-paths/` and each project's `.claude/`)

`~/.claude/scripts/pr-risk.sh` decides whether a PR gets the sensitive-level review (an Opus bug reviewer in `/until-clean`, the full four agents in `/code-review`). It works as a **safe list**: a PR is normal only when every changed file (and the old name of a renamed one) is on a safe list, and no sensitive signal fires. Everything else is sensitive. All lists are extended regex (Python `re`), one pattern per line, `#` for comments.

The safe list:

- `_default-safe.txt` — what is safe in any project: docs, Markdown and text files, licence and changelog files, images, video and audio, fonts, stylesheets, editor config. Matched case-insensitively.

The sensitive signals, any one of which makes a PR sensitive even if all its files are on a safe list:

- `_default-paths.txt` — file paths, matched case-insensitively: secrets, CI, deploy, dependency files, migrations, API and server code, Android / iOS / Expo security files, anything under `.claude/`, and a root `CLAUDE.md` or `AGENTS.md`.
- `_default-names.txt` — folder and file names such as `auth`, `payment`, `upload`, matched on code files only (docs are skipped).
- `_default-content.txt` — words in the PR's *added* lines, matched case-sensitively: billing and in-app-purchase APIs, payment providers by name, keychain and crypto calls, webview bridges, exported Android components, cleartext settings, service-role keys, deletes, third-party scripts, iframes and forms that post elsewhere. The backstop for mobile code, where a risky call often sits in an ordinary-looking file.

Add your payment provider and auth library to `_default-content.txt` if they're not there. Keep project-specific paths out of the shared lists: `install.sh` replaces the shared lists on a re-run when they differ from the repo's copy (it backs yours up first). A shared list that is missing, empty, or has a pattern that doesn't compile makes every PR sensitive, so a typo can't quietly switch a check off.

Each project gets its own lists in `<repo>/.claude/`:

- `safe-paths.txt` — the project's folders whose changes can't touch money, sign-in, access, customer data, uploads, deletes, jobs, webhooks, config or third-party scripts. **Until it exists, only PRs of docs, images, fonts and styles get the cheaper review.** To write it, run `~/.claude/scripts/pr-risk.sh --suggest` inside the project. It prints a draft of the folders where no file trips a risky check. Review every line, and when unsure, delete it: an unlisted folder is just reviewed in full. Then save the file and open it in its own small PR.
- `risk-paths.txt` (optional) — extra risky paths only this project knows about. They override the safe lists.

Both are read from the PR's **base** branch, so a PR can't loosen the lists it is judged by, and any change under `.claude/` is sensitive anyway. (Files at `~/.claude/risk-paths/<repo-name>.safe.txt` and `<repo-name>.txt` are used when the base branch has none, for a repo where you'd rather not commit them.)

The 150-line threshold that makes a PR "small" is in `pr-risk.py` (`lines <= 150`).

## 9. Package manager configuration (npm / pnpm / yarn / bun)

The `install.sh` sets two npm configs by default: `ignore-scripts=true` and `min-release-age=2` (when supported). Both can be tuned, and equivalents for other package managers are below.

### Tuning the release-age buffer

The default is 2 days. Adjust upward if you want a wider margin:

```
npm config set min-release-age 3   # 3 days
npm config set min-release-age 7   # one week (more conservative)
```

Two days is where most malicious uploads have been caught by community/Socket detection by the time you'd install. A week is paranoid but defensible if you ship at unusual hours when detection lag is longest.

### Allowing scripts for specific packages

`ignore-scripts=true` is the right default but breaks packages that need build steps. The well-known cases:

- **`sharp`** — native image processing binary
- **`esbuild`** — binary install
- **`puppeteer`, `playwright`** — browser binary downloads
- **`cypress`** — binary install
- **`husky`** — git hooks setup
- **`node-gyp`, native modules** — build steps

When you hit a "command not found" or "binary not found" error after installing one of these, the fix is one of:

```bash
# Option A — install this package with scripts allowed
npm install <pkg> --ignore-scripts=false

# Option B — install normally, then run the build step manually
npm install <pkg>
npm rebuild <pkg>
```

Both work. Pick whichever feels less surprising in the moment.

### Equivalent configs for other package managers

If you use pnpm, yarn, or bun, set the equivalent on whichever you actually use:

**pnpm:**
```
pnpm config set ignore-scripts true
pnpm config set minimumReleaseAge 2880    # 2 days in minutes
```

**yarn (v4+):**
```
yarn config set enableScripts false
yarn config set npmMinimalAgeGate "48h"
```

**bun** (in `bunfig.toml` at project root or `~/.bunfig.toml`):
```toml
[install]
ignoreScripts = true
minimumReleaseAge = 172800   # 2 days in seconds
```

The threat model is identical across all four. Only the syntax differs.

### Verifying the settings stuck

```
npm config get ignore-scripts
npm config get min-release-age
cat ~/.npmrc                  # see the file directly
```

## What NOT to customize

A few defaults exist for safety reasons. Changing them weakens the baseline:

### Don't add per-project exemptions

The whole point of the system is **uniform protection**. The original draft of this protocol included a "personal vs production" project classification — letting personal projects skip the full pipeline. It was rejected because side projects evolve into real products, and the moment a category exists that gets less protection, it becomes a shortcut. The shortcut eventually contains something that doesn't deserve less protection.

If you want to skip a review for a specific push, use the explicit override (`skip review`, `push to main`). Don't bake exemptions into the rules.

### Don't lower the blocking severity

By default, only HIGH severity findings block the push; MEDIUM and LOW proceed with a report. Lowering this further (so MEDIUM blocks) makes the gate noisier and trains you to ignore it. Raising the threshold (so even HIGH doesn't block) defeats the gate's purpose.

### Don't default Push Routing to direct main pushes

The Push Routing protocol creates feature branches and PRs by default for a reason: it's what feeds Socket.dev its input. Pushing straight to main means Socket never sees the code until after merge. The PR-by-default rule is structural, not stylistic.

### Don't disable the lockfile drift check

The lockfile drift detection (in the Dependency Installation Gate) catches the specific attack pattern that hit Axios users — a trusted package compromised at the maintainer level pushing a malicious update under the same name. CVE-database checks won't catch this because there's no CVE yet. Keep it.

## After customizing

Test that your changes work:

1. Open a project that touches one of your stack-specific surfaces.
2. Make a small change and try to push.
3. Confirm the right things happen:
   - `/security-review` fires if the change touches a strict-gate surface
   - The PreToolUse hook prompts on a push to `main`
   - The global git hook warns on sensitive file changes (case-insensitive match against your regex)

If nothing fires, double-check your regex syntax (especially the `|` separators), confirm you saved the right files, and start a fresh Claude Code session so the updated `CLAUDE.md` loads.

## Add your own rules

The protocol is a starting point, not a ceiling. As you ship, you'll find rules you wish you'd had when something went wrong. Add them. The pattern to follow:

- **Soft rule (sometimes-fire):** Add to `CLAUDE.md` as a Reminder Gate item
- **Hard rule (always-fire):** Add to the Strict Gate list, or write a new hook
- **Mechanical guarantee:** Encode it in a hook script, not just an instruction

Each rule that fires once a week and catches something serious has earned its place. Each rule that fires every day and never catches anything is probably overfit to a fear, not a threat. Prune both ways.
