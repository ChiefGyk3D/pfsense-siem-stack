#!/usr/bin/env python3
"""Validate the docs-migration page registry against a repo's tracked *.md files.

Usage: python3 -I check_registry.py REGISTRY --repo DIR

Exit 0 = clean. Exit 2 = offenders, one per line on stdout as
"<class>: <detail>". Exit 64 = usage error, unreadable or malformed CSV
(missing/unknown header column, unknown action, empty page on an action that
needs one, a page on a keep row, bad order, wrong field count).

CSV header: repo_path,section,page,action,order[,notes]. Actions: move,
merge-into, split-into, archive-into, keep, stub. section is empty or
L<start>-L<end> (1-indexed, inclusive). order is blank or an integer.

Offender classes:
  unregistered    tracked *.md that is in no row's repo_path
  unknown-file    row repo_path that is not a tracked file
  bad-page-name   page is not a landing name (Home, Start-Here, Glossary, FAQ),
                  _Sidebar/_Footer, or <Prefix>-<Words> (case-sensitive prefix
                  from the allowed list; Words = hyphen-joined [A-Za-z0-9]+)
  case-collision  two distinct page names equal ignoring case
  page-collision  RULE: group rows by page. A page is fine if it has rows from
                  exactly one distinct source (any action), or if every row for
                  it has action merge-into or archive-into (any number of
                  sources). Otherwise, i.e. two or more distinct sources and at
                  least one row that is move, stub or split-into, it is an
                  offender.
  section-overlap per source: two ranges overlap, a malformed range (non-numeric,
                  start>end, start<1), or an empty section on a source that has
                  more than one row (ranged rows or another whole-file row)
  split-single    source with a split-into row but fewer than 2 rows with sections
Sections need not cover the whole file; the move tool checks line loss later.
"""
import argparse
import csv
import re
import subprocess
import sys

ACTIONS = {"move", "merge-into", "split-into", "archive-into", "keep", "stub"}
REQUIRED = ["repo_path", "section", "page", "action", "order"]
PREFIXES = ["Suricata", "pfBlockerNG", "EVE-Forwarder", "Telegraf", "pfSense",
            "SIEM", "Docker-Stack", "SOAR", "CrowdSec", "Install", "Operate",
            "Troubleshoot", "Reference", "Project", "Archive"]
LANDING = {"Home", "Start-Here", "Glossary", "FAQ", "_Sidebar", "_Footer"}
PAGE_RE = re.compile(
    r"(?:%s)-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*" % "|".join(re.escape(p) for p in PREFIXES))
RANGE_RE = re.compile(r"L([0-9]+)-L([0-9]+)")
EX_USAGE = 64


class Usage(Exception):
    pass


def load(path):
    try:
        with open(path, newline="", encoding="utf-8") as fh:
            reader = csv.DictReader(fh, strict=True)
            fields = reader.fieldnames or []
            if any(c not in fields for c in REQUIRED):
                raise Usage("missing required header column(s): "
                            + ",".join(c for c in REQUIRED if c not in fields))
            extra = [c for c in fields if c not in REQUIRED and c != "notes"]
            if extra or len(set(fields)) != len(fields):
                raise Usage("unknown or duplicate header column(s)")
            rows = []
            for row in reader:
                n = reader.line_num
                if None in row or any(row[c] is None for c in REQUIRED):
                    raise Usage("line %d: wrong number of fields" % n)
                r = {c: row[c].strip() if c != "repo_path" else row[c] for c in REQUIRED}
                r["line"] = n
                if not r["repo_path"]:
                    raise Usage("line %d: empty repo_path" % n)
                if r["action"] not in ACTIONS:
                    raise Usage("line %d: unknown action %r" % (n, r["action"]))
                if r["action"] == "keep" and r["page"]:
                    raise Usage("line %d: keep row must have an empty page" % n)
                if r["action"] != "keep" and not r["page"]:
                    raise Usage("line %d: action %s needs a page" % (n, r["action"]))
                if r["order"] and not re.fullmatch(r"-?[0-9]+", r["order"]):
                    raise Usage("line %d: order must be an integer" % n)
                rows.append(r)
            return rows
    except (OSError, UnicodeDecodeError, csv.Error) as exc:
        raise Usage("cannot read registry: %s" % exc)


def tracked_md(repo):
    try:
        out = subprocess.run(["git", "-C", repo, "ls-files", "-z", "--", "*.md"],
                             capture_output=True, check=True).stdout
        allf = subprocess.run(["git", "-C", repo, "ls-files", "-z"],
                              capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise Usage("git ls-files failed in %s: %s" % (repo, exc))
    md = {p for p in out.decode("utf-8", "surrogateescape").split("\0") if p.endswith(".md")}
    every = {p for p in allf.decode("utf-8", "surrogateescape").split("\0") if p}
    return md, every


def check(rows, md, every):
    bad = []
    registered = {r["repo_path"] for r in rows}
    for p in sorted(md - registered):
        bad.append("unregistered: %s" % p)
    for p in sorted(registered - every):
        bad.append("unknown-file: %s" % p)

    pages = sorted({r["page"] for r in rows if r["page"]})
    for pg in pages:
        if pg not in LANDING and not PAGE_RE.fullmatch(pg):
            bad.append("bad-page-name: %s" % pg)
    seen = {}
    for pg in pages:
        seen.setdefault(pg.lower(), []).append(pg)
    for names in sorted(seen.values()):
        if len(names) > 1:
            bad.append("case-collision: %s" % " vs ".join(names))

    for pg in pages:
        prow = [r for r in rows if r["page"] == pg]
        if len({r["repo_path"] for r in prow}) < 2:
            continue
        if not all(r["action"] in ("merge-into", "archive-into") for r in prow):
            bad.append("page-collision: %s <- %s" % (
                pg, ", ".join(sorted({r["repo_path"] for r in prow}))))

    by_src = {}
    for r in rows:
        by_src.setdefault(r["repo_path"], []).append(r)
    for src in sorted(by_src):
        srows = by_src[src]
        ranges = []
        for r in srows:
            if not r["section"]:
                if len(srows) > 1:
                    bad.append("section-overlap: %s line %d: empty section with other rows"
                               % (src, r["line"]))
                continue
            m = RANGE_RE.fullmatch(r["section"])
            if not m or int(m.group(1)) < 1 or int(m.group(1)) > int(m.group(2)):
                bad.append("section-overlap: %s line %d: malformed range %r"
                           % (src, r["line"], r["section"]))
                continue
            ranges.append((int(m.group(1)), int(m.group(2)), r["line"]))
        ranges.sort()
        for (a1, b1, l1), (a2, b2, l2) in zip(ranges, ranges[1:]):
            if a2 <= b1:
                bad.append("section-overlap: %s lines %d and %d overlap" % (src, l1, l2))
        if any(r["action"] == "split-into" for r in srows):
            if sum(1 for r in srows if r["section"]) < 2:
                bad.append("split-single: %s" % src)
    return bad


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("registry")
    ap.add_argument("--repo", required=True)
    try:
        args = ap.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else EX_USAGE
    try:
        rows = load(args.registry)
        md, every = tracked_md(args.repo)
    except Usage as exc:
        print("usage: %s" % exc, file=sys.stderr)
        return EX_USAGE
    bad = check(rows, md, every)
    for line in bad:
        print(line)
    return 2 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
