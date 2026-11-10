# Changelog

Dated events in this protocol's lifecycle. Newest first.

## 2026-11-10

Review cost limits. Usage was hitting plan limits, and late review
passes were mostly finding PR-description wording, so the loop got
limits (new "Cost limits" block in `CLAUDE.md`, under Review-until-clean):

- **Pass cap:** at most 3 loop passes. Wording-only findings are fixed
  in one batch and never start a pass; only a MEDIUM or HIGH code
  finding earns a 4th; still open after that is NOT CLEAN.
- **Models by risk:** in the loop and in `/code-review`, Opus for the
  bug reviewer on sensitive PRs only; Sonnet for everything else and for
  compliance reviewers.
- **`/code-review` size:** normal-risk PRs of 150 changed lines or fewer
  get 2 Sonnet agents instead of 4.
- **Risk is mechanical, and missed files fail safe:** new
  `scripts/pr-risk.py` (with a `pr-risk.sh` wrapper) and shared lists in
  `risk-paths/`. A PR is normal only when every changed file, renames'
  old names included, is on a safe list (`_default-safe.txt`: docs,
  images, fonts, styles; plus the project's `.claude/safe-paths.txt`)
  and no sensitive signal fires (shared risky paths, code-file names and
  words in added lines for web, Android, iOS and Expo, plus an optional
  project `.claude/risk-paths.txt`). Anything else is sensitive. It
  fails safe on a bad pattern, a missing or empty shared list, or a diff
  it can't read. Project lists are read from the PR's base branch, and
  any change under `.claude/` is sensitive. New-project rule:
  `pr-risk.sh --suggest` drafts a safe list of folders where no file
  trips a risky check; a session reviews every line and opens it as its
  own PR.
- **Why a safe list:** the first version was a risky list. Reviewing it
  took four passes, and each pass found risky files the list had missed,
  18 in all, plus a pattern bug that made a check fail open. All were
  fixed before release. With a risky list, a file nobody thought of gets
  the cheap review; with a safe list, it gets the full one.

Also in `CLAUDE.md`: the light lane for docs-only and look-only PRs (one
loop pass, then the final code review; from 2026-11-05); the
`/adversarial-review` trigger for the admin narrowed to actions that
move money or change accounts or permissions, not wording, layout, help
text or read-only display; and Layer 0 on Sonnet 5.5, because it fires
every turn in every session.

`skills/until-clean/SKILL.md` now carries the pass cap, models by risk,
the light lane, wording-only findings, a final `/code-review --comment`
at the clean head before the marker is written, and a report file.
`skills/adversarial-review/SKILL.md` carries the narrowed admin trigger.

New `commands/code-review.md`: a modified copy of the official
`code-review` plugin's command (Apache License 2.0, in
`commands/LICENSE-code-review`). It re-reviews each new head commit,
posts a "Reviewed at `<sha>`" summary, and sizes itself with
`pr-risk.sh`.

`install.sh` and `docs/INSTALL.md` install the script, its four lists
and the command. Files that already exist and differ from the repo's
copy, the two skills included, are backed up with a timestamp first;
identical ones are left alone. The command's `allowed-tools` line gets
your home path substituted, as the settings snippet does.
`docs/CUSTOMIZE.md` has a new section 8 on the risk lists (package
manager configuration is now 9).

New `docs/review-cost-rationale.html` explains the reasoning, what still
protects money and data, and the known weaknesses. Linked from the
README, `CLAUDE.md` and `docs/protocol-rationale.html`, whose Layer 0 and
Review-until-clean cards are updated to match.

## 2026-10-21

Feature branches push freely. Claude may now push its own `claude/*`
branch and open the PR without being asked, after the Strict Gate's
`/security-review` where it applies. New paragraph in `CLAUDE.md` (Push
Routing) and rule 3.0b in `docs/protocol-rationale.html`.

