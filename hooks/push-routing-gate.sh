#!/usr/bin/env bash
#
# Push Routing Gate — Claude Code PreToolUse hook
#
# Prompts for user confirmation when Claude attempts to:
#   1. Push to protected branches (main/master/production)
#   2. Merge a PR by any route (gh pr merge, gh api, curl/wget to the API) —
#      "ask mode": the command pauses on an in-session confirmation prompt;
#      one user keypress approves or rejects it.
#   3. Write to enforcement config (~/.claude/hooks, settings.json) via shell.
#
# Enforces protocols from ~/.claude/CLAUDE.md:
#   - Push Routing: default = feature branch + PR; override = user says "push to main"
#   - PR Merge Follow-up (ask mode, 2026-08-10): Claude runs the merge only
#     after the user says "merge it" / "ship it"; this gate then requires a
#     live user keypress. The literal phrase "ship it through" skips the
#     prompt via a MERGE_GATE_BYPASS=1 prefix; every bypass is audit-logged.
#   (To restore deny mode — user merges in the GitHub UI, Claude locked out —
#    change the merge case's permissionDecision from "ask" to "deny".)
#
# This is a programmatic enforcement layer — Claude cannot bypass it without
# the env-var prefix, the prefix is gated by a specific user phrase, and every
# use of the prefix leaves a line in ~/.claude/logs/merge-bypass.log.
#
# Location: ~/.claude/hooks/push-routing-gate.sh

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$input" | jq -r '.cwd // ""')

# --- Merge gate: Claude does not merge PRs ---
# Catches: gh pr merge; gh api .../pulls/<n>/merge; curl/wget to the merge API.
if echo "$command" | grep -qiE '\bgh\s+pr\s+merge\b|\bgh\s+api\b[^|;]*pulls/[^ ]*/merge|\b(curl|wget)\b[^|;]*api\.github\.com[^ ]*pulls[^ ]*merge'; then
    if echo "$command" | grep -qE '\bMERGE_GATE_BYPASS=1\b'; then
        # Explicit user-phrase bypass — allow, but leave an audit trail.
        mkdir -p "$HOME/.claude/logs"
        printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$cwd" "$command" >> "$HOME/.claude/logs/merge-bypass.log"
        exit 0
    fi
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: "Merge gate: approve ONLY if you just told Claude to merge this PR (\"merge it\" / \"ship it\") AND the pre-merge summary showed Review loop: CLEAN. Reject otherwise. (\"ship it through\" skips this prompt next time; every skip is audit-logged.)"
        }
    }'
    exit 0
fi

# --- Enforcement-config self-protection (shell writes) ---
# Shell-side twin of config-edit-gate.sh: writing to the hooks/settings that
# implement these gates must never happen silently via Bash redirection,
# sed -i, mv, etc. Read-only access (cat/grep/ls) stays frictionless.
if echo "$command" | grep -qE '\.claude/(hooks|settings\.json|settings\.local\.json|keybindings\.json)'; then
    if echo "$command" | grep -qE '>>|>[[:space:]]*[^&[:space:]]|\bsed[[:space:]]+-i\b|\btee\b|\brm\b|\bmv\b|\bcp\b|\bchmod\b|\bln\b|\btruncate\b'; then
        jq -n '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "ask",
                permissionDecisionReason: "This command writes to Claude Code enforcement config (~/.claude/hooks or settings). Confirm only if you explicitly requested this change."
            }
        }'
        exit 0
    fi
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
