#!/usr/bin/env bash
#
# agentic-security-baseline installer
#
# Run from the cloned repo directory:
#   ./install.sh
#
# This script:
#   - Backs up any existing ~/.claude/CLAUDE.md and ~/.claude/settings.json
#   - Copies the protocol, hook scripts, skills, the /code-review command,
#     the review-risk script and its lists, and settings into place
#   - Substitutes the user's $HOME into the settings.json snippet
#     (Claude Code does not expand ~ or $HOME in hook command paths)
#   - Configures git's core.hooksPath if not already set
#
# Idempotent: safe to re-run. Existing files are backed up with a timestamp
# before being overwritten (skills, commands and the risk files only when
# they differ from the repo's copy).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "agentic-security-baseline installer"
echo "==================================="
echo

# ---- Pre-flight ----

if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is not installed" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required (used to safely merge settings.json)" >&2
    echo "Install it with:" >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Linux:  apt-get install jq  (or your distro's equivalent)" >&2
    exit 1
fi

# ---- Step 1: Place CLAUDE.md ----

mkdir -p "$HOME/.claude"

if [ -f "$HOME/.claude/CLAUDE.md" ]; then
    backup="$HOME/.claude/CLAUDE.md.bak.$TIMESTAMP"
    cp "$HOME/.claude/CLAUDE.md" "$backup"
    echo "✓ Backed up existing CLAUDE.md to $backup"
fi

cp "$REPO_DIR/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
echo "✓ Installed protocol to ~/.claude/CLAUDE.md"

# ---- Step 2: Install PreToolUse hook scripts ----

mkdir -p "$HOME/.claude/hooks"
cp "$REPO_DIR/hooks/push-routing-gate.sh" "$HOME/.claude/hooks/push-routing-gate.sh"
cp "$REPO_DIR/hooks/config-edit-gate.sh" "$HOME/.claude/hooks/config-edit-gate.sh"
chmod +x "$HOME/.claude/hooks/push-routing-gate.sh" "$HOME/.claude/hooks/config-edit-gate.sh"
echo "✓ Installed PreToolUse hooks to ~/.claude/hooks/ (push-routing-gate, config-edit-gate)"

# install_file SRC DEST [MODE]: copy SRC to DEST. An identical DEST is left
# alone (re-runs change nothing); a DEST that differs, for example one you
# customized, is backed up with a timestamp first. Used for the skills, the
# /code-review command, the risk script and its lists.
install_file() {
    local src="$1" dest="$2" mode="${3:-}"
    local short="~${dest#"$HOME"}"
    mkdir -p "$(dirname "$dest")"
    if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
        echo "✓ Up to date: $short"
    else
        if [ -f "$dest" ]; then
            cp "$dest" "$dest.bak.$TIMESTAMP"
            echo "✓ Backed up existing $short to $short.bak.$TIMESTAMP"
        fi
        cp "$src" "$dest"
        echo "✓ Installed $short"
    fi
    if [ -n "$mode" ]; then chmod "$mode" "$dest"; fi
}

# ---- Step 2b: Install the /until-clean skill ----

install_file "$REPO_DIR/skills/until-clean/SKILL.md" "$HOME/.claude/skills/until-clean/SKILL.md"

# ---- Step 2c: Install the /adversarial-review skill ----

install_file "$REPO_DIR/skills/adversarial-review/SKILL.md" "$HOME/.claude/skills/adversarial-review/SKILL.md"

# ---- Step 2d: Install the review-risk script and its shared lists ----
# pr-risk.sh (a wrapper for pr-risk.py, which needs python3 and gh)
# decides a PR's review level from the files it changes, so the loop and
# /code-review never size a review by judgment. A PR is normal only when
# every file is on a safe list and no risky list fires. The shared
# _default-*.txt lists cover web, Android, iOS and Expo; each project adds
# its own .claude/safe-paths.txt (pr-risk.sh --suggest drafts one). See
# docs/review-cost-rationale.html.

install_file "$REPO_DIR/scripts/pr-risk.py" "$HOME/.claude/scripts/pr-risk.py" +x
install_file "$REPO_DIR/scripts/pr-risk.sh" "$HOME/.claude/scripts/pr-risk.sh" +x
for list in _default-safe.txt _default-paths.txt _default-names.txt _default-content.txt; do
    install_file "$REPO_DIR/risk-paths/$list" "$HOME/.claude/risk-paths/$list"
done

# ---- Step 2e: Install the /code-review command ----
# A modified copy of the official plugin's command (Apache 2.0; license
# installed beside it). Its allowed-tools line names the risk script by
# absolute path, so __USER_HOME__ is replaced with $HOME, as in step 3.

TMP_CR=$(mktemp)
sed "s|__USER_HOME__|$HOME|g" "$REPO_DIR/commands/code-review.md" > "$TMP_CR"
install_file "$TMP_CR" "$HOME/.claude/commands/code-review.md"
rm -f "$TMP_CR"
install_file "$REPO_DIR/commands/LICENSE-code-review" "$HOME/.claude/commands/LICENSE-code-review"

# ---- Step 3: Wire hook into settings.json ----

SETTINGS="$HOME/.claude/settings.json"
SNIPPET="$REPO_DIR/settings.snippet.json"
TMP_SNIPPET=$(mktemp)
trap "rm -f $TMP_SNIPPET" EXIT

# Substitute __USER_HOME__ placeholder with $HOME
sed "s|__USER_HOME__|$HOME|g" "$SNIPPET" > "$TMP_SNIPPET"

if [ ! -f "$SETTINGS" ]; then
    cp "$TMP_SNIPPET" "$SETTINGS"
    echo "✓ Created ~/.claude/settings.json with hook config"
else
    backup="$SETTINGS.bak.$TIMESTAMP"
    cp "$SETTINGS" "$backup"
    # Deep-merge for sibling keys; hooks.PreToolUse and permissions.allow /
    # permissions.ask need explicit array concatenation because jq's *
    # replaces arrays wholesale — a plain merge would silently drop the
    # user's own PreToolUse hooks and permission rules. Any deny rule the
    # user has is kept as-is and still wins over these allow entries.
    # The snippet's allow entries let Claude push a claude/* branch to
    # origin and open a PR without a prompt; the push-routing hook still
    # asks on every other push and on every merge.
    # `unique` keeps the merge idempotent on re-runs; it sorts, so entry
    # order may change (harmless: all matching PreToolUse hooks run).
    jq -s '((.[0].hooks.PreToolUse // []) + (.[1].hooks.PreToolUse // []) | unique) as $pt
           | ((.[0].permissions.allow // []) + (.[1].permissions.allow // []) | unique) as $al
           | ((.[0].permissions.ask // []) + (.[1].permissions.ask // []) | unique) as $as
           | (.[0] * .[1]) | .hooks.PreToolUse = $pt
           | .permissions.allow = $al | .permissions.ask = $as' \
        "$SETTINGS" "$TMP_SNIPPET" > "$SETTINGS.new"
    mv "$SETTINGS.new" "$SETTINGS"
    echo "✓ Merged hook and permission config into ~/.claude/settings.json"
    echo "  Claude may now push its own claude/* branch to origin and open a PR"
    echo "  without a prompt. To keep prompting, add Bash(git push *) to"
    echo "  permissions.ask; an ask or deny rule wins over these allow entries."
    echo "  (previous version backed up to $backup)"
fi

# ---- Step 4: Install global git pre-push hook ----

mkdir -p "$HOME/.config/git/hooks"
cp "$REPO_DIR/hooks/pre-push" "$HOME/.config/git/hooks/pre-push"
chmod +x "$HOME/.config/git/hooks/pre-push"
echo "✓ Installed global git pre-push hook"

# ---- Step 5: Configure core.hooksPath ----

EXISTING_HOOKSPATH=$(git config --global --get core.hooksPath 2>/dev/null || echo "")

if [ -z "$EXISTING_HOOKSPATH" ]; then
    git config --global core.hooksPath "$HOME/.config/git/hooks"
    echo "✓ Set git core.hooksPath to ~/.config/git/hooks"
elif [ "$EXISTING_HOOKSPATH" = "$HOME/.config/git/hooks" ]; then
    echo "✓ git core.hooksPath already set correctly"
else
    echo "⚠ WARNING: core.hooksPath is already set to: $EXISTING_HOOKSPATH"
    echo "  Skipping git config update to avoid breaking your existing setup."
    echo "  To use this baseline's hook instead, run:"
    echo "    git config --global core.hooksPath \"\$HOME/.config/git/hooks\""
fi

# ---- Step 6: Configure npm for supply chain protection ----

if command -v npm >/dev/null 2>&1; then
    # ignore-scripts blocks preinstall/postinstall/prepare script execution.
    # This is the primary defense against install-time payload execution
    # used in the Axios, TanStack, and Mini Shai-Hulud campaigns.
    # Works on all npm versions.
    npm config set ignore-scripts true
    echo "✓ Set npm ignore-scripts=true (blocks install-time script execution)"
    echo "  Note: packages needing build scripts (sharp, esbuild, husky, etc.)"
    echo "  may require --ignore-scripts=false per-install. See docs/CUSTOMIZE.md"

    # min-release-age blocks installs of versions less than 2 days old.
    # Requires npm 11+; we detect and skip gracefully on older versions.
    NPM_VERSION=$(npm --version)
    NPM_MAJOR=$(echo "$NPM_VERSION" | cut -d. -f1)
    if [ "$NPM_MAJOR" -ge 11 ]; then
        npm config set min-release-age 2
        echo "✓ Set npm min-release-age=2 (skips early-installer window)"
    else
        echo "⚠ Skipped min-release-age — requires npm 11+ (you have npm $NPM_VERSION)"
        echo "  When you upgrade npm, run: npm config set min-release-age 2"
        echo "  Until then, ignore-scripts above provides most of the protection."
    fi
else
    echo "⚠ npm not found — skipping npm config setup"
fi

# ---- Done ----

echo
echo "Installation complete."
echo
echo "Next steps:"
echo
echo "  1. Install /security-review:"
echo "     mkdir -p ~/.claude/commands"
echo "     curl -o ~/.claude/commands/security-review.md \\"
echo "       https://raw.githubusercontent.com/anthropics/claude-code-security-review/main/.claude/commands/security-review.md"
echo
echo "  2. Set up Socket.dev on your GitHub repos:"
echo "     https://socket.dev/features/github"
echo
echo "  3. Customize the protocol for your stack:"
echo "     See docs/CUSTOMIZE.md"
echo
echo "  4. In each project, draft its own safe list (until it has one, only"
echo "     docs-and-images PRs get the cheaper review):"
echo "     ~/.claude/scripts/pr-risk.sh --suggest"
echo
echo "  5. Start a fresh Claude Code session to load the new protocol."
echo
