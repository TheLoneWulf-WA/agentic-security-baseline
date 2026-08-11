#!/usr/bin/env bash
#
# Config Edit Gate — Claude Code PreToolUse hook (Edit|Write)
#
# The guard guarding the guard: any Edit/Write targeting the enforcement
# config itself (~/.claude/hooks/*, settings.json, settings.local.json,
# keybindings.json) prompts for user confirmation instead of applying
# silently. Complements the shell-write check in push-routing-gate.sh.
#
# Location: ~/.claude/hooks/config-edit-gate.sh

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')

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
