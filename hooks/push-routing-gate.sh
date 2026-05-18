#!/usr/bin/env bash
#
# Push Routing Gate — Claude Code PreToolUse hook
#
# Prompts for user confirmation when Claude attempts to:
#   1. Push to protected branches (main/master/production)
#   2. Run `gh pr merge` without an explicit bypass
#
# Enforces two protocols from ~/.claude/CLAUDE.md:
#   - Push Routing: default = feature branch + PR; override = user says "push to main"
#   - PR Merge Follow-up: default = stop and wait for user; override = user says
#     "ship it through" (bypass phrase), which Claude translates into
#     MERGE_GATE_BYPASS=1 prefixing the command.
#
# This is a programmatic enforcement layer — Claude cannot bypass it without
# the env-var prefix, and the env-var prefix is gated by a specific user phrase.
#
# Location: ~/.claude/hooks/push-routing-gate.sh

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# --- gh pr merge gate ---
# Catches: gh pr merge, gh pr merge <n>, gh pr merge --squash, etc.
# Bypassed by: MERGE_GATE_BYPASS=1 gh pr merge ...
# Claude adds the env-var prefix only when the user has said the bypass phrase
# ("ship it through") for the current merge. Plain "ship it" / "merge it" does
# NOT add the prefix and so still triggers the prompt below.
if echo "$command" | grep -qE '\bgh\s+pr\s+merge\b'; then
    if echo "$command" | grep -qE '\bMERGE_GATE_BYPASS=1\b'; then
        # Explicit bypass present — allow silently.
        exit 0
    fi
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: "gh pr merge detected. PR Merge Follow-up protocol requires user confirmation. Only confirm if you explicitly approved this merge (\"ship it\" / \"merge it\"). To skip this prompt next time, use the bypass phrase \"ship it through\"."
        }
    }'
    exit 0
fi

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
