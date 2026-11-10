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

### Step 2 — Install the PreToolUse hook scripts

Both hooks: the push/merge gate (Bash commands) and the config-edit
gate (Edit/Write/NotebookEdit to the enforcement config itself).

```bash
mkdir -p ~/.claude/hooks
cp hooks/push-routing-gate.sh ~/.claude/hooks/push-routing-gate.sh
cp hooks/config-edit-gate.sh ~/.claude/hooks/config-edit-gate.sh
chmod +x ~/.claude/hooks/push-routing-gate.sh ~/.claude/hooks/config-edit-gate.sh
```

### Step 2b — Install the /until-clean skill

```bash
mkdir -p ~/.claude/skills/until-clean
cp skills/until-clean/SKILL.md ~/.claude/skills/until-clean/SKILL.md
```

### Step 2c — Install the /adversarial-review skill

```bash
mkdir -p ~/.claude/skills/adversarial-review
cp skills/adversarial-review/SKILL.md ~/.claude/skills/adversarial-review/SKILL.md
```

For these skills and for steps 2d and 2e: if a file is already there and differs from the repo's copy, back it up first (`cp <file> <file>.bak.$(date +%Y%m%d-%H%M%S)`). `install.sh` does this for you and leaves identical files alone.

### Step 2d — Install the review-risk script and its shared lists

`pr-risk.sh` decides each PR's review level from the files it changes; `/until-clean` and `/code-review` call it. It is a thin wrapper for `pr-risk.py`, which needs `python3` and an authenticated `gh`; if either is missing, every PR comes out sensitive. Why: [`review-cost-rationale.html`](review-cost-rationale.html).

```bash
mkdir -p ~/.claude/scripts ~/.claude/risk-paths
cp scripts/pr-risk.py scripts/pr-risk.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/pr-risk.py ~/.claude/scripts/pr-risk.sh
cp risk-paths/_default-safe.txt risk-paths/_default-paths.txt risk-paths/_default-names.txt risk-paths/_default-content.txt ~/.claude/risk-paths/
```

### Step 2e — Install the /code-review command

A modified copy of the official `code-review` plugin's command (Apache License 2.0, license file alongside): it re-reviews each new head commit, posts a "Reviewed at `<sha>`" summary, and sizes the review with `pr-risk.sh`. Its `allowed-tools` line names the script by absolute path, so substitute your home directory:

```bash
mkdir -p ~/.claude/commands
sed "s|__USER_HOME__|$HOME|g" commands/code-review.md > ~/.claude/commands/code-review.md
cp commands/LICENSE-code-review ~/.claude/commands/LICENSE-code-review
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
    # hooks.PreToolUse and permissions.allow/ask are concatenated explicitly —
    # jq's * replaces arrays, which would drop the hooks and rules you have.
    jq -s '((.[0].hooks.PreToolUse // []) + (.[1].hooks.PreToolUse // []) | unique) as $pt
           | ((.[0].permissions.allow // []) + (.[1].permissions.allow // []) | unique) as $al
           | ((.[0].permissions.ask // []) + (.[1].permissions.ask // []) | unique) as $as
           | (.[0] * .[1]) | .hooks.PreToolUse = $pt
           | .permissions.allow = $al | .permissions.ask = $as' \
        ~/.claude/settings.json "$SNIPPET" > ~/.claude/settings.json.new
    mv ~/.claude/settings.json.new ~/.claude/settings.json
fi

rm "$SNIPPET"
```

Sibling keys (plugins, etc.) deep-merge via `*`; `hooks.PreToolUse`, `permissions.allow` and `permissions.ask` are concatenated explicitly because `*` would replace each array and drop the hooks and rules you already have. Your `permissions.deny` is left untouched and still beats any allow entry. The snippet allows only `git push [-u] origin claude/<name>` and `gh pr create`, so Claude can push its own feature branch and open the PR without a prompt. Every other push still prompts: the push-routing hook asks on anything that is not that plain shape, when the repo's git config could redirect it (for example `push.default=upstream` on a branch tracking main), and on every merge. To keep prompting on all pushes, add `Bash(git push *)` to your `permissions.ask`. `unique` makes re-runs idempotent — note it sorts, so entry order may change (harmless: all matching PreToolUse hooks run).

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

