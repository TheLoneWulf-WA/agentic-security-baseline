#!/usr/bin/env bash
# pr-risk.sh [PR | --suggest] - wrapper for pr-risk.py (see its header). Fails safe if Python can't run.
python3 -I "$HOME/.claude/scripts/pr-risk.py" "$@" || { echo "RISK=sensitive"; echo "SIZE=large"; echo "LINES=?"; echo "REASON: pr-risk.py failed to run (defaulting to sensitive)"; }