Two layers keep it to that one case. `settings.snippet.json` allows only
`git push [-u|--set-upstream] origin claude/*` and `gh pr create`. The
push gate in `hooks/push-routing-gate.sh` now fails closed: it lets a
push through only when every push segment in the command is exactly
`git push [-u] origin claude/<name>`, and asks on everything else.
Before, it asked only when main/master/production appeared in the
command text, which missed `--all`, `--mirror`, force-pushes, tags,
deletes, other remotes and URLs, a protected name followed directly by
`;`, and names hidden in quotes or variables. That did not matter while
every push prompted; with feature pushes allowed, it would have. A push
command the hook cannot parse asks too, as do `git send-pack`, `git
subtree push`, pushes with global options (`--no-pager`, `--git-dir`,
`-c`), anything before `git` (`VAR=`, `env`, a subshell), a push with
`cd`/`pushd`/`popd` anywhere in the command, and a push in a repo whose
config could redirect or widen it: `remote.origin.push`, `push.default`
upstream or tracking (a branch created from `origin/main` would push to
`main`), `push.followTags`, `push.recurseSubmodules`, or a tag named
like the branch, a pushurl or `pushInsteadOf` rewrite, or
`remote.origin.mirror`. Booleans are read with git's own parser. The
whole command must be the push, optionally followed by `&& gh pr
create`: anything before it in the same command (`git config`, `export
GIT_*`, `git tag`) could change where it lands after the hook checked.
Input the hook cannot read (no `jq`, not JSON) asks.

`install.sh` and `docs/INSTALL.md` now concatenate `permissions.allow`
and `permissions.ask` when merging the snippet, the same way they
already did for `hooks.PreToolUse`. Without it, jq's `*` would have
replaced the user's own allow and ask lists with the snippet's. The
installer now says what it allowed and how to keep prompting.

## 2026-10-10

Fixed the `min-release-age` value everywhere it is set or suggested
(`CLAUDE.md`, `install.sh`, `tools/audit.sh`, `README.md`,
`docs/CUSTOMIZE.md`): npm documents it as a plain number of days, so
`2`, not `2d`. The 2026-05-13 entry below keeps the old spelling as a
record of what shipped then. **If you installed before this date, run
`npm config set min-release-age 2`** (or re-run `install.sh`): npm rejects
`2d`, and on recent npm 11 it makes installs fail with "Invalid time
value". `tools/audit.sh` now shows the value in green only when it is a plain
positive number of days (fractions such as `0.5` included) under
10,000, and otherwise (`2d`, `0`, a negative number, or 10,000 days or
more, a cutoff from before npm existed) shows
the command to fix it.

Brought the repo up to date with the protocol as it is used today.

Set an order for the reviews on one PR, in a new "The order, for one
PR" section at the top of the Review Protocol: local checks and a real
run of the thing, `/security-review` before the first push, push and
open the PR, `/adversarial-review` on sensitive PRs, fix every finding,
`/until-clean` until a pass after the last fix is clean, then
`/code-review --comment` last, at the clean head, and a fresh
`/until-clean` pass if main moved under the same files before merge.
The order came from what each step caught in practice: each looks with
a different lens, the role-based review found the most, the
verification pass caught what the fixes broke, and the diff-only
`/code-review` still found things the earlier reviewers had passed —
so it runs last, where its comments describe the code that will merge.

The adversarial review became a slash command. New:
`skills/adversarial-review/SKILL.md` (`/adversarial-review` — three
fresh-context reviewers, each in a role: a hostile party, the on-call
engineer, the person in the chair; no checklist, never the author's
conclusions; fixes every finding, LOW included, and hands off to
`/until-clean`, which gives the verdict). `CLAUDE.md` gained a matching
section saying when it runs without being asked. `install.sh` and
`docs/INSTALL.md` install it the same way as `/until-clean`; no hook or
settings change was needed.

Other sections had been added to the live protocol since the last sync
and are now here: Operating Posture (momentum on labor, never on
judgment; the always-ask classes; recommend technical, ask design; a
judgment ledger at every pre-merge stop), PR Decomposition, and Project
Documentation Architecture. Smaller edits: Layer 0 now says to set
its two model variables to the most capable model available (the
installer sets neither), and both `/until-clean` reviewers run on that
model too; the verdict line sits next to the judgment ledger; Intent
Debt routes the why through the project's doc atlas and is checked by
the ledger as well as `/code-review`; Push Routing's "push this" runs
the review order rather than going straight to `/code-review`; findings
whose fixes touch the same lines may share a commit, said so in the
message and the ledger.

**New: a destructive step, guarded from the start.** After a squash
merge the protocol now syncs the local default branch with `git reset
--hard origin/<default>`, which discards uncommitted work and local
commits. It runs only from a clean default branch with no local
commits of its own, and otherwise stops and asks; never on a feature
branch.

`docs/protocol-rationale.html` does not cover these changes yet, and
still shows `min-release-age 2d`; a rationale-doc update follows in its
own change, per the convention this changelog's 2026-07-06 entry set.