### Step 6 — Install `/security-review` (separately)

`/security-review` is not bundled in this repo. Install it from Anthropic's official source:

```bash
mkdir -p ~/.claude/commands
curl -o ~/.claude/commands/security-review.md \
  https://raw.githubusercontent.com/anthropics/claude-code-security-review/main/.claude/commands/security-review.md
```

Recent versions of Claude Code may bundle it by default. If `/security-review` already works in your terminal, you can skip this step. (`/code-review` was installed in step 2e. The original is the official [`code-review` plugin](https://github.com/anthropics/claude-code/tree/main/plugins/code-review).)

### Step 7 — Set up Socket.dev

Install the Socket.dev GitHub App on your repos:
https://socket.dev/features/github

The free tier covers solo and small-team use. Socket scans every PR for supply-chain threats — malicious packages, install scripts, network calls, obfuscated code — by analyzing what each package actually does, not by checking package names against a CVE database.

### Step 8 — Verify the install

Tell the user what should now be true:

- A new Claude Code session will load the protocol from `~/.claude/CLAUDE.md`
- Claude can push its own branch with `git push [-u] origin claude/<name>` and open the PR with `gh pr create` without a prompt (the settings allow list)
- Every other push will prompt for confirmation: `main`, `master` or `production`, force, `--all`/`--mirror`, tags, deletes, other remotes, refspecs, a bare `git push`, and a push the repo's config could redirect (the PreToolUse hook)
- PR merges Claude runs (`gh pr merge` and the API routes) will pause on a confirmation prompt showing the review-loop marker state (ask mode)
- Agent edits to `~/.claude/` enforcement config (hooks, settings, CLAUDE.md, skills, commands) will prompt (the config-edit gate)
- `/until-clean`, `/adversarial-review` and `/code-review` will be available as slash commands in new sessions
- `~/.claude/scripts/pr-risk.sh <PR>` prints `RISK=` and `SIZE=` for a PR; a PR that changes anything other than docs, images, fonts or styles comes out sensitive until the project has its own safe list (`--suggest` drafts one)
- Direct terminal pushes to those branches will run `npm audit` and warn on sensitive file changes (the global git hook)
- PRs will be scanned by Socket.dev (once the GitHub App is installed)

### Step 9 — Customize for the user's stack

Direct the user to [`CUSTOMIZE.md`](CUSTOMIZE.md) to adapt the strict gate list, sensitive file patterns, branch naming, and protected branches for their projects, and to write each project's safe list (`~/.claude/scripts/pr-risk.sh --suggest`).

## Uninstall

If you need to back out:

```bash
# Restore the previous CLAUDE.md (replace timestamp with your actual backup)
mv ~/.claude/CLAUDE.md.bak.<timestamp> ~/.claude/CLAUDE.md

# Remove the PreToolUse hooks and the skills
rm ~/.claude/hooks/push-routing-gate.sh
rm ~/.claude/hooks/config-edit-gate.sh
rm -r ~/.claude/skills/until-clean
rm -r ~/.claude/skills/adversarial-review

# Remove the review-risk script, its lists and the /code-review command
rm ~/.claude/scripts/pr-risk.py ~/.claude/scripts/pr-risk.sh
rm ~/.claude/risk-paths/_default-safe.txt ~/.claude/risk-paths/_default-paths.txt ~/.claude/risk-paths/_default-names.txt ~/.claude/risk-paths/_default-content.txt
rm ~/.claude/commands/code-review.md ~/.claude/commands/LICENSE-code-review

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
