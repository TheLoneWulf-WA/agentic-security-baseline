# agentic-security-baseline

What I run for security and review when building with Claude Code. Free or already-paid-for tools. Sharing in case any of it is useful.

## What this is

This repo is the implementation of a small workflow protocol I put together for myself. It tries to catch the kinds of mistakes I was making with AI-assisted code — pushing to main without review, missing supply chain warnings, forgetting to run security checks — before they shipped.

I'm not a security professional. I'm fairly technical, I read a lot, I ship things across web and app dev. The system here is what someone slightly more careful than the average AI builder would do. It's not advanced. It's just deliberate.

The full reasoning is in two companion articles: ["You Can Just Do Things." But Maybe, Be Safe About It?](https://atmr.substack.com/p/you-can-just-do-things-but-maybe) (the original) and [It Is "Next Time" Already](https://atmr.substack.com/p/it-is-next-time-already) (the update, after the TanStack supply-chain attack forced changes). The posts explain the architecture and the trade-offs. This repo is the files.

## What's in here

- **`CLAUDE.md`** — A workflow protocol that loads into every Claude Code session. Defines when to run `/security-review` and `/code-review`, how pushes get routed, how dependency installs are gated, and how PR merges happen. Lean by design — see `docs/protocol-rationale.html` for the why behind each rule.
- **`hooks/push-routing-gate.sh`** — A Claude Code PreToolUse hook. Fires on every `git push` Claude tries to run. If the push targets `main`, `master`, or `production`, it prompts for confirmation. Claude can't bypass it.
- **`hooks/pre-push`** — A global git pre-push hook (configured via `core.hooksPath`). Runs on every push from the terminal regardless of whether Claude is involved. Runs `npm audit --audit-level=critical` and warns on changes to sensitive files.
- **`settings.snippet.json`** — The Claude Code settings entry that wires the PreToolUse hook in.
- **`install.sh`** — A shell script that places the files, substitutes paths, configures git, and sets npm config for supply chain protection (`ignore-scripts`, `min-release-age` when supported). Idempotent.
- **`docs/INSTALL.md`** — Step-by-step install. Written so an agent can follow it, or you can.
- **`docs/CUSTOMIZE.md`** — What to adapt for your stack: payment processor names, sensitive file patterns, branch names, etc.
- **`tools/audit.sh`** — A read-only check for the Mini Shai-Hulud / TanStack-class worm: persistence daemon, tampered `.claude`/`.vscode` configs, affected packages in lockfiles, and npm defense status.
- **`docs/protocol-rationale.html`** — Why each rule in `CLAUDE.md` exists, with diagrams (authority hierarchy, defense stack, review loop, push routing, merge-gate mechanic, dep-gate layers). Self-contained HTML, no build step. Open locally in a browser. The companion to `CLAUDE.md` — operating manual vs. reference.

The install also configures `~/.npmrc` on your machine with two supply-chain protections:

- **`ignore-scripts=true`** — blocks `preinstall`/`postinstall`/`prepare` script execution, the vector used in the Axios, TanStack, and Mini Shai-Hulud supply chain attacks. Compromised packages can't auto-run their payload on install.
- **`min-release-age=2d`** (npm 11+) — skips the early-installer window for *future* supply chain attacks by refusing to install package versions less than 2 days old. Most malicious uploads are detected by Socket and the security community within 6-24 hours; the 2-day buffer means you skip the exposure window by default.

See `docs/CUSTOMIZE.md` for tuning, equivalents for pnpm/yarn/bun, and per-package overrides when you need them.

The system also relies on three things that aren't in this repo:

- `security-guidance@claude-plugins-official` plugin (Anthropic's) — continuous in-session checks via hooks. This is "Layer 0" in `CLAUDE.md`. Install with `/plugin install security-guidance@claude-plugins-official` inside Claude Code. Canonical docs: <https://code.claude.com/docs/en/security-guidance>.
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

## Check a machine for compromise

If you've installed npm packages recently and want to know whether the Mini Shai-Hulud / TanStack-class worm got you:

```bash
bash tools/audit.sh            # scans your home directory
bash tools/audit.sh ~/code     # or point it at a specific folder
```

It's **read-only** — it inspects and reports, never modifies, deletes, or revokes anything. It checks for the persistence daemon, dropped scripts, tampered `.claude/settings.json` and `.vscode/tasks.json`, affected packages in your lockfiles, and whether your npm install-time defenses are on.

**If it finds the persistence daemon, do not revoke your GitHub tokens first.** The malware watches for revocation and runs `rm -rf ~/` when it sees it. Remove the daemon, then rotate. The script prints this warning inline.

The known-package list is point-in-time; [Socket's writeup](https://socket.dev/blog/tanstack-npm-packages-compromised-mini-shai-hulud-supply-chain-attack) has the authoritative current list.

## Customize before relying on it

A few defaults need adapting for your stack: the strict gate's payment processor list, the regex of sensitive filenames in the git hook, your protected branches, your skip phrases. `docs/CUSTOMIZE.md` walks through what to change and where.

## A few things worth knowing

- This is what I have today. It'll change. If you adopt any of it, treat it the same way — test it, adjust it, push back on the parts that don't fit you.
- Review-until-clean burns tokens. On a noisy diff that's three or four review cycles before convergence. You'll feel it on your usage limit.
- The `CLAUDE.md` is a permanent context tax. It loads into every session. As it grows, it costs more. Try not to let it bloat without reason.
- I'm not the deepest expert on bash hooks or settings.json internals. I had Claude write the scripts, I read them, I tested them. They've held up. If something breaks at 2am, debugging it likely involves asking Claude again.
- Threat models differ. The defaults here reflect what I worry about. They might miss things you should worry about.

## A note on Anthropic's security tools (and one related tool)

This protocol relies on three Anthropic-shipped pieces. All install through Claude Code; none requires a paid plan.

- **`security-guidance` plugin** — continuous, hook-based, in-session. Pattern-matches every `Edit`/`Write` and runs fresh-context security reviews at end-of-turn and on-commit. Install: `/plugin install security-guidance@claude-plugins-official`. Docs: <https://code.claude.com/docs/en/security-guidance>. In `CLAUDE.md` this is **Layer 0** — runs out-of-band and is *not* a replacement for the slash commands below.
- **`/security-review`** — on-demand security pass on the current branch, run when you ask. From [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review).
- **`/code-review`** — on-demand correctness + style pass that posts findings as PR comments. From the official `code-review` plugin in [anthropics/claude-code](https://github.com/anthropics/claude-code/tree/main/plugins/code-review).

The slash commands aren't the same as Anthropic's hosted Code Review service (a paid Team/Enterprise feature, billed at $15-25 per review).

The three layer rather than overlap: the plugin catches the cheap, high-frequency stuff while you're writing; the slash commands run on demand at push or PR time and dig deeper.

### Also worth knowing about: DeepSec

The slash commands above run on a *diff* — your branch's pending changes or a PR. They're per-event tools. [DeepSec](https://vercel.com/blog/introducing-deepsec-find-and-fix-vulnerabilities-in-your-code-base) (Vercel, open source) is a complementary tool for *whole-codebase* audits — useful when you're doing a pre-launch sweep, a quarterly audit, or inheriting a codebase you didn't build per-commit yourself.

It's BYOK (uses your existing Claude or OpenAI API keys, no new subscription) and runs locally via `npx deepsec init`. Fits the same budget thesis as the rest of this baseline. Not a replacement for the per-event review commands — a different layer entirely, for a different question (*"what's already in here?"* rather than *"should this change happen?"*).

Worth knowing about for when you need it.

## License

MIT. See [LICENSE](LICENSE).

---

The post is the architecture. This repo is the implementation. Take what's useful, leave what isn't.
