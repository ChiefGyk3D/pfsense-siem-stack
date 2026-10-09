#!/usr/bin/env python3
"""Build the GitHub wiki from the Markdown files in this repository.

The documentation lives in ``docs/``, ``config/``, ``dashboards/``, ``plugins/``,
``scripts/`` and the repository root. This script assembles those files, plus the
hand-written landing pages in ``wiki/``, into a flat set of GitHub-wiki pages:

* every source file in ``PAGES`` becomes ``<Page-Name>.md`` in the output directory;
* relative links between Markdown files are rewritten to wiki page links
  (``docs/pfsense/PFSENSE_UPGRADE_GUIDE.md#part-1`` -> ``Upgrading-pfSense#part-1``);
* relative links to anything else in the repository (scripts, JSON, directories)
  become ``https://github.com/<owner>/<repo>/blob/main/...`` links;
* images are copied into ``<out>/images/`` and referenced from there;
* the leading ``# Title`` of each source file is dropped, because the wiki renders
  the page name as the title;
* each generated page ends with a line naming the source file, so nobody edits
  the wiki copy by hand.

The output directory is normally a clone of ``<repo>.wiki.git``;
``.github/workflows/wiki.yml`` runs this on every push to ``main`` and pushes the
result. Run it locally to preview::

    python3 scripts/build-wiki.py                 # writes build/wiki/
    python3 scripts/build-wiki.py --out /tmp/w    # elsewhere

Exit status is 1 if any relative link cannot be resolved or points at a Markdown
file that has no entry in ``PAGES`` (add one). CI runs the script for that reason.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import urllib.parse

REPO_SLUG = "ChiefGyk3D/pfsense-siem-stack"
DEFAULT_BRANCH = "main"
BLOB_URL = f"https://github.com/{REPO_SLUG}/blob/{DEFAULT_BRANCH}/"
TREE_URL = f"https://github.com/{REPO_SLUG}/tree/{DEFAULT_BRANCH}/"
WIKI_URL = f"https://github.com/{REPO_SLUG}/wiki/"

# Source file (repo-relative) -> wiki page name. The page name is what appears in the
# wiki URL and, with hyphens shown as spaces, as the page title. Keep names stable:
# renaming a page breaks every external link to it.
PAGES = {
    # Hand-written wiki pages (wiki/). README.md there documents the build and is
    # deliberately not a page.
    "wiki/Home.md": "Home",
    "wiki/_Sidebar.md": "_Sidebar",
    "wiki/_Footer.md": "_Footer",
    "wiki/New-to-pfSense-Start-Here.md": "New-to-pfSense-Start-Here",
    "wiki/Glossary.md": "Glossary",
    "wiki/FAQ.md": "FAQ",
    # Repository root
    "README.md": "Project-Overview",
    "QUICK_START.md": "Quick-Start",
    "ORGANIZATION.md": "Repository-Layout",
    "ROADMAP.md": "Roadmap",
    "CHANGELOG.md": "Changelog",
    "CONTRIBUTING.md": "Contributing",
    "SECURITY.md": "Security-Policy",
    # docs/
    "docs/DOCUMENTATION_INDEX.md": "Documentation-Index",
    "docs/ARCHIVE.md": "Archived-Material",
    # pfSense knowledge base
    "docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md": "Suricata-Optimization-Guide",
    "docs/pfsense/SURICATA_CONFIGURATION.md": "Suricata-Configuration-and-Design",
    "docs/pfsense/LAN_MONITORING.md": "LAN-and-East-West-Monitoring",
    "docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md": "pfBlockerNG-Optimization",
    "docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md": "pfBlockerNG-Feed-Reference",
    "docs/pfsense/TELEGRAF_ON_PFSENSE.md": "Telegraf-on-pfSense",
    "docs/pfsense/TELEGRAF_PFBLOCKER_SETUP.md": "Telegraf-pfBlockerNG-Pipeline",
    "docs/pfsense/MAC_VENDOR_LOOKUP_SETUP.md": "MAC-Vendor-Lookup",
    "docs/pfsense/PFSENSE_UPGRADE_GUIDE.md": "Upgrading-pfSense",
    "docs/pfsense/TRAFFIC_SHAPING_GUIDE.md": "Traffic-Shaping-Guide",
    "docs/pfsense/crowdsec-phase1.md": "CrowdSec-Exploratory-Notes",
    "config/sid/README.md": "Suricata-SID-Management",
    # Deploy
    "docs/install/HARDWARE_REQUIREMENTS.md": "Hardware-Requirements",
    "docs/install/NEW_USER_CHECKLIST.md": "New-User-Checklist",
    "docs/install/INSTALL_SIEM_STACK.md": "SIEM-Server-Installation",
    "docs/install/INSTALL_PFSENSE_FORWARDER.md": "Forwarder-Installation",
    "docs/install/GEOIP_SETUP.md": "GeoIP-Setup",
    "docs/install/INSTALL_DASHBOARD.md": "Dashboard-Installation",
    # Operate
    "docs/operations/MANAGEMENT_CONSOLE.md": "Management-Console",
    "docs/operations/SURICATA_FORWARDER_MONITORING.md": "Forwarder-Operations-and-Watchdog",
    "docs/operations/MULTI_INTERFACE_RETENTION.md": "Multi-Interface-and-Retention",
    # Fix
    "docs/troubleshooting/TROUBLESHOOTING.md": "Troubleshooting",
    "docs/troubleshooting/DASHBOARD_NO_DATA_FIX.md": "Dashboard-Shows-No-Data",
    "docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md": "Data-Stops-at-Midnight-UTC",
    "docs/troubleshooting/LOG_ROTATION_FIX.md": "Forwarder-and-Log-Rotation",
    "docs/troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md": "Filterlog-Stops-After-Rotation",
    # Reference
    "docs/reference/CONFIGURATION.md": "Configuration-Reference",
    "docs/reference/FIELD_REFERENCE.md": "Field-Reference",
    "config/README.md": "Configuration-Files",
    "dashboards/README.md": "Dashboards",
    "dashboards/wazuh/README.md": "Wazuh-Dashboards",
    "plugins/README.md": "Telegraf-Plugins",
    "scripts/README.md": "Scripts-Reference",
    "tests/README.md": "Tests",
    # Other backends
    "docs/siem/COMPARISON.md": "SIEM-Backend-Comparison",
    "docs/siem/wazuh/README.md": "Wazuh-Integration",
    "docs/siem/graylog/README.md": "Graylog",
}

# Pages that get no "Source:" trailer (the wiki renders them as chrome, not content).
NO_TRAILER = {"_Sidebar", "_Footer"}

# Tracked Markdown files that are deliberately not wiki pages; links to them become
# ordinary github.com links.
NOT_PAGES = {"wiki/README.md"}

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}

# The "](target)" of any Markdown link or image, including the outer link of a badge
# ([![alt](img)](target)); an optional "title" after the target is kept. Matching only
# the tail avoids caring what the link text contains.
LINK_RE = re.compile(r"(\]\()([^)\s]+)((?:\s+\"[^\"]*\")?\))")
# <img src="..."> and <a href="..."> in raw HTML (the README support footer).
HTML_SRC_RE = re.compile(r"((?:src|href)=\")([^\"]+)(\")")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
H1_RE = re.compile(r"^#\s+\S")


def repo_root():
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


class Builder:
    def __init__(self, root, out_dir):
        self.root = root
        self.out_dir = out_dir
        self.images_dir = os.path.join(out_dir, "images")
        self.errors = []
        self.copied_images = {}

    # -- link resolution -----------------------------------------------------

    def resolve(self, source, target):
        """Map one link target from `source` (repo-relative) to its wiki form."""
        parsed = urllib.parse.urlparse(target)
        if parsed.scheme or target.startswith("//") or target.startswith("#"):
            return target  # external URL or in-page anchor
        if not parsed.path:
            return target
        rel = urllib.parse.unquote(parsed.path)
        anchor = f"#{parsed.fragment}" if parsed.fragment else ""
        abs_path = os.path.normpath(os.path.join(self.root, os.path.dirname(source), rel))
        repo_rel = os.path.relpath(abs_path, self.root)

        if repo_rel in PAGES:
            return PAGES[repo_rel] + anchor
        if not os.path.exists(abs_path):
            self.errors.append(f"{source}: link target does not exist: {target}")
            return target
        ext = os.path.splitext(repo_rel)[1].lower()
        if ext == ".md" and repo_rel not in NOT_PAGES:
            self.errors.append(
                f"{source}: links to {repo_rel}, which has no entry in PAGES"
            )
            return target
        if ext in IMAGE_EXT:
            return self.copy_image(abs_path, repo_rel)
        if os.path.isdir(abs_path):
            return TREE_URL + urllib.parse.quote(repo_rel.rstrip("/")) + "/"
        return BLOB_URL + urllib.parse.quote(repo_rel) + anchor

    def copy_image(self, abs_path, repo_rel):
        if repo_rel not in self.copied_images:
            # media/Suricata IDS_IPS WAN Dashboard.png -> images/media-Suricata-IDS_IPS-WAN-Dashboard.png
            name = re.sub(r"[^A-Za-z0-9._-]+", "-", repo_rel.replace("/", "-"))
            os.makedirs(self.images_dir, exist_ok=True)
            shutil.copy2(abs_path, os.path.join(self.images_dir, name))
            self.copied_images[repo_rel] = "images/" + name
        return self.copied_images[repo_rel]

    # -- page conversion -----------------------------------------------------

    def convert(self, source, text, page):
        out_lines = []
        in_fence = False
        dropped_h1 = False
        for line in text.splitlines():
            if FENCE_RE.match(line):
                in_fence = not in_fence
                out_lines.append(line)
                continue
            if in_fence:
                out_lines.append(line)
                continue
            if not dropped_h1:
                if not line.strip():
                    continue  # leading blank lines before the title
                if H1_RE.match(line):
                    dropped_h1 = True
                    continue
                dropped_h1 = True  # no H1; keep everything from here on

            line = LINK_RE.sub(
                lambda m: m.group(1) + self.resolve(source, m.group(2)) + m.group(3), line
            )
            line = HTML_SRC_RE.sub(
                lambda m: m.group(1) + self.resolve(source, m.group(2)) + m.group(3), line
            )
            out_lines.append(line)

        body = "\n".join(out_lines).strip("\n") + "\n"
        if page not in NO_TRAILER:
            src_url = BLOB_URL + urllib.parse.quote(source)
            body += (
                "\n---\n\n"
                f"<sub>Source: [`{source}`]({src_url}). This wiki is generated from the "
                f"repository on every push to `{DEFAULT_BRANCH}`; edit the source file "
                "and open a pull request rather than editing the wiki page.</sub>\n"
            )
        return body

    def build(self):
        os.makedirs(self.out_dir, exist_ok=True)
        # Remove pages from a previous build so renamed/deleted sources disappear.
        for name in os.listdir(self.out_dir):
            path = os.path.join(self.out_dir, name)
            if name.endswith(".md") and os.path.isfile(path):
                os.remove(path)
        if os.path.isdir(self.images_dir):
            shutil.rmtree(self.images_dir)

        written = []
        for source, page in PAGES.items():
            src_path = os.path.join(self.root, source)
            if not os.path.exists(src_path):
                self.errors.append(f"PAGES entry has no file: {source}")
                continue
            with open(src_path, encoding="utf-8") as fh:
                text = fh.read()
            body = self.convert(source, text, page)
            with open(os.path.join(self.out_dir, page + ".md"), "w", encoding="utf-8") as fh:
                fh.write(body)
            written.append(page)

        # Every tracked .md should be a page, except the ones that document the build.
        tracked = subprocess.run(
            ["git", "ls-files", "-z", "*.md"],
            capture_output=True, text=True, check=True, cwd=self.root,
        ).stdout.split("\0")
        for md in filter(None, tracked):
            if md not in PAGES and md not in NOT_PAGES:
                self.errors.append(f"tracked Markdown file has no PAGES entry: {md}")
        return written


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument(
        "--out", default=None,
        help="output directory (default: build/wiki under the repository root)",
    )
    args = ap.parse_args()

    root = repo_root()
    out_dir = os.path.abspath(args.out) if args.out else os.path.join(root, "build", "wiki")

    builder = Builder(root, out_dir)
    written = builder.build()

    print(f"wrote {len(written)} pages and {len(builder.copied_images)} images to {out_dir}")
    if builder.errors:
        print(f"\nFAIL: {len(builder.errors)} problem(s):\n")
        for err in builder.errors:
            print(f"  {err}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
