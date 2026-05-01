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

Push Routing creates feature branches with the prefix `claude/<short-slug>`. If you prefer `feat/<slug>` or your team's own convention, edit the **Branch naming** section.

## 4. The protected branches list (`~/.claude/hooks/push-routing-gate.sh`)

The PreToolUse hook treats `main`, `master`, and `production` as protected. If you have other protected branches (`release`, `staging`, `prod-au`, etc.), add them to the case statements near the top of the script.

There are two case statements to update — one for explicit branch names in the push command, one for the current-branch check.

## 5. Skip clauses (`~/.claude/CLAUDE.md`)

If the default skip phrases ("skip review", "just push", "no review needed") don't match how *you* talk, change them in the **Skip Clauses** section to match your actual phrasing. The phrases need to be unambiguous so Claude Code recognizes the override.

## 6. Reports directory (`~/.claude/CLAUDE.md`)

Reports save to `~/.claude/reports/<project-name>/...` by default. Change the path in the **Review Output Format** section if you want them somewhere else (e.g. inside each project, or under your Documents folder).

## 7. The merge default (`~/.claude/CLAUDE.md`)

The default merge strategy is `squash + delete branch`. If your team prefers rebase or merge commits, change it in the **PR Merge Follow-up** section.

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
