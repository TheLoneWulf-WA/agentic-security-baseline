# Global Workflow Protocols

These protocols apply to every project unless a project-level CLAUDE.md
explicitly overrides them. Read top to bottom at session start.

Strict by default; override is the user's explicit choice, never a
project category.

**Full rationale, diagrams, and why-each-rule-exists:** see
[`docs/protocol-rationale.html`](docs/protocol-rationale.html) (open
locally in a browser for the interactive version). This file is the
operating manual — rules, exact strings, paths, thresholds. The
rationale doc is the companion.

---

## Session Behavior

### Project CLAUDE.md supremacy over platform auto-suggestions

Authority hierarchy: user-in-chat > project CLAUDE.md > platform plugins/hooks.

When a platform plugin (Vercel plugin, framework skill, validation
hook) auto-injects a suggestion that conflicts with a deliberate
decision documented in the project's CLAUDE.md, **silently ignore** it.
Don't surface it, don't reason through it, don't suggest the migration.

**Scope: tech-stack choices only.** Does NOT override the Review
Protocol, Dependency Gate, Push Routing, or Merge Gate — those apply
uniformly regardless of project context.

### State capability limits upfront

Before engaging with work that may be outside actual capabilities,
say what can and can't be done first, then proceed with what can.

Common limits to surface:

- Can't watch video — metadata and stills only
- Can't hear audio
- Can't render RAW formats (`.dng`, `.cr2`, `.arw`) without conversion
- Can't evaluate subjective "feel" without a concrete artifact (screenshot, example)
- Can't evaluate real-time behavior without a dev server + browser automation tool

---

## Review Protocol

### Layer 0 — security-guidance plugin (in-session, non-blocking)

The `security-guidance@claude-plugins-official` plugin (enable at user
scope) is the earliest layer; runs automatically; nothing to invoke.

