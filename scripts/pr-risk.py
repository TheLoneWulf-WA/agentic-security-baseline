#!/usr/bin/env python3
"""pr-risk.py [PR] - is this PR docs, images or styles only?

Prints RISK=normal only when EVERY changed file (old and new names) is docs, images or styles by file type
(~/.claude/risk-paths/_default-safe.txt) AND no added line contains a risky word (_default-content.txt: scripts,
iframes, database access, secrets and so on). Everything else is RISK=sensitive. Also prints SIZE and LINES.

Used to pick reviewers: sensitive means the normal review (Opus bug reviewer, Sonnet compliance, four-agent
/code-review); normal means two Sonnet reviewers. It fails SAFE: any error gives RISK=sensitive.
"""
import json, os, re, subprocess, sys

D = os.path.expanduser("~/.claude/risk-paths")

def out(risk, size, lines, reasons):
    print(f"RISK={risk}\nSIZE={size}\nLINES={lines}")
    for r in reasons: print(f"REASON: {r}")
    sys.exit(0)

def fail(why): out("sensitive", "large", "?", [f"{why} (defaulting to sensitive)"])

def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0: raise RuntimeError(" ".join(cmd[:3]))
    return r.stdout

def load(name, flags=0):
    p = os.path.join(D, name)
    if not os.path.exists(p) or not os.path.getsize(p): fail(f"list {p} is missing or empty")
    pats = []
    for n, line in enumerate(open(p), 1):
        s = line.strip()
        if not s or s.startswith("#"): continue
        try: pats.append(re.compile(s, flags))
        except re.error as e: fail(f"{p} line {n} doesn't compile ({e})")
    if not pats: fail(f"list {p} has no patterns")
    return pats

def main():
    safe = load("_default-safe.txt", re.I)
    words = load("_default-content.txt")
    pr = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        meta = json.loads(run("gh", "pr", "view", *([pr] if pr else []), "--json", "number,additions,deletions,url"))
        num, lines = meta["number"], meta["additions"] + meta["deletions"]
        # Take the repo from the PR's own URL, not the current folder: given a
        # PR link from another repo, the folder's repo would be read instead
        # and could hand back the wrong PR's files (2026-11-10).
        m = re.match(r"https://github\.com/([^/]+/[^/]+)/pull/\d+$", meta["url"])
        if not m: fail(f"unexpected PR url {meta['url']}")
        repo = m.group(1)
        rows = run("gh", "api", f"repos/{repo}/pulls/{num}/files", "--paginate", "--jq", '.[] | [.filename, (.previous_filename // "")] | @tsv')
        diff = run("gh", "pr", "diff", meta["url"])
    except Exception as e:
        fail(f"could not read the PR ({e})")
    files = {f for row in rows.splitlines() for f in row.split("\t") if f}
    if not files: fail("the PR lists no files")
    size = "small" if lines <= 150 else "large"
    reasons = []
    other = sorted(f for f in files if not any(p.search(f) for p in safe))
    if other: reasons.append("not docs, images or styles: " + " ".join(other[:5]))
    added, in_hunk = [], False
    for l in diff.splitlines():
        if l.startswith("diff --git "): in_hunk = False; continue
        if l.startswith("@@"): in_hunk = True; continue
        if in_hunk and l.startswith("+"): added.append(l[1:])
    hits = sorted({m.group(0)[:40] for l in added for p in words for m in [p.search(l)] if m})
    if hits: reasons.append("added lines mention: " + " ".join(hits[:5]))
    if reasons: out("sensitive", size, lines, reasons)
    out("normal", size, lines, ["docs, images or styles only, and no risky words added"])

if __name__ == "__main__":
    try: main()
    except SystemExit: raise
    except Exception as e: fail(f"unexpected error ({e})")
