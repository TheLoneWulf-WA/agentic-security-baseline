#!/usr/bin/env bash
#
# Push Routing Gate — Claude Code PreToolUse hook
#
# Prompts for user confirmation when Claude attempts to:
#   1. Push anything other than a plain claude/* branch to origin
#      (protected branches, force, --all/--mirror, tags, deletes, URLs)
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
# If the input cannot be read, ask: a gate that cannot see the command
# must not let it through silently.
unreadable='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Push routing gate could not read this command (jq missing or input not JSON), so it asks."}}'
command -v jq >/dev/null 2>&1 || { printf '%s\n' "$unreadable"; exit 0; }
command=$(printf '%s' "$input" | jq -er '.tool_input.command // ""') || { printf '%s\n' "$unreadable"; exit 0; }
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)

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

# --- Push gate: fail closed ---
# Feature-branch pushes are on the settings allow list, so this hook is
# the only thing between Claude and a push it should not make silently.
# It allows exactly one shape and asks on everything else:
#
#   git push [-u | --set-upstream] origin claude/<name>
#
# as a whole command part (between separators: && || ; | & newline),
# with nothing before `git` (no VAR=, env, sudo, subshell) and nothing
# after the branch name except an optional 2>&1. So these ask: other
# branches and refspecs (claude/x:main), flags (--force, --all,
# --mirror, --tags, --delete), other remotes or URLs, quotes, variables,
# a bare `git push`, `git -C dir push`, `git send-pack`, `git subtree
# push`, and any push the hook cannot parse.
#
# The command text is not the whole story: git config decides where a
# push lands. So the hook also reads the repo's effective config in the
# session's cwd, and asks when any of these could move or widen the push:
# remote.origin.push (remaps the refspec), push.default upstream/tracking
# (sends claude/x to its upstream, often main), push.followTags (adds
# tags), push.recurseSubmodules on-demand/only (pushes other repos), a
# tag with the same name as the branch (git prefers the tag), or a cd /
# pushd / popd anywhere in the command (the config read would be the
# wrong repo's). This reads command text and config: a push hidden in a
# script file or eval is outside it (see "Honest scope" above), and such
# commands match no allow entry either, so the normal permission flow
# decides them.
#
# Why ask rather than deny: the user may want any of these, and says so
# with an override ("push to main"); the keypress is theirs to give.

# A push is `git`, any global options (-C dir, -c k=v, --no-pager,
# --git-dir=...), then push, send-pack or `subtree push`. Options are
# matched broadly so an unusual form still counts as a push and asks.
push_re='\bgit([[:space:]]+(-[Cc][[:space:]]+[^[:space:];&|]+|-[^[:space:];&|]+))*[[:space:]]+(push|send-pack|subtree[[:space:]]+push)\b'
if ! printf '%s' "$command" | grep -qE "$push_re"; then
    exit 0
fi

ask() {
    jq -n --arg r "$1" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason: $r
        }
    }'
    exit 0
}
unparsed="Push gate could not read this push command, so it asks. Confirm only if you asked for this push."

# Split into command parts. Newlines become ";" (a newline inside a grep
# pattern would split the pattern in two), and the harmless 2>&1 is
# dropped first so its "&" does not split a part.
flat=$(printf '%s' "$command" | sed 's/[[:space:]]*2>&1//g' | tr '\n' ';')
parts=$(printf '%s' "$flat" | grep -oE "[^;&|]*${push_re}[^;&|]*") || ask "$unparsed"
[ -n "$parts" ] || ask "$unparsed"

safe_re='^git[[:space:]]+push([[:space:]]+(-u|--set-upstream))?[[:space:]]+origin[[:space:]]+claude/[A-Za-z0-9._/-]+$'
branches=""
while IFS= read -r part; do
    part=$(printf '%s' "$part" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [ -z "$part" ] && continue
    if printf '%s' "$part" | grep -qE "[[:space:]:/+\"'](main|master|production)([^A-Za-z0-9._-]|\$)"; then
        ask "Push to protected branch detected. Push Routing requires feature branch + PR by default. Only confirm if you explicitly said \"push to main\"."
    fi
    if ! printf '%s' "$part" | grep -qE "$safe_re"; then
        ask "This push is not the plain feature-branch shape (git push [-u] origin claude/<name>). Force, --all, --mirror, tags, deletes, other remotes, refspecs, bare pushes and anything before git always ask. Confirm only if you asked for this push."
    fi
    branches="$branches ${part##* }"
done <<< "$parts"

# A directory change anywhere in the command means the config read below
# would be the wrong repo's.
if printf '%s' "$command" | grep -qE '(^|[^A-Za-z0-9_-])(cd|pushd|popd)([^A-Za-z0-9_-]|$)'; then
    ask "This push comes with a directory change, so the push gate cannot check that repo's config. Confirm only if you asked for this push."
fi

# Read the effective git config of the repo the push runs in.
if [ -z "$cwd" ] || [ ! -d "$cwd" ] || ! git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    ask "Push gate could not find the repo for this push, so it asks. Confirm only if you asked for this push."
fi
cfg() { git -C "$cwd" config --get "$1" 2>/dev/null; }
if [ -n "$(git -C "$cwd" config --get-all remote.origin.push 2>/dev/null)" ]; then
    ask "This repo sets remote.origin.push, which can redirect a claude/* push to another branch. Confirm only if you asked for this push."
fi
case "$(cfg push.default)" in
    upstream|tracking)
        ask "push.default is upstream here, so a claude/* push goes to the branch's upstream, which may be main. Confirm only if you asked for this push." ;;
esac
case "$(printf '%s' "$(cfg push.followTags)" | tr 'A-Z' 'a-z')" in
    true|yes|on|1)
        ask "push.followTags is on here, so this push would also push tags. Confirm only if you asked for this push." ;;
esac
case "$(cfg push.recurseSubmodules)" in
    on-demand|only)
        ask "push.recurseSubmodules would push submodule repos too. Confirm only if you asked for this push." ;;
esac
for b in $branches; do
    if git -C "$cwd" show-ref --verify --quiet "refs/tags/$b"; then
        ask "A tag named $b exists, and git pushes the tag before the branch of the same name. Confirm only if you asked for this push."
    fi
done

# Every push part is a plain push of a claude/* branch to origin, and the
# repo's config cannot move it.
exit 0