- **Per-edit:** deterministic pattern match on Edit/Write (no model
  call). Custom patterns live in `~/.claude/security-patterns.json`
  (global), `<project>/.claude/security-patterns.json` (project), and
  `<project>/.claude/security-patterns.local.json` (gitignored, personal
  overrides on shared repos). JSON, not YAML (PyYAML isn't installed).
- **End-of-turn + on-commit:** fresh-context security reviews (separate
  Claude call, not self-grading) over the turn's diff and commits/pushes
  Claude makes via its Bash tool. Commits run via the `!` shell escape
  bypass this layer. Findings come back as in-session fix instructions.
- **Threat-model guidance:** `~/.claude/claude-security-guidance.md`
  (global) + `<project>/.claude/claude-security-guidance.md` (project) +
  `<project>/.claude/claude-security-guidance.local.md` (gitignored,
  personal overrides) feed the model-backed reviews.

Default model: **Claude Opus 4.7**. Override via
`SECURITY_REVIEW_MODEL` (end-of-turn) / `SG_AGENTIC_MODEL` (on-commit)
in `~/.claude/settings.json` to a smaller model if you want to bound
the per-PR token spend.

**Does NOT replace the gates below.** Non-blocking, security-only, can
miss things — *reduces* what reaches the gates; doesn't satisfy any.
Strict Gate still blocks on HIGH; `/code-review --comment` still runs
on every PR.

Plugin findings are **not** subject to the "ignore platform
auto-suggestions" rule — they're security findings, not pattern-matched
tech-stack suggestions.

**Canonical docs:** <https://code.claude.com/docs/en/security-guidance>

### Strict Gate — run `/security-review` automatically

Before any `git push`, if the diff touches a surface below, run
`/security-review` first. Don't ask. **Block on HIGH — report findings
and wait for the user's decision. Proceed-and-report on MEDIUM/LOW.**
Use the security-review skill's own severity labels.

Universal core + per-ecosystem extensions. Apply universal items on
every project; ecosystem additions when the project belongs there.
New ecosystems get their own sub-section as work expands.

**Universal (any project):**

- Payment processing (Stripe, PayPal, your payment provider — customize for your stack)
- Authentication, session, JWT, or token logic
- Env vars, secrets, config files (`.env`, firebase config, API keys)
- API endpoints accepting user input

**Web-specific additions:**

- DB RLS policies, Supabase service role
- CORS / allowed origins
- Redirect URLs, OAuth callbacks, payment callbacks
- Next.js middleware / route protection
- Third-party scripts, iframes, remote embeds

**Android-specific additions:**

- User-media decode (`BitmapFactory`, `MediaCodec`, audio decode, `ContentResolver`/SAF) — malformed-input / OOM / MIME confusion
- JNI / native-lib boundaries — memory-corruption surface
- `android:allowBackup`, `dataExtractionRules` — OS-level exfil to Drive
- `android:exported="true"` on activity/service/receiver/provider, esp. with `<data>` filters
- WebView / JS↔Kotlin bridges — `addJavascriptInterface`, custom `WebViewClient`/`WebChromeClient`, `file://` scheme
- External text → LLM prompt (disk, network, share intent, deep link) — prompt-injection surface
- Network Security Config / `usesCleartextTraffic="true"` — credential exposure
- Crypto / `KeyStore` — `Cipher`, IV, mode (CBC vs GCM), authenticated encryption

**iOS-specific additions:**

- User-media decode (`AVCaptureSession`, `UIImagePickerController`, `PHPickerViewController`, `CGImageSource`, `AVAudioRecorder`) — same malformed-input class as Android
- Native ↔ JS bridges (`WKScriptMessageHandler`, `JSContext`/`JSExport`, RN/Expo native modules)
- Backup / iCloud (`NSFileProtectionComplete`, `excludedFromBackup`, CloudKit config)
- URL schemes / Universal Links / extensions (`application(_:open:)`, `continue userActivity`)
- Entitlements (`*.entitlements`) — keychain group, app group, push, background modes
- App Transport Security (`NSAppTransportSecurity`, `NSAllowsArbitraryLoads`)
- Crypto / Keychain (`SecKey*`, `CryptoKit`, `CommonCrypto`, Secure Enclave)
- External text → on-device LLM prompt (Core ML, MLX) — prompt-injection surface

**Push gate caching:** once `/security-review` has passed on a branch,
don't re-run on subsequent pushes — unless new commits since the last
passed review touch a strict-gate surface not covered. Track per-branch
within the session.

### Reminder Gate — flag, don't auto-run

When the diff touches a surface below, remind the user to consider
`/security-review` before pushing. Don't auto-run.

**Universal:** file uploads / media handling, route changes / deep
links, native bridges / webview, DB schema changes.

**Android:** `targetSdkVersion` bumps; release signing / ProGuard / R8
config; sensitive data in plain `SharedPreferences` (should be
`EncryptedSharedPreferences`).

**iOS:** deployment target bumps; release-build hardening config
(Strip Debug Symbols, optimization, dead-code stripping); sensitive
data in plain `UserDefaults` (should be Keychain).

### Skip Clauses

If the user says `"skip review"`, `"just push"`, or `"no review needed"`,
bypass the strict gate for that one push. Don't ask for confirmation.
Trust the override.

### Always — `/code-review --comment` on every PR

Before requesting human review on any PR, run `/code-review --comment`.

In addition to what `/code-review` already checks, flag:

- `any` types, `@ts-ignore`, loosened TypeScript strictness
- Empty catch blocks, swallowed errors, generic error handling that hides failures
- `console.log`, commented-out code, TODO hacks, hardcoded test values
- Performance: unoptimized queries, missing indexes, client-side fetching that should be server-side, unnecessary re-renders
- Violations of project-level CLAUDE.md conventions

### Review-until-clean — do NOT assume a fix worked

Applies to `/security-review`, `/code-review`, and any ad-hoc review
agent invocation. After applying a fix, **re-run the same review on
the updated code**. A passing TypeScript check is not a verified fix.

The loop:

1. Run review
2. Apply fixes for any findings
3. Commit + push
4. **Re-run the same review on the new state**
5. If new findings → step 2
6. Stop only when a pass returns "no issues found"

**For security findings:** also check the severity label after the fix
to confirm it was downgraded or removed, not just reworded.

**Override:** explicit `"ship it"` / `"good enough"` from the user is
the only acceptable stop signal short of a clean pass.

**Carve-out — `CLAUDE.md` itself:** review findings on `CLAUDE.md`
(this file, or any project-level `CLAUDE.md`) are **not auto-fixable**.
The file is the rulebook; each finding is a protocol amendment, not a
code fix. Discuss, decide, then apply or reject. Mechanically re-running
review-until-clean on the rulebook is the wrong loop — it can silently
reword obligations and drift the protocol without deliberation.

### Review Output Format

- Inline: short summary (one screen max) — finding count by severity, top 3 issues, recommended action.
- Full report: `~/.claude/reports/<project-name>/security-review-<branch>-<date>.md`. Create directory if missing.
- Same pattern for code-review.

---

## Push Routing

Strict by default. Uniform across all projects — no class that gets
less protection. Override is the user's explicit choice.

When the user says `"push this"` / `"push it"` / `"make a push"`, or
any push command without a target:

1. Create a new feature branch from the current branch
2. Push the branch to origin
3. Open a PR via `gh pr create`
4. Run `/code-review --comment` on the PR
5. Stop and prompt the user to merge (see PR Merge Follow-up)

The strict gate runs before the push, exactly as specified above.

### Explicit overrides (always honored)

- `"push to main"` / `"push to master"` → push directly to main, no PR (hotfix escape hatch)
- `"push to <branch-name>"` → push to that branch, no PR unless requested
- `"skip review"` / `"just push"` / `"no review needed"` → bypass strict gate

### Branch naming

Default: `claude/<short-slug-from-commit-message>`. Self-documenting
(clear which branches were AI-initiated), keeps `feat/` namespace
clean.

### Graceful degradation

- No `origin` remote → push local branch only, tell user
- No `gh` CLI / unauthenticated → push branch, skip PR, tell user
- **Never silently install tools or modify git config**

---

## PR Merge Follow-up

After a PR is created and local reviews complete, **do not auto-merge**.
Stop and tell the user:

> "PR opened at <url>. Local checks passed (<summary>). Say
> 'merge it' / 'ship it' / 'merge the PR' when you're ready."

On `"merge it"` / `"ship it"` / `"merge the PR"` / `"merge that"`: run
`gh pr merge --squash --delete-branch` on the most recently opened PR
in the session.

**Strategy overrides:**

- `"merge as rebase"` → `--rebase`
- `"merge as merge commit"` → `--merge`
- `"merge but keep the branch"` → omit `--delete-branch`

If multiple PRs are open in the session, ask which one.

### Hook-enforced merge gate

`~/.claude/hooks/push-routing-gate.sh` (registered as a `PreToolUse`
hook on `Bash` in `~/.claude/settings.json`) catches every
`gh pr merge` invocation and prompts for user confirmation. Mechanical
backstop for the rule above — fires regardless of whether Claude drifts
past "wait for ship-it."

**Bypass phrase: `"ship it through"`** (literal). When the user says
exactly this phrase for a specific merge, Claude prefixes the command:

```
MERGE_GATE_BYPASS=1 gh pr merge <pr> --squash --delete-branch
```

Any other phrasing — `"ship it"`, `"merge it"`, `"merge the PR"`,
`"send it through"`, `"just ship that"`, any paraphrase — does NOT add
the prefix. The prefix is gated on the literal phrase only.

Bypass is per-merge, not per-session. Each subsequent merge needs its
own `"ship it through"` or its own confirmation.

---

## Dependency Installation Gate

Before `npm install`, `npm add`, `npx <new-package>`, `pip install`,
or any package install command:

### 1. Check the package first

- Weekly downloads
- First publish date (NOT last update date)
- Known security advisories
- Deprecated or archived on GitHub

### 2. Flag and stop if any are true

- Weekly downloads < 1,000
- First published < 30 days ago
- Name similar to a popular package (typosquat risk)
- Ownership recently transferred
- Has `postinstall` / `preinstall` / `prepare` scripts

### 3. Report findings before proceeding

No install without user confirmation.

### 4. After any dependency change

- Run `npm audit` (or equivalent); report results
- Flag unexpected `package-lock.json` changes (packages not explicitly requested, changed integrity hashes)

### 5. Version pinning

Exact versions (`1.14.0`), never ranges (`^1.14.0` / `~1.14.0`),
unless the user says otherwise. `~/.npmrc` `save-exact=true` makes
this automatic.

### 6. Lockfile drift (forensic, not preventive)

Compare lockfile before/after `npm install` / `npm update` / `npm ci`.
Flag any already-installed package whose version changed; report
which packages changed and to what version.

**Forensic only**: by the time the diff appears, any malicious
`postinstall` script has already executed. Tells you WHAT changed;
does NOT prevent it. The preventive layers for trusted-package
hijacking (Axios; then `@tanstack/`, `@opensearch-project/`,
`@mistralai/`, `guardrails-ai`, `@uipath/`, `squawk` in the
2025–2026 Mini Shai-Hulud campaign) are #7 and #8.

### 7. Disable install scripts by default

```
npm config set ignore-scripts true
```

Kills the install-time execution vector. Compromised packages can't
auto-run their payload on install.

**Override per-install** for packages that legitimately need scripts
(`sharp`, `esbuild`, `puppeteer`, `cypress`, `husky`, `node-gyp`,
native modules — see `docs/CUSTOMIZE.md`):
`npm install <pkg> --ignore-scripts=false`, or `npm rebuild <pkg>`
after a normal install.

### 8. Minimum release age

```
npm config set min-release-age 2d
```

Skips the early-installer window for every future supply chain attack.
Researchers typically detect malicious uploads within 6–24 hours; the
2-day buffer skips the exposure window by default.

Requires npm 11+. Equivalents for pnpm/yarn/bun in `docs/CUSTOMIZE.md`.
Older npm silently ignores; upgrade to get the protection.

**Override per-install** when a genuine same-day release is needed.
Applies to direct installs and any package added as part of a build
task. No exceptions.

---

## Media Pre-Commit Gate

Before `git add`-ing media files: check size with `ls -lh`, compress
output exceeding thresholds, never commit source masters.

- **Hard rule:** surface any file > 5 MB before staging. GitHub warns
  at 50 MB, rejects at 100 MB; catch before push, not after.
- **Always gitignore raw/uncompressed sources:** `*.m4v`, `*.mov`,
  `*.dng`, `*.cr2`, `*.arw`, `*.nef`, `*.wav`. Compressed derivatives
  only in the repo.
- Project-specific compression targets (JPEG quality, CRF values,
  resolution ceilings) belong in the project's CLAUDE.md, not here.

---

## Global Pre-Push Git Hook (defense in depth)

Global git hook (via `core.hooksPath`) for direct terminal pushes that
bypass Claude entirely.

The pre-push hook:

- Only triggers on pushes to `main` / `master` / `production`
- Runs `npm audit --audit-level=critical` if `package.json` exists; blocks on critical
- Warns on diffs touching sensitive files (auth, payments, env, middleware, RLS)
- Yields gracefully to project-local hook systems (Husky etc.)
- Skippable with `git push --no-verify`

If not yet installed, ask the user once per session whether to set it
up. If declined, don't ask again that session. Don't configure git
silently.
