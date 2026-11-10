#!/usr/bin/env python3
"""pr-risk.py [PR | --suggest] - decide a PR's review level mechanically, for any project (2026-11-10).

Prints RISK=sensitive|normal, SIZE=small|large, LINES=n and REASON lines. Never review a PR at lower risk than this says.

SAFE-LIST approach: a PR is NORMAL only when EVERY changed file (old and new names) matches a safe list -
~/.claude/risk-paths/_default-safe.txt or the project's .claude/safe-paths.txt - and NO sensitive signal fires:
shared risky paths (_default-paths.txt), risky names on code files (_default-names.txt), risky words in added
lines (_default-content.txt), or the project's .claude/risk-paths.txt. Everything else is sensitive.

Fails SAFE: any error (no repo, no PR, no diff, a missing or empty shared list, a pattern that doesn't compile)
gives RISK=sensitive. Project lists are read from the PR's BASE branch, so a PR can't loosen the lists it is
judged by; and any change under .claude/ is sensitive through the shared defaults.
"""
import json, os, re, subprocess, sys

D = os.path.expanduser("~/.claude/risk-paths")
DOC = re.compile(r"\.(md|mdx|txt|rst|adoc)$", re.I)  # by extension only: a code file under docs/ is still code

def out(risk, size, lines, reasons):
    print(f"RISK={risk}\nSIZE={size}\nLINES={lines}")
    for r in reasons: print(f"REASON: {r}")
    sys.exit(0)

def fail(why): out("sensitive", "large", "?", [f"{why} (defaulting to sensitive)"])

def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0: raise RuntimeError(" ".join(cmd[:3]))
    return r.stdout

def compile_lines(text, where, flags=0):
    pats = []
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"): continue
        try: pats.append(re.compile(s, flags))
        except re.error as e: fail(f"{where} line {n} doesn't compile ({e})")
    return pats

def shared(name, flags=0, must=True):
    p = os.path.join(D, name)
    if not os.path.exists(p) or not os.path.getsize(p):
        if must: fail(f"shared list {p} is missing or empty")
        return []
    pats = compile_lines(open(p).read(), p, flags)
    if must and not pats: fail(f"shared list {p} has no patterns")
    return pats

def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    try: top = run("git", "rev-parse", "--show-toplevel").strip()
    except Exception: fail("not inside a git repository")
    try: repo = run("gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()
    except Exception: repo = ""
    name = repo.split("/")[-1] if repo else os.path.basename(top)

    safe_d = shared("_default-safe.txt", re.I)
    risk_p = shared("_default-paths.txt", re.I)
    risk_n = shared("_default-names.txt", re.I)
    risk_c = shared("_default-content.txt")

    if arg == "--suggest":
        rp = os.path.join(top, ".claude", "risk-paths.txt")
        proj_r = compile_lines(open(rp).read(), rp) if os.path.exists(rp) else []
        suggest(top, safe_d, risk_p, risk_n, proj_r); return

    pr = arg
    try:
        meta = json.loads(run("gh", "pr", "view", *([pr] if pr else []), "--json", "number,baseRefName,additions,deletions"))
        num, base = meta["number"], meta["baseRefName"]
        lines = meta["additions"] + meta["deletions"]
        pages = run("gh", "api", f"repos/{repo}/pulls/{num}/files", "--paginate", "--jq", ".[] | [.filename, (.previous_filename // \"\")] | @tsv")
        diff = run("gh", "pr", "diff", str(num))
    except Exception as e:
        fail(f"could not read the PR ({e})")
    files = set()
    for row in pages.splitlines():
        for f in row.split("\t"):
            if f: files.add(f)
    if not files: fail("the PR lists no files")
    size = "small" if lines <= 150 else "large"

    def from_base(path, fallback):
        try: return run("git", "-C", top, "show", f"origin/{base}:{path}"), f"{base}:{path}"
        except Exception:
            if os.path.exists(fallback): return open(fallback).read(), fallback
            return None, None
    st, sw = from_base(".claude/safe-paths.txt", os.path.join(D, f"{name}.safe.txt"))
    rt, rw = from_base(".claude/risk-paths.txt", os.path.join(D, f"{name}.txt"))
    safe_p = compile_lines(st, sw) if st else []
    risk_proj = compile_lines(rt, rw) if rt else []

    reasons = []
    def note(label, hits):
        if hits: reasons.append(f"{label}: " + " ".join(sorted(hits)[:5]))
    note("risky path (shared)", [f for f in files if any(p.search(f) for p in risk_p)])
    note("risky name (shared)", [f for f in files if not DOC.search(f) and any(p.search(f) for p in risk_n)])
    note("risky path (project)", [f for f in files if any(p.search(f) for p in risk_proj)])
    added, in_hunk = [], False
    for l in diff.splitlines():
        if l.startswith("diff --git "): in_hunk = False; continue
        if l.startswith("@@"): in_hunk = True; continue
        if in_hunk and l.startswith("+"): added.append(l[1:])  # inside a hunk every + line is added code, even "+++x"
    words = sorted({m.group(0)[:40] for l in added for p in risk_c for m in [p.search(l)] if m})
    note("added code mentions", words)
    unsafe = [f for f in files if not any(p.search(f) for p in safe_d + safe_p)]
    if unsafe:
        note("not on a safe list" + ("" if safe_p else " (no project safe list yet: run pr-risk.sh --suggest)"), unsafe)
    if reasons: out("sensitive", size, lines, reasons)
    out("normal", size, lines, ["every file is on a safe list and no sensitive signal fired"])

def suggest(top, safe_d, risk_p, risk_n, proj_r):
    files = [f for f in run("git", "-C", top, "ls-files").splitlines() if f and not any(p.search(f) for p in safe_d)]
    def risky(f):
        return any(p.search(f) for p in risk_p) or (not DOC.search(f) and any(p.search(f) for p in risk_n)) or any(p.search(f) for p in proj_r)
    folders = {}
    for f in files:
        parts = f.split("/")
        for i in range(1, len(parts)):
            folders.setdefault("/".join(parts[:i]) + "/", []).append(f)
    chosen = []
    for c in sorted(k for k, v in folders.items() if k.count("/") >= 2 and not any(risky(f) for f in v)):
        if not any(c.startswith(x) for x in chosen): chosen.append(c)
    print(f"# Project SAFE paths for {os.path.basename(top)} (extended regex), read by ~/.claude/scripts/pr-risk.sh.")
    print("# Drafted by --suggest from folders where no file trips a risky check. REVIEW EVERY LINE: keep only folders whose")
    print("# changes can't touch money, sign-in, access, customer data, uploads, deletes, jobs, webhooks, config or third-party")
    print("# scripts. When unsure, delete the line: unlisted code is reviewed in full.")
    for c in chosen: print("^" + re.sub(r"([.\[\]()*+?{}|^$\\])", r"\\\1", c))
    print(f"# Save as {top}/.claude/safe-paths.txt and open it as its own PR for the owner's OK.")

if __name__ == "__main__":
    try: main()
    except SystemExit: raise
    except Exception as e: fail(f"unexpected error ({e})")
