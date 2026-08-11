#!/usr/bin/env bash
#
# Config Edit Gate — Claude Code PreToolUse hook (Edit|Write|NotebookEdit)
#
# The guard guarding the guard: any Edit/Write targeting the enforcement
# config itself — hooks, settings, keybindings, the protocol rulebook
# (~/.claude/CLAUDE.md), and the skills/commands that are load-bearing
# for the loop — prompts for user confirmation instead of applying
# silently. Complements the shell-write check in push-routing-gate.sh
# (which is wider: it also catches project-level .claude/settings.json).
#
# Location: ~/.claude/hooks/config-edit-gate.sh

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')

# Resolve symlinks/relative paths so a link into ~/.claude can't sidestep
# the match. No -m flag: macOS ships BSD realpath, which lacks it — for a
# not-yet-existing target (a Write creating a new file), resolve the
# parent directory and re-attach the basename. Raw path as last resort.
# $HOME is resolved too, so a symlinked home component can't cause a
# resolved-path / unresolved-pattern mismatch.
if command -v realpath >/dev/null 2>&1 && [ -n "$file_path" ]; then
    if resolved=$(realpath "$file_path" 2>/dev/null); then
        file_path="$resolved"
    elif resolved=$(realpath "$(dirname "$file_path")" 2>/dev/null); then
        file_path="$resolved/$(basename "$file_path")"
    fi
    HOME_R=$(realpath "$HOME" 2>/dev/null || echo "$HOME")
else
    HOME_R="$HOME"
fi
HOME_R="${HOME_R:-$HOME}"

case "$file_path" in
    "$HOME_R"/.claude/hooks/*|"$HOME_R"/.claude/skills/*|"$HOME_R"/.claude/commands/*|"$HOME_R"/.claude/CLAUDE.md|"$HOME_R"/.claude/settings.json|"$HOME_R"/.claude/settings.local.json|"$HOME_R"/.claude/keybindings.json)
        jq -n '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "ask",
                permissionDecisionReason: "This edit targets Claude Code enforcement config (~/.claude/hooks or settings). Confirm only if you explicitly requested this change."
            }
        }'
        ;;
esac
exit 0
