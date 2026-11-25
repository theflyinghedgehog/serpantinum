#!/usr/bin/env python3
"""Git repos widget helper.

  gitrepos.py scan [--fetch]          print the state of every repo as JSON
  gitrepos.py run <message> <dir>...  commit (if dirty) and push each repo

Which folders are scanned: ~/.config/serpantinum/gitrepos.conf, one path per
line. A line starting with "!" hides that repo, "#" is a comment. Without the
file, ~/Code is scanned. Repos are looked for up to 4 levels deep.
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HOME = os.path.expanduser("~")
CONF = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")),
                    "serpantinum", "gitrepos.conf")
MAX_DEPTH = 4
SKIP_DIRS = {"node_modules", ".venv", "venv", "__pycache__", "target", "build", "dist", ".cache"}

ENV = dict(os.environ, GIT_TERMINAL_PROMPT="0", LC_ALL="C",
           GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=8")


def git(repo, *args, timeout=20):
    try:
        p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True,
                           env=ENV, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timed out"


def read_conf():
    roots, hidden = [], set()
    try:
        with open(CONF) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("!"):
                    hidden.add(os.path.realpath(os.path.expanduser(line[1:].strip())))
                else:
                    roots.append(os.path.expanduser(line))
    except OSError:
        pass
    if not roots:
        roots = [os.path.join(HOME, "Code")]
    return roots, hidden


def find_repos(roots, hidden):
    found = []
    seen = set()
    for root in roots:
        root = os.path.realpath(root)
        if not os.path.isdir(root):
            continue
        base_depth = root.rstrip("/").count("/")
        for cur, dirs, files in os.walk(root):
            if ".git" in dirs or ".git" in files:
                if cur not in seen and cur not in hidden:
                    seen.add(cur)
                    found.append(cur)
            if cur.count("/") - base_depth >= MAX_DEPTH:
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d != ".git" and d not in SKIP_DIRS and not d.startswith(".")]
    return sorted(found)


def repo_state(path, fetch):
    if fetch:
        git(path, "fetch", "--quiet", "--all", "--prune", timeout=30)
    rc, out, _ = git(path, "status", "--porcelain=v2", "--branch", "-z")
    if rc != 0:
        return None
    branch, upstream = "", ""
    ahead = behind = staged = modified = untracked = conflicts = 0
    files = []
    entries = out.split("\0")
    i = 0
    while i < len(entries):
        e = entries[i]
        i += 1
        if not e:
            continue
        if e.startswith("# branch.head "):
            branch = e[14:]
        elif e.startswith("# branch.upstream "):
            upstream = e[18:]
        elif e.startswith("# branch.ab "):
            a, b = e[12:].split()
            ahead, behind = int(a), -int(b)
        elif e[0] in "12":
            parts = e.split(" ", 8 if e[0] == "1" else 9)
            xy = parts[1]
            name = parts[-1]
            if e[0] == "2":
                i += 1   # renamed entries carry the old path as a second field
            if xy[0] != ".":
                staged += 1
            if xy[1] != ".":
                modified += 1
            files.append({"st": xy.replace(".", " "), "path": name})
        elif e[0] == "u":
            conflicts += 1
            files.append({"st": "UU", "path": e.split(" ", 10)[-1]})
        elif e[0] == "?":
            untracked += 1
            files.append({"st": "??", "path": e[2:]})

    has_remote = bool(git(path, "remote")[1].strip())
    unpublished = 0
    if not upstream and branch and branch != "(detached)":
        rc, o, _ = git(path, "rev-list", "--count", "HEAD", "--not", "--remotes")
        if rc == 0 and o.strip().isdigit():
            unpublished = int(o.strip())
    stashes = len([l for l in git(path, "stash", "list")[1].splitlines() if l.strip()])

    name = os.path.basename(path)
    rel = path[len(HOME) + 1:] if path.startswith(HOME + "/") else path
    return {
        "path": path, "name": name, "rel": rel, "branch": branch, "upstream": upstream,
        "hasRemote": has_remote, "ahead": ahead, "behind": behind,
        "unpublished": unpublished, "staged": staged, "modified": modified,
        "untracked": untracked, "conflicts": conflicts, "stashes": stashes,
        "changes": len(files), "files": files[:12],
    }


def cmd_scan(fetch):
    roots, hidden = read_conf()
    repos = find_repos(roots, hidden)
    with ThreadPoolExecutor(max_workers=6) as ex:
        states = [s for s in ex.map(lambda p: repo_state(p, fetch), repos) if s]
    print(json.dumps({"roots": roots, "repos": states}))


def say(msg):
    print(msg, flush=True)


def cmd_run(msg, paths):
    msg = msg.strip()
    failed = 0
    for n, path in enumerate(paths, 1):
        name = os.path.basename(path)
        say(f"@@REPO {n}/{len(paths)} {name}")
        say(f"==> {name}")
        ok = True
        dirty = bool(git(path, "status", "--porcelain")[1].strip())
        if dirty:
            if not msg:
                say("   has changes but no commit message was given, skipping commit")
            else:
                git(path, "add", "-A")
                rc, o, e = git(path, "commit", "-m", msg)
                for l in (o + e).splitlines():
                    say("   " + l)
                ok = rc == 0
        if ok:
            rc, o, _ = git(path, "remote")
            remotes = o.split()
            if not remotes:
                say("   no remote, nothing to push")
            else:
                rc, up, _ = git(path, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
                if rc == 0:
                    rc, o, e = git(path, "push", timeout=90)
                else:
                    br = git(path, "branch", "--show-current")[1].strip()
                    remote = "origin" if "origin" in remotes else remotes[0]
                    say(f"   no upstream, pushing {br} to {remote}")
                    rc, o, e = git(path, "push", "-u", remote, br, timeout=90)
                for l in (o + e).splitlines():
                    say("   " + l)
                ok = rc == 0
        if not ok:
            failed += 1
            say(f"   failed: {name}")
    say(f"@@DONE {failed}")
    return 1 if failed else 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "scan":
        cmd_scan("--fetch" in sys.argv[2:])
        return 0
    if len(sys.argv) >= 4 and sys.argv[1] == "run":
        return cmd_run(sys.argv[2], sys.argv[3:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