## 2026-08-10

Mechanized the review-until-clean loop and hardened the merge gate.
Motivated by a live drift incident: review findings were fixed, the
mandatory re-review didn't run until asked for — and when it ran, it
surfaced a new bug the first pass had missed. Prose rules drift under
momentum; the fix was moving the loop into invocable and mechanical
layers.

New: `skills/until-clean/SKILL.md` (the `/until-clean` slash command —
runs the loop, verifies each prior finding is resolved rather than
reworded, reports a fixed-format verdict line, writes a per-branch
clean marker recording the head SHA of the clean pass). New:
`hooks/config-edit-gate.sh` (prompts on agent edits to the enforcement
config itself — hooks, settings, skills, commands, the protocol
CLAUDE.md; Edit/Write/NotebookEdit, symlink-resolving). Updated:
`hooks/push-routing-gate.sh` now intercepts merges via `gh pr merge`,
`gh api`, and `curl`/`wget` to the merge API in ask mode — the agent
merges, a human keystroke gates the act, and the prompt reports the
current branch's marker state (clean / stale / missing) — with a
documented one-word flip to deny mode; the `"ship it through"` bypass
is audit-logged to `~/.claude/logs/`; the protected-branch push check
is now refspec-aware (`HEAD:main`, trailing flags). Updated:
`CLAUDE.md` (mandatory verdict line at every pre-merge stop; ask-mode
merge protocol), `settings.snippet.json` (wires the Edit/Write/
NotebookEdit gate), `install.sh` (places the new pieces; settings merge
now preserves existing PreToolUse hooks), README.

`docs/protocol-rationale.html` still describes the pre-mechanization
merge gate — a rationale-doc update follows in its own change, per the
convention this changelog's 2026-07-06 entry set.

## 2026-07-06

Brought docs/protocol-rationale.html up to date with the 2026-07-05
protocol additions: a new Section 08 (Intent Debt) with the
externalize-the-why rule and its rationale, a new Rule 2.6 card for
the docs-same-bar rule (including the two real incidents that
motivated it), the two new flag-list bullets on the Rule 2.4 card
with their reasoning, and TOC entries for all of it. The rationale
doc had gone stale against the rulebook — which is itself the
intent-debt failure the new section describes.

## 2026-07-05

Added the Intent Debt section to CLAUDE.md, plus a matching item in
the `/code-review` flag list. Motivated by Addy Osmani's "intent debt"
framing: code records *what*, never *why*, and an agent session starts
cold every time — so the why has to be written where it can be diffed.
The section scopes the rule by blast radius (guards, magic numbers,
deliberate constraints — not trivia), routes each kind of why to its
home (decision log, commit message, issue, engineering log), and
enforces it at the review gate rather than relying on the writing
agent's memory. Same pattern as the rest of the protocol: instructions
are best-effort, gates are what hold.

Two more review-gate rules in the same change. Test changes get
reviewed before source — rewritten assertions, removed or skipped
tests, lowered thresholds; a green suite over edited tests proves
nothing until the edits are verified legitimate. And docs pushed to
public repos get the same review bar as code, with the sanitization
scan as a hard blocking gate that covers commit metadata and PR
bodies, not just file content.

## 2026-06-01

Fixed `hooks/pre-push` to be package-manager-aware. The hook
previously ran `npm audit --audit-level=critical` whenever
`package.json` existed, without checking whether the project actually
uses npm. On yarn / pnpm / bun projects (no `package-lock.json`),
`npm audit` fails with `ENOLOCK` — which the hook interpreted as a
critical-vuln finding and false-blocked the push. False-blocking is
worse than not auditing: adopters lose trust in the hook and disable
it with `--no-verify` as muscle memory, which then hides the cases
where the hook would have caught a real vuln.

The hook now:

- Detects the package manager from the lockfile: `package-lock.json`
  → npm; `yarn.lock` → yarn (Classic if v1; Berry if v2+);
  `pnpm-lock.yaml` → pnpm; `bun.lockb` → bun
- Runs the matching audit command at the `critical` threshold:
  - npm: `npm audit --audit-level=critical`
  - yarn 1.x (Classic): `yarn audit --level critical`
  - yarn 2+/3+/4+ (Berry): `yarn npm audit --severity critical --recursive`
  - pnpm: `pnpm audit --audit-level critical`
  - bun: `bun audit` (when the subcommand is available in the
    installed bun version; otherwise skips with a note)
