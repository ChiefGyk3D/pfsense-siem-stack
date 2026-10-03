# Wiki source

The project's GitHub wiki at <https://github.com/ChiefGyk3D/pfsense-siem-stack/wiki> is
**generated**, not hand-maintained. This directory holds the only hand-written wiki
pages; every other page is one of the repository's Markdown files, converted.

| File | Becomes |
|------|---------|
| `Home.md` | The wiki landing page |
| `_Sidebar.md` | The navigation sidebar shown on every page |
| `_Footer.md` | The footer shown on every page |
| `New-to-pfSense-Start-Here.md` | Beginner on-ramp: the pieces, a reading order, the things that bite newcomers |
| `Glossary.md` | One-line definitions with links to the full explanations |
| `FAQ.md` | Short answers that point at the right page |
| `README.md` | This file. Not published. |

## How it is built

`scripts/build-wiki.py` holds the map from source file to wiki page name (`PAGES`) and
does the conversion:

- relative links between Markdown files become wiki page links, anchors preserved;
- relative links to anything else in the repository become `github.com/.../blob/main/...`
  links, images are copied into `images/`;
- the leading `# Title` is dropped (the wiki shows the page name as the title);
- each page gets a trailer naming its source file.

```bash
python3 scripts/build-wiki.py            # writes build/wiki/ (git-ignored)
python3 scripts/build-wiki.py --out DIR  # anywhere else, e.g. a clone of the .wiki.git repo
```

It exits non-zero if a relative link does not resolve or a tracked Markdown file has no
`PAGES` entry, and CI runs it on every push and pull request for that reason.

`.github/workflows/wiki.yml` runs the build on every push to `main` that touches
documentation and pushes the result to `pfsense-siem-stack.wiki.git`. The wiki repository
only exists once the wiki has been created once through the GitHub UI (Wiki tab → *Create
the first page*); until then the workflow fails with a message saying so.

## Writing pages here

- Use **repository-relative links** (`../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md`,
  `Glossary.md`), never wiki-style `[[Page]]` links or bare page names. The builder
  rewrites them, and `scripts/check-doc-links.py` can verify them in CI.
- Adding a new documentation file anywhere in the repository requires a `PAGES` entry
  with a stable, readable page name, plus a link from `Home.md` and `_Sidebar.md` if it
  deserves one. Renaming a page name later breaks external links to it.
- Keep `_Sidebar.md` short; it renders in a narrow column.
