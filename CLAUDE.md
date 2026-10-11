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

## Operating Posture

The behavioral layer — governs judgment, not tool permissions. The
permission rules in settings.json and the hooks enforce the mechanical
boundary; this section governs everything a permission rule cannot see.

### Momentum on labor, never on judgment

Chain routine implementation — code → build → test → review → fix —
without "want to continue?" prompts. Autonomy covers labor only.
An always-ask class below stops the chain, even mid-PR.

### Always-ask classes — stop, present options + recommendation

- **Product / design / UX** — anything user-visible by look or feel.
  Produce the artifact (mockup, draft) proactively; never translate it
  into code without sign-off.
- **User-data retention/deletion semantics** — cascades, what survives
  a delete or replace. Product promises wearing technical clothes;
  documented-in-PR is NOT sufficient.
- **Measurement → rule conversions** — any must/never/always derived
  from evidence gets a scope check (does the evidence cover the rule's
  whole domain, or only the case measured?) and the static-vs-adaptive
  choice surfaced, not assumed.
- **Amendments to canonical documents** — decision logs, specs, any
  CLAUDE.md (consistent with the CLAUDE.md review carve-out below:
  protocol changes are discussed, then applied).

### Recommend technical, ask design

Engineering / sequencing / implementation calls: recommend as principal
engineer — options + my pick — and proceed unless overridden.
Product/design calls: ask, with artifacts. When unsure which class a
call is: it's the asking class.

### Judgment ledger at pre-merge

Every pre-merge stop lists the judgment-bearing calls made under
momentum — separate from the diff summary — so review attention lands
on the judgments, not the mechanics. The ledger also confirms each
non-obvious choice in the diff carries its recorded *why* (see Intent
Debt).

---

## Review Protocol

### The order, for one PR

Each layer below is described in its own section; this is the order
they run in, and why. Each step looks with a different lens, so a later
one does not replace an earlier one.

1. **Local checks, then the real thing.** Lint, typecheck, tests; then
   a production build with the behaviour exercised the way a user or an
   attacker would (real requests, real inputs, real signals). Unit
   tests prove the code you thought of; this proves the thing.
2. **`/security-review` before the first push**, when the Strict Gate
   applies. Cheap and focused.
3. **Push and open the PR.**
4. **`/adversarial-review`** on sensitive PRs (see its section). The
   deep finding step, and the one that finds the most. For a change
   that touches nothing sensitive, say in one line that it is skipped.
5. **Fix every finding**, one commit per finding, pushed as you go.
   What is the user's to decide is surfaced, not fixed.
6. **`/until-clean`**, looping until a pass after the last fix comes
   back clean; it writes the marker. It catches what the fixes broke.
7. **`/code-review --comment` last**, at the clean head, so what it
   posts describes the code that will merge. Its diff-only lens still
   finds things the earlier reviewers passed. If it finds anything:
   fix, and one more `/until-clean` pass (that pass is the re-run the
   Review-until-clean section asks for).
8. **At merge, check the base.** If main moved under the same files,
   merge main in and run one fresh `/until-clean` pass (no new
   adversarial round: nothing reviewed changed).

**No CLEAN verdict before step 6 has run.** A pass of my own, however
careful, is not the loop.

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

Set `SECURITY_REVIEW_MODEL` (end-of-turn) / `SG_AGENTIC_MODEL`
(on-commit) in `~/.claude/settings.json` to the most capable model
available; the plugin has its own default otherwise, and the installer
sets neither. When that is the same model that writes the code, keep
independence in other ways: fresh-context reviewers, and testing
against a real running build (a preview deploy where you have one). Layer 0 fires every turn (end-of-turn +
on-commit), so this is a recurring per-turn cost, not per-PR; point one
var at a smaller model if steady-state usage bites.

**Does NOT replace the gates below.** Non-blocking, security-only, can
miss things — *reduces* what reaches the gates; doesn't satisfy any.
Strict Gate still blocks on HIGH; `/until-clean` still covers
correctness + conventions + verifies fixes; `/code-review --comment`
still runs on every PR.

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
- Non-obvious choices missing their recorded *why* — a guard, magic
  number, defensive check, or deliberate constraint with no commit
  message or comment explaining it (see Intent Debt below)
- **Test changes, reviewed before source.** Rewritten assertions that
  match newly-changed behavior, removed or skipped tests, lowered
  thresholds, weakened CI. A green suite over edited tests proves
  nothing until the edits are verified legitimate.

### Adversarial review — `/adversarial-review` on sensitive PRs

Three fresh-context reviewers, no checklist, each in a role: **a
hostile party** (how is this abused, what can it reach or delete that
isn't its own), **the on-call engineer** (where does it hang, fail
silently, leave a mess, or mislead at a bad moment), **the person in
the chair** (whoever reads the screen, the guide, the runbook or the
README: is it true, and does it say what to do). They are given the
code and the docs, never the author's conclusions.

