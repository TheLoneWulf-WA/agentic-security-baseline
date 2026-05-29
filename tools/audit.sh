#!/usr/bin/env bash
#
# audit.sh — read-only check for the Mini Shai-Hulud / TanStack-class
# npm supply-chain worm (and similar install-time attacks).
#
# READ-ONLY. This script inspects your machine and reports what it finds.
# It does NOT modify, delete, quarantine, disable, or revoke anything.
#
# Usage:
#   bash tools/audit.sh            # scans your home directory
#   bash tools/audit.sh ~/code     # or point it at a specific folder
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │ IF A PERSISTENCE DAEMON IS FOUND: do NOT revoke your GitHub tokens   │
# │ first. The malware watches for token revocation and runs `rm -rf ~/` │
# │ when it sees it. Remove the daemon, THEN rotate credentials.         │
# └─────────────────────────────────────────────────────────────────────┘
#
# The known-package list below is point-in-time and not exhaustive — the
# campaign expands. Authoritative current list:
#   https://socket.dev/blog/tanstack-npm-packages-compromised-mini-shai-hulud-supply-chain-attack
#
# No `set -e` on purpose: every check should run even if an earlier one
# matches or a path is missing.

SCAN_DIR="${1:-$HOME}"
findings=0

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
grn()   { printf '\033[32m%s\033[0m\n' "$1"; }
ylw()   { printf '\033[33m%s\033[0m\n' "$1"; }
hdr()   { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

echo "audit.sh — read-only supply-chain compromise check"
echo "scan target: $SCAN_DIR"

# ---------------------------------------------------------------------------
hdr "1. Persistence daemon (dead-man's switch)"
hit=0
mac_agent="$HOME/Library/LaunchAgents/com.user.gh-token-monitor.plist"
linux_unit="$HOME/.config/systemd/user/gh-token-monitor.service"
[ -f "$mac_agent" ]  && { red "  FOUND: $mac_agent";  hit=1; findings=$((findings+1)); }
[ -f "$linux_unit" ] && { red "  FOUND: $linux_unit"; hit=1; findings=$((findings+1)); }
if [ -d "$HOME/Library/LaunchAgents" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && { red "  FOUND (name match): $f"; hit=1; findings=$((findings+1)); }
  done < <(grep -rl -iE "gh-token|token-monitor" "$HOME/Library/LaunchAgents" 2>/dev/null)
fi
if [ "$hit" -eq 0 ]; then
  grn "  clean — no known persistence daemon"
else
  ylw "  -> DO NOT revoke GitHub tokens before removing this. Remove first, then rotate."
fi

# ---------------------------------------------------------------------------
hdr "2. Dropped scripts / loaded services"
hit=0
[ -f "$HOME/.local/bin/gh-token-monitor.sh" ] && {
  red "  FOUND: $HOME/.local/bin/gh-token-monitor.sh"; hit=1; findings=$((findings+1)); }
if command -v launchctl >/dev/null 2>&1; then
  if launchctl list 2>/dev/null | grep -iqE "gh-token|token-monitor"; then
    red "  FOUND: a gh-token-monitor service is loaded (launchctl)"; hit=1; findings=$((findings+1))
  fi
fi
[ "$hit" -eq 0 ] && grn "  clean — no dropped scripts or loaded services"

# ---------------------------------------------------------------------------
hdr "3. AI-tooling config tampering (.claude / .vscode)"
# The worm persists by injecting into .claude/settings.json and
# .vscode/tasks.json. These IOC strings should never appear there.
ioc='gh-token-monitor|IfYouRevokeThisToken|git-tanstack|rm -rf ~|rm -rf \$HOME'
hit=0
check_cfg() {
  local cfg="$1"
  [ -f "$cfg" ] || return
  if grep -lEi "$ioc" "$cfg" >/dev/null 2>&1; then
    red "  SUSPECT: $cfg"
    grep -nEi "$ioc" "$cfg" 2>/dev/null | sed 's/^/        /'
    hit=1; findings=$((findings+1))
  fi
}
check_cfg "$HOME/.claude/settings.json"
while IFS= read -r cfg; do
  check_cfg "$cfg"
done < <(find "$SCAN_DIR" \
            \( -type d \( -name node_modules -o -name .git \) -prune \) -o \
            -type f \( -path '*/.claude/settings.json' -o -path '*/.vscode/tasks.json' \) -print 2>/dev/null)
[ "$hit" -eq 0 ] && grn "  clean — no known IOC strings in AI-tooling configs"
ylw "  note: only catches known signatures. Eyeball any hook/command you don't recognize."

# ---------------------------------------------------------------------------
hdr "4. Affected packages in lockfiles"
pkgs='@tanstack/|@opensearch-project/|@mistralai/|guardrails-ai|@uipath/|squawk'
hit=0
while IFS= read -r lf; do
  if grep -lE "($pkgs)" "$lf" >/dev/null 2>&1; then
    red "  CONTAINS affected namespace: $lf"
    grep -oE "($pkgs)[^\"',[:space:]]*" "$lf" 2>/dev/null | sort -u | sed 's/^/        /'
    hit=1; findings=$((findings+1))
  fi
done < <(find "$SCAN_DIR" \
            \( -type d \( -name node_modules -o -name .git \) -prune \) -o \
            -type f \( -name package-lock.json -o -name pnpm-lock.yaml -o -name yarn.lock \) -print 2>/dev/null)
[ "$hit" -eq 0 ] && grn "  clean — no affected namespaces in scanned lockfiles"
ylw "  note: package list is point-in-time. Authoritative current list: Socket's writeup."

# ---------------------------------------------------------------------------
hdr "5. npm install-time defenses"
if command -v npm >/dev/null 2>&1; then
  ig=$(npm config get ignore-scripts 2>/dev/null)
  if [ "$ig" = "true" ]; then
    grn "  ignore-scripts = true (install scripts blocked)"
  else
    ylw "  -> ignore-scripts = $ig. Set it: npm config set ignore-scripts true"
  fi
  mra=$(npm config get min-release-age 2>/dev/null)
  if [ -n "$mra" ] && [ "$mra" != "undefined" ] && [ "$mra" != "null" ]; then
    grn "  min-release-age = $mra"
  else
    ylw "  -> min-release-age not set (needs npm 11+). Set it: npm config set min-release-age 2d"
  fi
else
  ylw "  npm not found — skipping"
fi

# ---------------------------------------------------------------------------
hdr "Summary"
if [ "$findings" -eq 0 ]; then
  grn "No known indicators found."
  echo  "(Absence of indicators is not proof of safety — keep your defenses on.)"
else
  red "$findings finding(s) above need your attention."
  ylw "If a persistence daemon was found: remove it BEFORE revoking tokens, then rotate everything it had access to."
fi
exit 0
