#!/usr/bin/env bash
#
# Push Routing Gate — Claude Code PreToolUse hook
#
# Prompts for user confirmation when Claude attempts to:
#   1. Push to protected branches (main/master/production)
#   2. Merge a PR via the known routes (gh pr merge, gh api, curl/wget to
#      the API) — "ask mode": the command pauses on an in-session
#      confirmation prompt; one user keypress approves or rejects it. The
#      prompt includes the review-loop marker state for the current branch.
#   3. Write to enforcement config (~/.claude/hooks, settings.json) via shell.
#
# Enforces protocols from ~/.claude/CLAUDE.md:
#   - Push Routing: default = feature branch + PR; override = user says "push to main"
#   - PR Merge Follow-up (ask mode): Claude runs the merge only after the
#     user says "merge it" / "ship it"; this gate then requires a live user
#     keypress. The literal phrase "ship it through" skips the prompt via a
#     MERGE_GATE_BYPASS=1 prefix; every bypass is audit-logged.
#   (To restore deny mode — user merges in the GitHub UI, Claude locked out —
#    change the merge case's permissionDecision from "ask" to "deny".)
#
# Honest scope: this intercepts the enumerated command shapes. A merge
# issued through an unenumerated route (a script file, a non-curl HTTP
# client) is not caught — the gate makes drift and casual circumvention
# loud, not impossible. The MERGE_GATE_BYPASS prefix is mechanical; the
# rule that it only follows the user's "ship it through" phrase lives in
# CLAUDE.md (best-effort), which is why every use of the prefix leaves a
# line in ~/.claude/logs/merge-bypass.log — accountable, not prevented.
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
    # Enrich the prompt with the review-loop marker written by /until-clean
    # on a clean pass. Scoped to the CURRENT branch in cwd — if the merge
    # targets a different PR's branch, judge from the pre-merge summary
    # instead. Any commit after the clean pass makes the marker stale.
    marker_note="No clean-review marker for the current branch — expect a 'Review loop: CLEAN' line in the pre-merge summary, or run /until-clean first."
    if [ -n "$cwd" ] && [ -d "$cwd" ]; then
        gitdir=$(cd "$cwd" && git rev-parse --git-dir 2>/dev/null || echo "")
        branch=$(cd "$cwd" && git branch --show-current 2>/dev/null || echo "")
        head=$(cd "$cwd" && git rev-parse HEAD 2>/dev/null || echo "")
        if [ -n "$gitdir" ] && [ -n "$branch" ]; then
            case "$gitdir" in
                /*) marker_file="$gitdir/review-clean/$(echo "$branch" | tr '/' '_')" ;;
                *)  marker_file="$cwd/$gitdir/review-clean/$(echo "$branch" | tr '/' '_')" ;;
            esac
            if [ -f "$marker_file" ]; then
                marker_sha=$(cut -d' ' -f1 "$marker_file")
                if [ "$marker_sha" = "$head" ]; then
                    marker_note="Review loop marker: CLEAN at ${marker_sha:0:7} (matches HEAD of $branch)."
                else
                    marker_note="WARNING: commits landed after the last clean review of $branch (marker ${marker_sha:0:7}, HEAD ${head:0:7}) — the clean pass is stale; re-run /until-clean."
                fi
            fi
        fi
    fi
    jq -n --arg note "$marker_note" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: ("Merge gate: approve ONLY if you just told Claude to merge this PR (\"merge it\" / \"ship it\"). " + $note + " (\"ship it through\" skips this prompt next time; every skip is audit-logged.)")
        }
    }'
    exit 0
fi

# --- Enforcement-config self-protection (shell writes) ---
# Shell-side counterpart of config-edit-gate.sh — deliberately WIDER in
# one respect: the unanchored pattern also catches project-level
# .claude/settings.json, while the Edit/Write gate scopes to $HOME.
# Writing to the files that implement these gates must never happen
# silently via Bash redirection, sed -i, mv, etc. Read-only access
# (cat/grep/ls) stays frictionless.
if echo "$command" | grep -qE '\.claude/(hooks|skills|commands|CLAUDE\.md|settings\.json|settings\.local\.json|keybindings\.json)'; then
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

# --- Check 1: Protected branch named as a push target ---
# Catches: git push origin main (also with trailing flags like
# --no-verify), refspec forms (HEAD:main, feature:main), -u variants.
# The [\s:] left boundary means feature-main does NOT match; the (\s|$)
# right boundary means trailing flags no longer defeat the check.
if echo "$command" | grep -qE '[[:space:]:](main|master|production)([[:space:]]|$)'; then
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
