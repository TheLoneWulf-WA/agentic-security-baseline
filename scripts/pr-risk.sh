#!/usr/bin/env bash
# pr-risk.sh [PR | --suggest] — decide a PR's review level mechanically, for any project (2026-11-10).
# Prints RISK=sensitive|normal and SIZE=small|large, with the reasons.
#
# SENSITIVE when any of these hold:
#   - a changed file matches the shared defaults   ~/.claude/risk-paths/_default-paths.txt (case-insensitive)
#   - a changed CODE file's name matches            ~/.claude/risk-paths/_default-names.txt (docs skipped)
#   - a changed file matches the project's list     <repo>/.claude/risk-paths.txt, else ~/.claude/risk-paths/<repo-name>.txt
#   - an added line matches the shared word list   ~/.claude/risk-paths/_default-content.txt
#   - the project has no list of its own yet (the defaults alone can miss a project's own risky folders)
#   - anything can't be read (no repo, no PR, no files)
# Never review a PR at lower risk than this says; higher is allowed.
set -u
pr="${1:-}"
dir="$HOME/.claude/risk-paths"
strip() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$'; }

# --suggest: draft a project list from this repo's own folders, for a session to review and open as its own PR.
if [ "$pr" = "--suggest" ]; then
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repository" >&2; exit 1; }
  out="$top/.claude/risk-paths.txt"
  [ -f "$out" ] && { echo "a project list already exists at $out; edit it instead" >&2; exit 1; }
  echo "# Project risk paths for $(basename "$top") (extended regex, one per line), read by ~/.claude/scripts/pr-risk.sh."
  echo "# Drafted by pr-risk.sh --suggest on $(date -u +%Y-%m-%d). A session reviews it, adds this project's own risky"
  echo "# folders the shared defaults can't know, removes false hits, and opens it as its own small PR for the owner's OK."
  echo "# Folders below matched the shared lists; folders that hold money, access, customer data, uploads or deletes belong here."
  dirs=$(mktemp) || { echo "could not create a temporary file" >&2; exit 1; }
  trap 'rm -f "$dirs"' EXIT
  git -C "$top" ls-files | awk -F/ '{p=""; for(i=1;i<NF;i++){p=p $i "/"; print p}}' | sort -u > "$dirs"
  { grep -i -E -f <(strip "$dir/_default-paths.txt") "$dirs" ; grep -i -E -f <(strip "$dir/_default-names.txt") "$dirs"; } 2>/dev/null \
    | grep -v -i -E '(^|/)(docs|node_modules|dist|build|\.next|coverage)/' | sort -u \
    | awk '{ for (i in seen) if (index($0, i) == 1) next; seen[$0]=1; print }' \
    | sed -e 's/[.[\()*+?{|^$]/\\&/g' -e 's/^/^/'
  echo "# Next: review, then save as $out and open it as its own PR."
  exit 0
fi
say() { echo "RISK=$1"; echo "SIZE=$2"; echo "LINES=$3"; shift 3; for r in "$@"; do echo "REASON: $r"; done; }
fail() { say sensitive large "?" "$1 (defaulting to sensitive)"; exit 0; }
top=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository"
repo=$(gh repo view --json name -q .name 2>/dev/null) || repo=$(basename "$top")
json=$(gh pr view $pr --json files,additions,deletions 2>/dev/null) || fail "could not read the PR"
files=$(printf '%s' "$json" | python3 -I -c 'import json,sys;[print(f["path"]) for f in json.load(sys.stdin)["files"]]' 2>/dev/null)
[ -n "$files" ] || fail "the PR lists no files"
lines=$(printf '%s' "$json" | python3 -I -c 'import json,sys;d=json.load(sys.stdin);print(d["additions"]+d["deletions"])')
size=large; [ "$lines" -le 150 ] && size=small
reasons=()
# shared default paths
if [ -f "$dir/_default-paths.txt" ]; then
  m=$(printf '%s\n' "$files" | grep -i -E -f <(strip "$dir/_default-paths.txt") || true)
  [ -n "$m" ] && reasons+=("default path: $(printf '%s' "$m" | head -5 | tr '\n' ' ')")
else reasons+=("shared default path list missing"); fi
# shared default names, on code files only (docs skipped)
if [ -f "$dir/_default-names.txt" ]; then
  code=$(printf '%s\n' "$files" | grep -v -i -E '(^|/)docs/|\.(md|mdx|txt|rst)$' || true)
  m=$( [ -n "$code" ] && printf '%s\n' "$code" | grep -i -E -f <(strip "$dir/_default-names.txt") || true)
  [ -n "$m" ] && reasons+=("sensitive name: $(printf '%s' "$m" | head -5 | tr '\n' ' ')")
fi
# project list
plist=""
[ -f "$top/.claude/risk-paths.txt" ] && plist="$top/.claude/risk-paths.txt"
[ -z "$plist" ] && [ -f "$dir/$repo.txt" ] && plist="$dir/$repo.txt"
if [ -n "$plist" ]; then
  m=$(printf '%s\n' "$files" | grep -E -f <(strip "$plist") || true)
  [ -n "$m" ] && reasons+=("project path: $(printf '%s' "$m" | head -5 | tr '\n' ' ')")
else reasons+=("no project list yet: run ~/.claude/scripts/pr-risk.sh --suggest, review the draft, and open it as <repo>/.claude/risk-paths.txt in its own PR"); fi
# added lines
if [ -f "$dir/_default-content.txt" ]; then
  hit=$(gh pr diff $pr 2>/dev/null | grep -E '^\+[^+]' | grep -E -o -f <(strip "$dir/_default-content.txt") | sort -u | head -5 | tr '\n' ' ' || true)
  [ -n "$hit" ] && reasons+=("added code mentions: $hit")
fi
if [ ${#reasons[@]} -gt 0 ]; then say sensitive "$size" "$lines" "${reasons[@]}"; else say normal "$size" "$lines" "no sensitive path or word matched (project list: ${plist#$top/})"; fi
exit 0
