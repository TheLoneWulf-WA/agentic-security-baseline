# agentic-security-baseline

What I run for security and review when building with Claude Code. Free or already-paid-for tools. Sharing in case any of it is useful.

## What this is

This repo is the implementation of a small workflow protocol I put together for myself. It tries to catch the kinds of mistakes I was making with AI-assisted code — pushing to main without review, missing supply chain warnings, forgetting to run security checks — before they shipped.

I'm not a security professional. I'm fairly technical, I read a lot, I ship things across web and app dev. The system here is what someone slightly more careful than the average AI builder would do. It's not advanced. It's just deliberate.

The full reasoning is in the companion article: ["You Can Just Do Things." But Maybe, Be Safe About It?](https://atmr.substack.com/p/you-can-just-do-things-but-maybe). The post explains the architecture and the trade-offs. This repo is the files.

## What's in here

- **`CLAUDE.md`** — A workflow protocol that loads into every Claude Code session. Defines when to run `/security-review` and `/code-review`, how pushes get routed, how dependency installs are gated, and how PR merges happen.
- **`hooks/push-routing-gate.sh`** — A Claude Code PreToolUse hook. Fires on every `git push` Claude tries to run. If the push targets `main`, `master`, or `production`, it prompts for confirmation. Claude can't bypass it.
- **`hooks/pre-push`** — A global git pre-push hook (configured via `core.hooksPath`). Runs on every push from the terminal regardless of whether Claude is involved. Runs `npm audit --audit-level=critical` and warns on changes to sensitive files.
- **`settings.snippet.json`** — The Claude Code settings entry that wires the PreToolUse hook in.
- **`install.sh`** — A shell script that places the files, substitutes paths, and configures git. Idempotent.
- **`docs/INSTALL.md`** — Step-by-step install. Written so an agent can follow it, or you can.
- **`docs/CUSTOMIZE.md`** — What to adapt for your stack: payment processor names, sensitive file patterns, branch names, etc.

The system also relies on two things that aren't in this repo:

- `/security-review` and `/code-review` slash commands (Anthropic's, install separately — links in `docs/INSTALL.md`)
- Socket.dev's free tier on GitHub for supply chain scanning at the PR level

## Who this might help

I built this for myself, but it might fit if you're a solo builder, indie hacker, vibe coder, small-shop founder, or non-technical person shipping with AI — especially if:

- You're on a constrained budget where paid security tools are too expensive
- You're shipping payments, auth, or user data and want a baseline before you scale up
- You don't yet have a system for review and enforcement when building with Claude Code

If you have a security team, SOC2 compliance, and dedicated SAST infrastructure, you probably don't need this. You have something better.

## Install

Two ways:

**Let your agent do it.** Open this repo in Claude Code (or Cursor, Codex, etc.) and say *"Follow `docs/INSTALL.md` and install this for me."* The agent reads the steps, adapts to whatever you already have set up — backing up existing files, merging instead of replacing where it can.

**Or run the script.** `./install.sh` does the same thing deterministically. Same result, less back-and-forth.

`docs/INSTALL.md` has the full step-by-step if you want to see what's actually happening.

## Customize before relying on it

A few defaults need adapting for your stack: the strict gate's payment processor list, the regex of sensitive filenames in the git hook, your protected branches, your skip phrases. `docs/CUSTOMIZE.md` walks through what to change and where.

## A few things worth knowing

- This is what I have today. It'll change. If you adopt any of it, treat it the same way — test it, adjust it, push back on the parts that don't fit you.
- Review-until-clean burns tokens. On a noisy diff that's three or four review cycles before convergence. You'll feel it on your usage limit.
- The `CLAUDE.md` is a permanent context tax. It loads into every session. As it grows, it costs more. Try not to let it bloat without reason.
- I'm not the deepest expert on bash hooks or settings.json internals. I had Claude write the scripts, I read them, I tested them. They've held up. If something breaks at 2am, debugging it likely involves asking Claude again.
- Threat models differ. The defaults here reflect what I worry about. They might miss things you should worry about.

## A note on the slash commands

The two slash commands this protocol references aren't in the repo. They're Anthropic's:

- `/security-review` — from [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review)
- `/code-review` — from the official `code-review` plugin in [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/plugins/code-review)

Both are local slash commands. They're not the same as Anthropic's hosted Code Review service (a paid Team/Enterprise feature, billed at $15-25 per review).

## License

MIT. See [LICENSE](LICENSE).

---

The post is the architecture. This repo is the implementation. Take what's useful, leave what isn't.