- Skips cleanly with an informational message if `package.json`
  exists but no recognized lockfile is present, or if the matching
  package manager isn't on `PATH`
- Reports which tool found the vulns and which command to re-run for
  full output when blocking

`CLAUDE.md` (the "Global Pre-Push Git Hook" section), `README.md`
(the `hooks/pre-push` bullet), and `docs/protocol-rationale.html`
(Section 7 rule block and its "Why this exists" callout) updated to
describe the new behavior. The rationale doc additionally documents
*why* the design is detection-first.

`install.sh` is unchanged — it copies whatever hook file is in the
repo, so users running `install.sh` after this commit get the fix
automatically. Users who already ran `install.sh` can either re-run
it or copy `hooks/pre-push` to `~/.config/git/hooks/pre-push`
manually to pick up the fix.

## 2026-05-29

Compressed `CLAUDE.md` and split the rationale into a new
`docs/protocol-rationale.html`. The operating manual (`CLAUDE.md`,
loaded into every Claude Code session) now carries only rules, exact
strings, paths, env vars, and thresholds. The "why each rule exists"
prose — with inline-SVG diagrams for the authority hierarchy, defense
stack, review-until-clean loop, push routing flow, merge-gate bypass
mechanic, and dependency-gate layers — moved to the rationale doc.

Why the split: `CLAUDE.md` is a permanent context tax, loaded every
session. Trimming rationale-bloat from it without losing the reasoning
required somewhere to put the reasoning. The rationale doc is
self-contained HTML with a sticky TOC (scroll-tracking active state
via a small `IntersectionObserver`) and embedded SVGs — fetch it when
you want the why, ignore it when you just want the rule.

Result: `CLAUDE.md` 538 → 356 lines (~34% reduction). **No rule
removed; no exact-string, path, env-var, threshold, or behavior
changed.** Rules that already read tersely (Skip Clauses,
`/code-review` on every PR) are unchanged.

**Maintenance discipline:** when a rule changes in `CLAUDE.md`, update
the matching section in `docs/protocol-rationale.html` in the same
commit. The doc's footer carries the same note inline.

Also: `README.md` updated to list the new doc under "What's in here"
and to note that `CLAUDE.md` is lean by design.

## 2026-05-20

Added `tools/audit.sh` — a read-only machine check for the Mini
Shai-Hulud / TanStack-class supply-chain worm. It checks for the
gh-token-monitor persistence daemon (macOS LaunchAgent + Linux
systemd), dropped scripts, IOC strings in `.claude/settings.json`
and `.vscode/tasks.json`, affected package namespaces in lockfiles,
and whether `ignore-scripts` / `min-release-age` are set. Read-only:
it reports, it never modifies or revokes anything. Documented in the
README under "Check a machine for compromise."

