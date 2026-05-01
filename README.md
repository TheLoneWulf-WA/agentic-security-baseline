# agentic-security-baseline

> Defense-in-depth security and review workflow for Claude Code, built from free and already-paid-for tools. No enterprise budget required.

> **Instructions are best-effort. Hooks are guaranteed. External scanners are deterministic. Each rule lives where it can actually be enforced.**

## What's in here

Five layers of defense. Each one enables the next.

**1. Global `CLAUDE.md`** — Policy file loaded into every Claude Code session, every project, automatically. Defines when to run security review, when to run code review, how to route pushes, how to gate dependency installs, how to handle PR merges.

**2. PreToolUse hook** — Fires every time Claude tries to run `git push`. If the push targets `main`, `master`, or `production`, the hook intercepts and prompts you to confirm. Claude cannot bypass this. It's a script that runs every time, on every agent, in every session.

**3. Global git hook** — A bash script wired in via `core.hooksPath` that runs on every push from your terminal regardless of whether Claude is involved. Blocks pushes with critical npm vulnerabilities. Warns on changes to sensitive files.

**4. Review commands** — `/security-review` runs before pushes that touch sensitive surfaces (payments, auth, secrets, RLS, CORS, middleware, OAuth callbacks, third-party scripts). `/code-review --comment` runs on every PR before merge. These are Anthropic's slash commands; install instructions linked below.

**5. [Socket.dev](https://socket.dev/features/github) on GitHub** — A GitHub App that scans every PR for supply chain threats. Not by checking package names against a CVE database — by analyzing what each package actually does. Free tier sufficient for solo and small-team use.

The Socket layer matters because of how it connects to push routing: because the policy forces every change through a feature branch and a PR by default, every change automatically goes through Socket. The PR-by-default rule isn't just about review — it's what feeds Socket its input.

## Who this is for

> *If you're reading this from a country where enterprise tooling isn't a casual line item, or you're an indie hacker watching every dollar, the system this implements is built for you. Not because it's a downgrade. Because the constraint produced a cleaner design than money would have.*

Indie hackers, solo devs, and small teams shipping real software with AI. Especially:

- Anyone whose budget can't accommodate Snyk Pro, Greptile, Veracode, SonarQube Cloud
- Anyone shipping payments, auth, or user data on a constrained budget
- Anyone who's been pasting security audit prompts into chat windows and wants a system instead

If you're at an enterprise with a security team, SOC2 compliance, and dedicated SAST infrastructure — you don't need this. You have something better.

## Install

**Recommended (let your agent do it):** Open this repo in Claude Code (or Cursor, Codex, or any agentic tool) and say:

> *"Follow `docs/INSTALL.md` and install this baseline for me."*

The agent will read the instructions, adapt to your existing setup (back up before overwriting, merge instead of replacing where possible), and verify each step.

**Manual / scripted:** Run `./install.sh` for a deterministic shell-based install. Or follow [`docs/INSTALL.md`](docs/INSTALL.md) yourself.

## Customize

The protocol ships with sensible defaults but parts of it (sensitive surfaces, payment processor names, sensitive file patterns) need adapting to *your* stack. See [`docs/CUSTOMIZE.md`](docs/CUSTOMIZE.md).

## Slash commands (install separately)

This baseline assumes two Anthropic-built slash commands are present in `~/.claude/commands/`:

- **`/security-review`** — branch-level security audit, from [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review)
- **`/code-review`** — multi-agent PR review pipeline, shipped as part of the official `code-review` plugin in [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/plugins/code-review)

Both are *local* slash commands. They are **not** the same as Anthropic's hosted Code Review service (which is a paid Team/Enterprise feature billed at $15-25 per review). The free local versions are what this baseline uses.

## Three moves to start

If you're not ready to install everything, do these three things first:

1. **Start with what scares you.** Pick the one thing that, if it broke, would be worst. That's where the first gate goes.
2. **Build the hook before the instruction.** The instruction layer is convenient and probabilistic. The hook layer is mechanical and guaranteed. If you only do one, do the hook.
3. **Commit small.** Cheapest change with the biggest review-quality return. No tooling required. With AI in the review loop, small atomic commits are no longer just hygiene — they're a defensive strategy. The AI's attention budget is the binding constraint.

That's enough to be safer than 90% of people shipping AI-assisted code right now.

## Honest disclaimer

- This is what I run today. It'll change. Adopt it the same way.
- Token consumption is real — review-until-clean burns into your usage limit. You'll feel it.
- The Global `CLAUDE.md` is a permanent context tax. It gets injected into every session. Don't let it bloat without reason.
- I'm not a security expert. This is what someone slightly more careful than the average AI builder would do. It's not advanced. It's deliberate.
- Threat models differ. Adapt for your stack. Security is your responsibility once you fork.
- The system is understood enough by me to maintain — but not line-by-line. If something breaks, debugging it likely involves asking Claude.

## Why this exists

The full reasoning behind every layer — why the architecture is shaped this way, what was deliberately left out, the trade-offs you should know about, what's still being figured out — is in the companion article: *[link to companion article — coming soon]*.

The post is the architecture. This repo is the implementation. Take what's useful, leave what isn't.

## License

MIT. See [LICENSE](LICENSE).
