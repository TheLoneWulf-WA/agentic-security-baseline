#!/usr/bin/env bash
#
# Push Routing Gate — Claude Code PreToolUse hook
#
# Prompts for user confirmation when Claude attempts to push to
# protected branches (main/master/production).
#
# Enforces Push Routing protocol from ~/.claude/CLAUDE.md:
#   Default behavior: feature branch + PR
#   Override: user explicitly says "push to main"
#
# This is a programmatic enforcement layer — Claude cannot bypass it.
# Only the user can confirm the push via the prompt.
#
# Location: ~/.claude/hooks/push-routing-gate.sh

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# Not a git push? Allow immediately.
if ! echo "$command" | grep -qE '\bgit\s+push\b'; then
    exit 0
fi

# --- Check 1: Protected branch explicitly named in command ---
# Catches: git push origin main, git push -u origin master,
#          git push --force origin production, etc.
if echo "$command" | grep -qE '\s(main|master|production)\s*$'; then
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: "Push to protected branch detected. Push Routing protocol requires feature branch + PR by default. Only confirm if you explicitly said \"push to main\"."
        }
    }'
    exit 0
fi

# --- Check 2: Bare push while on a protected branch ---
# Catches: git push, git push origin (no branch = pushes current branch)
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    current_branch=$(cd "$cwd" && git branch --show-current 2>/dev/null || echo "")
    case "$current_branch" in
        main|master|production)
            jq -n --arg branch "$current_branch" '{
                hookSpecificOutput: {
                    hookEventName: "PreToolUse",
                    permissionDecision: "ask",
                    permissionDecisionReason: ("Currently on protected branch " + $branch + ". Push Routing requires feature branch + PR. Only confirm if you explicitly requested pushing to this branch.")
                }
            }'
            exit 0
            ;;
    esac
fi

# Feature branch or non-protected target — allow silently
exit 0
