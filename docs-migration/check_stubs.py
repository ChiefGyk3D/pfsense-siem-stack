#!/usr/bin/env python3
"""Validate docs-migration/stubs.csv (old wiki names that become redirect stubs).

Usage: python3 -I check_stubs.py STUBS --registry REGISTRY --repo DIR

Exit 0 = clean. Exit 2 = offenders, one "<class>: <detail>" per line on stdout.
Exit 64 = usage error or malformed CSV (same CSV format as check_registry.py).

Offender classes:
  stub-action        row whose action is not stub
  stub-duplicate     two stub page names equal ignoring case
  stub-is-real-page  stub page name equals a real page in the registry, ignoring
                     case (the old name is the new page, so no redirect is needed)
  stub-untracked     stub repo_path is not a tracked file
  stub-target        notes lack "points to <target>[ and <target>...]", or a
                     target is neither a page in the registry nor
                     "repo file <tracked path>"
"""
import argparse
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "check_registry", os.path.join(HERE, "check_registry.py"))
cr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cr)


def load_notes(path):
    """Map csv line number -> notes (load() drops the optional notes column)."""
    import csv
    notes = {}
    with open(path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh, strict=True)
        for row in reader:
            notes[reader.line_num] = (row.get("notes") or "")
    return notes


def check(stubs, notes, pages, every):
    bad = []
    real = {p.lower() for p in pages}
    seen = {}
    for r in stubs:
        name = r["page"]
        if r["action"] != "stub":
            bad.append("stub-action: line %d: %s is %s" % (r["line"], name, r["action"]))
        seen.setdefault(name.lower(), []).append(name)
        if name.lower() in real:
            bad.append("stub-is-real-page: %s" % name)
        if r["repo_path"] not in every:
            bad.append("stub-untracked: %s (%s)" % (r["repo_path"], name))
        m = re.search(r"points to (.+?)\s*$", notes.get(r["line"], ""))
        if not m:
            bad.append("stub-target: %s: notes do not say 'points to <page>'" % name)
            continue
        for tgt in re.split(r"\s+and\s+", m.group(1)):
            tgt = tgt.strip()
            if tgt.startswith("repo file "):
                if tgt[len("repo file "):] not in every:
                    bad.append("stub-target: %s: no tracked file %r" % (name, tgt))
            elif tgt not in pages:
                bad.append("stub-target: %s: %r is not a page in the registry" % (name, tgt))
    for names in sorted(seen.values()):
        if len(names) > 1:
            bad.append("stub-duplicate: %s" % " vs ".join(names))
    return bad


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("stubs")
    ap.add_argument("--registry", required=True)
    ap.add_argument("--repo", required=True)
    try:
        args = ap.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else cr.EX_USAGE
    try:
        stubs = cr.load(args.stubs)
        notes = load_notes(args.stubs)
        reg = cr.load(args.registry)
        _, every = cr.tracked_md(args.repo)
    except (cr.Usage, OSError, UnicodeDecodeError, ValueError) as exc:
        print("usage: %s" % exc, file=sys.stderr)
        return cr.EX_USAGE
    except Exception as exc:  # csv.Error
        print("usage: %s" % exc, file=sys.stderr)
        return cr.EX_USAGE
    pages = {r["page"] for r in reg if r["page"]}
    bad = check(stubs, notes, pages, every)
    for line in bad:
        print(line)
    return 2 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
