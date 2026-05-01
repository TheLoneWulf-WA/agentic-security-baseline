# Install

## The fastest path: let your agent do it

Open this repo in Claude Code (or Cursor, Codex, or any agentic tool) and say:

> *"Follow `INSTALL.md` and install this baseline for me."*

The agent will read this file and execute the steps below adaptively — backing up existing files, merging instead of overwriting where possible, verifying each step. Most installs complete in under a minute.

## Manual install (or for agents to follow step-by-step)

These steps are written for both humans and agents. An agent should adapt to existing state (back up before overwriting, merge instead of replace where possible) rather than executing blindly.

### Prerequisites

Verify these are installed:

- `git`
- `bash` (or `zsh`)
- `jq` (for safe `settings.json` merging) — install via `brew install jq` on macOS, or your package manager on Linux

### Step 0 — Reconnaissance

Check existing state without modifying anything:

```bash
[ -f ~/.claude/CLAUDE.md ] && echo "CLAUDE.md EXISTS" || echo "CLAUDE.md FRESH"
[ -f ~/.claude/settings.json ] && echo "settings.json EXISTS" || echo "settings.json FRESH"
git config --global --get core.hooksPath || echo "core.hooksPath UNSET"
```

If any of these show `EXISTS` or a non-empty `core.hooksPath`, the install needs to back up and merge thoughtfully rather than overwrite.

### Step 1 — Place the protocol

Copy `CLAUDE.md` to `~/.claude/CLAUDE.md`. If a file already exists at that path, back it up first.

```bash
mkdir -p ~/.claude
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak.$(date +%Y%m%d-%H%M%S)
cp CLAUDE.md ~/.claude/CLAUDE.md
```

If the user has substantial existing content in their `~/.claude/CLAUDE.md`, an agent should ask before overwriting and offer to merge rather than replace.

### Step 2 — Install the PreToolUse hook script

```bash
mkdir -p ~/.claude/hooks
cp hooks/push-routing-gate.sh ~/.claude/hooks/push-routing-gate.sh
chmod +x ~/.claude/hooks/push-routing-gate.sh
```

### Step 3 — Wire the hook into settings.json

The snippet uses `__USER_HOME__` as a placeholder. Claude Code does **not** expand `~` or `$HOME` in hook command paths, so we substitute the literal absolute path before merging.

```bash
SNIPPET=$(mktemp)
sed "s|__USER_HOME__|$HOME|g" settings.snippet.json > "$SNIPPET"

if [ ! -f ~/.claude/settings.json ]; then
    cp "$SNIPPET" ~/.claude/settings.json
else
    cp ~/.claude/settings.json ~/.claude/settings.json.bak.$(date +%Y%m%d-%H%M%S)
    jq -s '.[0] * .[1]' ~/.claude/settings.json "$SNIPPET" > ~/.claude/settings.json.new
    mv ~/.claude/settings.json.new ~/.claude/settings.json
fi

rm "$SNIPPET"
```

The `jq -s '.[0] * .[1]'` pattern deep-merges the snippet into existing settings, preserving the user's other config (permissions, plugins, etc.).

### Step 4 — Install the global git pre-push hook

```bash
mkdir -p ~/.config/git/hooks
cp hooks/pre-push ~/.config/git/hooks/pre-push
chmod +x ~/.config/git/hooks/pre-push
```

### Step 5 — Configure git's hooks path

```bash
git config --global core.hooksPath ~/.config/git/hooks
```

If `core.hooksPath` is already set to something else, do **not** overwrite. Tell the user there's an existing config so they can decide. Overwriting could break a setup they rely on (e.g. a Husky path or a corporate hooks bundle).

### Step 6 — Install the slash commands (separately)

`/security-review` and `/code-review` are not bundled in this repo. Install them from Anthropic's official sources:

**`/security-review`:**

```bash
mkdir -p ~/.claude/commands
curl -o ~/.claude/commands/security-review.md \
  https://raw.githubusercontent.com/anthropics/claude-code-security-review/main/.claude/commands/security-review.md
```

**`/code-review`:**

This ships as part of the official `code-review` plugin. See the current install instructions at:
https://github.com/anthropics/claude-code/tree/main/plugins/code-review

Recent versions of Claude Code may bundle these by default. If `/code-review` and `/security-review` already work in your terminal, you can skip this step.

### Step 7 — Set up Socket.dev

Install the Socket.dev GitHub App on your repos:
https://socket.dev/features/github

The free tier covers solo and small-team use. Socket scans every PR for supply-chain threats — malicious packages, install scripts, network calls, obfuscated code — by analyzing what each package actually does, not by checking package names against a CVE database.

### Step 8 — Verify the install

Tell the user what should now be true:

- A new Claude Code session will load the protocol from `~/.claude/CLAUDE.md`
- Pushes to `main`, `master`, or `production` will prompt for confirmation (the PreToolUse hook)
- Direct terminal pushes to those branches will run `npm audit` and warn on sensitive file changes (the global git hook)
- PRs will be scanned by Socket.dev (once the GitHub App is installed)

### Step 9 — Customize for the user's stack

Direct the user to [`CUSTOMIZE.md`](CUSTOMIZE.md) to adapt the strict gate list, sensitive file patterns, branch naming, and protected branches for their projects.

## Uninstall

If you need to back out:

```bash
# Restore the previous CLAUDE.md (replace timestamp with your actual backup)
mv ~/.claude/CLAUDE.md.bak.<timestamp> ~/.claude/CLAUDE.md

# Remove the PreToolUse hook
rm ~/.claude/hooks/push-routing-gate.sh

# Restore the previous settings.json
mv ~/.claude/settings.json.bak.<timestamp> ~/.claude/settings.json

# Remove the global git hook
rm ~/.config/git/hooks/pre-push

# Unset the hooks path (or restore the previous one)
git config --global --unset core.hooksPath
```

## Troubleshooting

**The PreToolUse hook isn't firing.**

- Check that the hook is registered: `cat ~/.claude/settings.json | jq .hooks`
- Check that the path in the config is the literal absolute path (not `~` or `$HOME`)
- Check that the hook script is executable: `ls -la ~/.claude/hooks/push-routing-gate.sh`
- Restart your Claude Code session

**The global git hook isn't running on `git push`.**

- Check the config: `git config --global --get core.hooksPath`
- Check the script is executable: `ls -la ~/.config/git/hooks/pre-push`
- Try a manual run: `cat /dev/null | ~/.config/git/hooks/pre-push origin git@example.com:test/test.git`

**Claude Code doesn't seem to load the new CLAUDE.md.**

- Start a fresh session (`exit` then `claude` again). The protocol loads at session start.
- Check the file exists: `cat ~/.claude/CLAUDE.md | head -10`