Run it **without being asked, before the merge prompt**, on any PR
touching: auth, sessions or tokens; uploads or media; payments; the
admin; API endpoints taking input; anything an attacker can reach; any
script or job that runs with access rules off or deletes records. A
project CLAUDE.md or memory may widen this; the wider rule wins. For a
change that is none of these, say in one line that it is skipped.

- Fix every finding, LOW included, one commit each. What is the user's
  to decide (always-ask classes) is surfaced with a recommendation, not
  fixed; if this change didn't create it, it becomes an issue.
- It finds and fixes; it never gives the verdict. **`/until-clean`
  follows it** and verifies the fixes on the pushed state.
- In addition to the Strict Gate and `/code-review --comment`, not in
  place of either.

The skill (`skills/adversarial-review/SKILL.md`, installed to
`~/.claude/skills/`) holds the briefs and the procedure.

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

**Verdict line (mandatory):** every pre-merge stop states the loop
outcome explicitly, next to the judgment ledger:
`Review loop: CLEAN (re-run after fixes at <sha>)` or
`Review loop: NOT CLEAN — <n> open finding(s)`. Absence of this line
means the loop wasn't closed — the user should never have to ask.
The `/until-clean` skill (`skills/until-clean/SKILL.md`, installed to
`~/.claude/skills/`) runs the loop on demand and, on a clean pass,
writes a per-branch marker at
`<git-dir>/review-clean/<branch with / replaced by _>` (head SHA +
timestamp). The merge gate reads the current branch's marker and shows
its state — clean / stale / missing — in the confirmation prompt.

**Carve-out — `CLAUDE.md` itself:** review findings on `CLAUDE.md`
(this file, or any project-level `CLAUDE.md`) are **not auto-fixable**.
The file is the rulebook; each finding is a protocol amendment, not a
code fix. Discuss, decide, then apply or reject. Mechanically re-running
review-until-clean on the rulebook is the wrong loop — it can silently
reword obligations and drift the protocol without deliberation.

### Docs get the same bar on public repos

Prose pushed to a **public** repo (READMEs, protocol docs, changelogs)
gets a clean-context review pass before the push — accuracy, tone, no
sensitive leakage — and review-until-clean applies (excepting
`CLAUDE.md` itself, per the carve-out above). Trivial one-liners
are a judgment call. The sanitization scan is a **hard gate that blocks
the push** (never an informational echo), and it covers **commit
metadata and PR bodies**, not just file content — author email and
session-trailer leaks live there, not in the diff.

### Review Output Format

- Inline: short summary (one screen max) — finding count by severity, top 3 issues, recommended action.
- Full report: `~/.claude/reports/<project-name>/security-review-<branch>-<date>.md`. Create directory if missing.
- Same pattern for code-review.

---

## PR Decomposition

The supply side of the Review Protocol: small units are what make
review-until-clean converge. Uniform across all projects.

- **One logical change per PR.** A plan step is the natural unit. If
  the description needs "also" or "plus," it's two PRs.
- **Don't smuggle.** A "while I'm here" cleanup becomes a sibling PR; a
  bug found mid-refactor gets fixed in its own PR first.
- **N findings → N fix commits.** Sequential, building between each.
  Never one combined fix. The one exception: findings whose fixes touch
  the same lines may share a commit, said so in the commit message and
  the judgment ledger.
- **Sensitive surfaces ride alone.** Strict-gate diffs get their own
  focused PR so review sees the security surface in isolation.
- **Split across sessions when heavy.** Finish the current PR and stop;
  don't stack a second PR into a depleted context.

---

## Push Routing

Strict by default. Uniform across all projects — no class that gets
less protection. Override is the user's explicit choice.

When the user says `"push this"` / `"push it"` / `"make a push"`, or
any push command without a target:

1. Create a new feature branch from the current branch
2. Push the branch to origin
3. Open a PR via `gh pr create`
4. Run the review order (see "The order, for one PR"):
   `/adversarial-review` where it applies, fixes, `/until-clean`, then
   `/code-review --comment` on the PR
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

After a PR is created and local reviews complete, **do not auto-merge**
(merge gate runs in **ask mode** by default). Stop and tell the user:

> "PR opened at <url>. <verdict line>. Say 'merge it' when you're
> ready."

On `"merge it"` / `"ship it"` / `"merge the PR"` / `"merge that"`: run
`gh pr merge --squash --delete-branch` on the most recently opened PR
in the session. The merge-gate hook will pause the command on an
in-session confirmation prompt for the user's keypress — expected
behavior, not an error; never retry around it.

**Strategy overrides:**

