#!/usr/bin/env bash
#
# agentic-security-baseline installer
#
# Run from the cloned repo directory:
#   ./install.sh
#
# This script:
#   - Backs up any existing ~/.claude/CLAUDE.md and ~/.claude/settings.json
#   - Copies the protocol, hook scripts, and settings into place
#   - Substitutes the user's $HOME into the settings.json snippet
#     (Claude Code does not expand ~ or $HOME in hook command paths)
#   - Configures git's core.hooksPath if not already set
#
# Idempotent: safe to re-run. Existing files are backed up with a timestamp
# before being overwritten.

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

# ---- Step 2: Install PreToolUse hook script ----

mkdir -p "$HOME/.claude/hooks"
cp "$REPO_DIR/hooks/push-routing-gate.sh" "$HOME/.claude/hooks/push-routing-gate.sh"
chmod +x "$HOME/.claude/hooks/push-routing-gate.sh"
echo "✓ Installed PreToolUse hook to ~/.claude/hooks/push-routing-gate.sh"

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
    # Deep-merge: existing settings + snippet's hooks
    jq -s '.[0] * .[1]' "$SETTINGS" "$TMP_SNIPPET" > "$SETTINGS.new"
    mv "$SETTINGS.new" "$SETTINGS"
    echo "✓ Merged hook config into ~/.claude/settings.json"
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
        npm config set min-release-age 2d
        echo "✓ Set npm min-release-age=2d (skips early-installer window)"
    else
        echo "⚠ Skipped min-release-age — requires npm 11+ (you have npm $NPM_VERSION)"
        echo "  When you upgrade npm, run: npm config set min-release-age 2d"
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
echo "  2. Install /code-review (see https://github.com/anthropics/claude-code/tree/main/plugins/code-review)"
echo
echo "  3. Set up Socket.dev on your GitHub repos:"
echo "     https://socket.dev/features/github"
echo
echo "  4. Customize the protocol for your stack:"
echo "     See docs/CUSTOMIZE.md"
echo
echo "  5. Start a fresh Claude Code session to load the new protocol."
echo
