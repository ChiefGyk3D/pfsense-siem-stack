#!/usr/bin/env python3
"""Check relative markdown links in all git-tracked .md files.

Scans every tracked Markdown file for inline links and image references
(``[text](target)`` / ``![alt](target)``) and verifies that relative targets
resolve to a real file or directory in the repository.

Skipped targets:
  - absolute URLs (http://, https://, mailto:, etc.)
  - pure in-page anchors (#fragment)

For targets with an anchor (``file.md#section``) only the file's existence is
validated, not the fragment.

Exit status: 0 if all links resolve, 1 otherwise (broken links are listed).
"""
import os
import re
import subprocess
import sys
import urllib.parse

# Inline markdown link/image: [text](target) or ![alt](target)
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+(?:\s+\"[^\"]*\")?)\)")
# Fenced code block delimiter
FENCE_RE = re.compile(r"^\s*(```|~~~)")


def repo_root():
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def tracked_markdown(root):
    out = subprocess.run(
        ["git", "ls-files", "-z", "*.md"],
        capture_output=True, text=True, check=True, cwd=root,
    )
    return [f for f in out.stdout.split("\0") if f]


def extract_targets(text):
    """Yield (lineno, target) for markdown links, skipping fenced code blocks."""
    in_fence = False
    for lineno, line in enumerate(text.splitlines(), start=1):
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for match in LINK_RE.finditer(line):
            target = match.group(1)
            # Strip optional link title: (target "title")
            target = target.split(' "')[0].strip()
            yield lineno, target


def main():
    root = repo_root()
    broken = []
    checked = 0

    for md_file in tracked_markdown(root):
        md_path = os.path.join(root, md_file)
        try:
            with open(md_path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            broken.append((md_file, 0, f"<unreadable: {exc}>"))
            continue

        for lineno, target in extract_targets(text):
            parsed = urllib.parse.urlparse(target)
            if parsed.scheme or target.startswith("//"):
                continue  # external URL
            path_part = urllib.parse.unquote(parsed.path)
            if not path_part:
                continue  # pure anchor (#fragment)
            checked += 1
            base = os.path.dirname(md_path)
            resolved = os.path.normpath(os.path.join(base, path_part))
            if not os.path.exists(resolved):
                broken.append((md_file, lineno, target))

    if broken:
        print(f"FAIL: {len(broken)} broken relative link(s):\n")
        for md_file, lineno, target in broken:
            print(f"  {md_file}:{lineno}: {target}")
        return 1

    print(f"OK: {checked} relative link(s) checked across "
          f"{len(tracked_markdown(root))} markdown files — all resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