- `"merge as rebase"` → `--rebase`
- `"merge as merge commit"` → `--merge`
- `"merge but keep the branch"` → omit `--delete-branch`

If multiple PRs are open in the session, ask which one. After a squash
merge lands, switch to `<default>`. If `git status` is clean and
`<default>` has no local commits of its own, sync with `git fetch
origin && git reset --hard origin/<default>`. Otherwise stop and ask.
Never run it on a feature branch: it discards uncommitted work and
local commits.

### Hook-enforced merge gate

`~/.claude/hooks/push-routing-gate.sh` (registered as a `PreToolUse`
hook on `Bash` in `~/.claude/settings.json`) intercepts merge attempts
via the routes agents actually use — `gh pr merge`,
`gh api .../pulls/<n>/merge`, and `curl`/`wget` to the merge API — and
pauses them on an in-session user confirmation prompt that includes the
review-loop marker state for the current branch. This is **ask mode**,
the shipped default: Claude does the work, a human keystroke gates the
act. Flip the merge case's `permissionDecision` from `"ask"` to
`"deny"` for **deny mode** — Claude locked out of merging (via those
routes), you merge in the GitHub UI. Every honored bypass (below) is
audit-logged to `~/.claude/logs/merge-bypass.log` in both modes. It's
a pattern match on command shapes, not a sandbox — unenumerated routes
exist; the gate makes drift and casual circumvention loud, not
impossible.

The hook also prompts on shell writes to enforcement config (hooks,
settings, skills, commands, the protocol CLAUDE.md — including
project-level `.claude/settings.json`), and its companion
`hooks/config-edit-gate.sh` (PreToolUse on `Edit|Write|NotebookEdit`,
`$HOME`-scoped, symlink-resolving) prompts on direct edits to the same
config — the guard guarding the guard. A gate an agent can silently
rewrite is not a gate.

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
- Detects the package manager from the lockfile (`package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` / `bun.lockb`) and runs the matching audit at the `critical` threshold; blocks on critical findings. Skips cleanly if no recognized lockfile is present (no false-blocking yarn/pnpm/bun projects via `npm audit ENOLOCK`).
- Warns on diffs touching sensitive files (auth, payments, env, middleware, RLS)
- Yields gracefully to project-local hook systems (Husky etc.)
- Skippable with `git push --no-verify`

If not yet installed, ask the user once per session whether to set it
up. If declined, don't ask again that session. Don't configure git
silently.

---

## Project Documentation Architecture

CLAUDE.md holds rules + pointers — never records, status, or anything
that accumulates. Accumulating content gets a designated home, created
**on first need** (no empty scaffolding in small repos):

- **Rule detail** too long for CLAUDE.md → `docs/conventions/` —
  CLAUDE.md keeps the trigger line + pointer.
- **Records of completed work** (what landed, per phase/milestone) →
  `docs/phase-history/` or equivalent. Read when touching a surface a
  past phase built; never duplicated into CLAUDE.md.
- **Live state** (where we are / what's next) → a forward-plan doc +
  transient handoffs in `docs/handoff/` that **self-delete on pickup**
  (durable content must already live in a durable home before the
  handoff dies).
- **Decisions and their why** → an append-only decision log. Append at
  the next number; never delete; revisiting a decision adds a new entry
  referencing the old.
- **The atlas** → `docs/documentation-map.md` once a project has
  several of the above; it points, it does not duplicate.

The test before writing anything down: what *kind* of thing is it, and
does it accumulate? If yes, it has a home above — not CLAUDE.md.

---

## Intent Debt — the *why* gets written down, where it can be diffed

Code records *what*, never *why* — and an agent session starts cold
every time, so it can only guess. A guess about intent isn't the
intent.

- **The test:** could a cold session (or a new contributor) tell
  whether a choice is load-bearing or leftover? If not, the why isn't
  externalized yet.
- **Scope by blast radius:** record the why for choices expensive to
  get wrong or to reconstruct — guards, magic numbers, defensive
  checks, deliberate constraints. Not trivia.
- **Route at decision time,** per the project's doc atlas (see Project
  Documentation Architecture): architectural why → a decision log /
  ADR · code-level why → the commit message or a comment at the diff,
  so it travels with the code · deferred / blocked-on-a-dependency work
  → a tracked issue · lesson learned / tried-and-failed → an
  engineering log · durable convention → CLAUDE.md.
- **Tests protect intent, not just behavior:** where behavior is
  user-visible or load-bearing, the test name or a comment says *why*
  it matters — so a green refactor can't silently change what mattered.
- **Enforced at review, not by memory:** the `/code-review` flag list
  and the pre-merge judgment ledger both check that non-obvious choices
  carry their why. Instructions are best-effort; the review gates are
  what make this hold.