The follow-up article covering the 2026-05-13 through 2026-05-18
changes is live: "It Is 'Next Time' Already"
(https://atmr.substack.com/p/it-is-next-time-already).

## 2026-05-18

Added hook-enforced PR merge gate.

The PR Merge Follow-up protocol was previously instruction-only —
Claude was supposed to stop after opening a PR and wait for the user
to say "merge it" / "ship it" before running `gh pr merge`. Like all
instructions, that was best-effort. A Claude in a high-momentum flow
could autonomously merge after creating a PR, skipping the explicit-
approval step.

This update adds a mechanical backstop. `hooks/push-routing-gate.sh`
now catches any `gh pr merge` invocation and prompts the user, exactly
like the existing protected-branch push gate.

Bypass: `MERGE_GATE_BYPASS=1` env-var prefix. Claude adds the prefix
only when the user says the **exact** phrase `"ship it through"` —
not any paraphrase. Variations like `"ship it"`, `"merge it"`,
`"merge the PR"`, `"send it through"`, `"just ship that"`, etc., do
NOT trigger the bypass; those still hit the prompt. The bypass is
per-merge, not per-session — each subsequent merge needs its own
explicit phrase or its own confirmation.

`CLAUDE.md` gained a "Hook-enforced merge gate" subsection under PR
Merge Follow-up that documents the behavior and the bypass.

The forkable hook script in this repo now includes the merge gate.
`install.sh` is unchanged — it copies whatever hook script is in the
repo, so users running `install.sh` after this update get the new
hook automatically.

## 2026-05-15

Restructured the Strict Gate and Reminder Gate (in `CLAUDE.md`'s
Pre-Push Review Protocol) from a single flat list into a universal
core plus per-ecosystem extensions. Added Android-specific AND
iOS-specific extensions in the same wave:

- **Strict Gate — Universal:** payment processing, auth/session/JWT,
  env vars/secrets, API endpoints accepting user input. Items every
  project gets regardless of platform.
- **Strict Gate — Web-specific:** RLS policies, CORS, OAuth callbacks,
  Next.js middleware, third-party scripts (the items previously
  treated as universal but actually web-flavored).
- **Strict Gate — Android-specific (new):** capture code paths
  (camera/audio/image bytes via `BitmapFactory` etc.), JNI / native
  boundaries, `allowBackup` / `dataExtractionRules`, component
  `exported="true"` changes, WebView / JS↔Kotlin bridges
  (`addJavascriptInterface`), external text becoming a system prompt,
  Network Security Config / cleartext traffic, cryptographic operations
  / `KeyStore` usage.
- **Strict Gate — iOS-specific (new):** capture code paths
  (`AVCaptureSession`, `UIImagePickerController`,
  `PHPickerViewController`, `CGImageSource`, `AVAudioRecorder`),
  native ↔ JS bridges (`WKScriptMessageHandler`, `JSContext` /
  `JSExport`, React Native / Expo native modules),
  `NSFileProtectionComplete` / `excludedFromBackup` / iCloud
  exclusion attributes, URL scheme and Universal Links handlers,
  entitlements changes, App Transport Security (ATS) exceptions,
  cryptographic operations / Keychain Services usage, external text
  becoming a system prompt.
- **Reminder Gate — Android-specific (new):** `targetSdkVersion` bumps,
  release signing / ProGuard or R8 config changes, sensitive data
  stored in plain `SharedPreferences`.
- **Reminder Gate — iOS-specific (new):** iOS deployment target
  bumps, release build hardening config changes, sensitive data
  stored in plain `UserDefaults`.

The previous flat list was implicitly web-flavored. As active work
expanded into Android (and iOS is in-scope across multiple Expo
projects), the protocol's calibration left real risk surfaces
without coverage. The restructure scales to new ecosystems (Solana
mobile, embedded, etc.) without further reorganization.

No items were removed from the existing gate. The web-specific items
that used to be in the universal list are now categorized but still
fire on web projects.

## 2026-05-13

Updated `CLAUDE.md`, `install.sh`, `docs/CUSTOMIZE.md`, and `README.md`:

- Reframed lockfile drift detection (Dependency Installation Gate, section 6) as forensic rather than preventive. The drift check runs after `npm install` completes, by which point any malicious `postinstall` script has already executed. The original framing overstated what it prevents.
- Added section 7: `npm config set ignore-scripts true`. The install-time execution defense. Set by `install.sh` on all npm versions.
- Added section 8: `npm config set min-release-age 2d`. Forward protection for future supply chain attacks. Requires npm 11+; `install.sh` skips it gracefully on older npm.
- `docs/CUSTOMIZE.md` gained a section on tuning the release-age buffer, the script-allowance workflow for packages needing build steps (`sharp`, `esbuild`, `puppeteer`, `cypress`, `husky`, `node-gyp`, native modules), and equivalents for pnpm/yarn/bun.
- `README.md` surfaces both npm configs in the "What's in here" section.

## 2026-05-11

TanStack / Mini Shai-Hulud npm supply chain attack made public. 84 packages across the `@tanstack/` namespace shipped malicious versions, including `@tanstack/react-router` (12M+ weekly downloads). The campaign expanded over the following two days to OpenSearch, Mistral AI, Guardrails AI, UiPath, and Squawk — across both npm and PyPI.

The attack specifically targeted AI developer tooling, injecting persistence into `.claude/settings.json` and `.vscode/tasks.json`. `npm uninstall` did not remove the persistence.

This event exposed the install-time execution gap in the original protocol and triggered the 2026-05-13 update above.

## 2026-05-01

Companion article published on Substack: ["You Can Just Do Things." But Maybe, Be Safe About It?](https://atmr.substack.com/p/you-can-just-do-things-but-maybe)

Repo state at publication: five-layer baseline (Global `CLAUDE.md`, PreToolUse hook, global git pre-push hook, slash command references, Socket.dev). Lockfile drift detection was framed as preventive. No `ignore-scripts` or `min-release-age` configs in `install.sh`.
