#!/usr/bin/env bash
#
# Config Edit Gate — Claude Code PreToolUse hook (Edit|Write|NotebookEdit)
#
# The guard guarding the guard: any Edit/Write targeting the enforcement
# config itself (~/.claude/hooks/*, settings.json, settings.local.json,
# keybindings.json) prompts for user confirmation instead of applying
# silently. Complements the shell-write check in push-routing-gate.sh.
#
# Location: ~/.claude/hooks/config-edit-gate.sh

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""')

# Resolve symlinks/relative paths so a link into ~/.claude can't sidestep
# the match. No -m flag: macOS ships BSD realpath, which lacks it — for a
# not-yet-existing target (a Write creating a new file), resolve the
# parent directory and re-attach the basename. Raw path as last resort.
if command -v realpath >/dev/null 2>&1 && [ -n "$file_path" ]; then
    if resolved=$(realpath "$file_path" 2>/dev/null); then
        file_path="$resolved"
    elif resolved=$(realpath "$(dirname "$file_path")" 2>/dev/null); then
        file_path="$resolved/$(basename "$file_path")"
    fi
fi

case "$file_path" in
    "$HOME"/.claude/hooks/*|"$HOME"/.claude/settings.json|"$HOME"/.claude/settings.local.json|"$HOME"/.claude/keybindings.json)
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
