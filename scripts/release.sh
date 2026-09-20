#!/bin/bash
# Cut a release: bump VERSION + pfsense-siem, roll CHANGELOG [Unreleased] into
# [X.Y.Z] - YYYY-MM-DD, commit, and create an annotated tag vX.Y.Z.
#
# Usage: scripts/release.sh X.Y.Z [--push]
#   Run on an up-to-date, clean checkout of main. Without --push nothing leaves
#   your machine; inspect with `git show` and then `git push origin main --tags`.
#   Pushing the tag triggers .github/workflows/release.yml, which builds the
#   tarball + SHA256SUMS and publishes the GitHub Release from the CHANGELOG.
set -euo pipefail

VERSION="${1:-}"
PUSH="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: $0 X.Y.Z [--push]" >&2; exit 1
fi
TAG="v${VERSION}"
DATE="$(date +%Y-%m-%d)"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean — commit or stash first." >&2; exit 1
fi
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
    echo "You are on '$BRANCH'; releases are cut from main." >&2; exit 1
fi
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    echo "Tag ${TAG} already exists." >&2; exit 1
fi
if ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    echo "CHANGELOG.md has no [Unreleased] section to release." >&2; exit 1
fi

echo "Releasing ${TAG} (${DATE})"

# CHANGELOG: [Unreleased] -> [X.Y.Z] - date, with a fresh empty [Unreleased] above it
python3 - "$VERSION" "$DATE" <<'PY'
import re, sys
version, date = sys.argv[1], sys.argv[2]
p = "CHANGELOG.md"
s = open(p, encoding="utf-8").read()
s = s.replace("## [Unreleased]", f"## [Unreleased]\n\n## [{version}] - {date}", 1)
# Version history table: insert a row after the header separator if the table exists
m = re.search(r"(\| Version \| Date +\| Key Features \|\n\|[-| ]+\|\n)", s)
if m:
    s = s[:m.end()] + f"| {version}   | {date} | see above |\n" + s[m.end():]
open(p, "w", encoding="utf-8").write(s)
PY

echo "$VERSION" > VERSION
sed -i "s/^VERSION=\"[0-9][0-9.]*\"/VERSION=\"${VERSION}\"/" pfsense-siem

# Sanity: the checks CI runs
bash -n pfsense-siem
python3 scripts/check-doc-links.py >/dev/null

git add CHANGELOG.md VERSION pfsense-siem
git commit -q -m "release: ${TAG}"
git tag -a "$TAG" -m "pfSense SIEM Stack ${TAG}"
echo "Committed and tagged ${TAG}."

if [[ "$PUSH" == "--push" ]]; then
    git push origin main
    git push origin "$TAG"
    echo "Pushed. The Release workflow will publish https://github.com/ChiefGyk3D/pfsense-siem-stack/releases/tag/${TAG}"
else
    echo "Review with: git show ${TAG}"
    echo "Publish with: git push origin main && git push origin ${TAG}"
fi
