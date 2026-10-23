# docs-migration

Temporary tooling for the wiki restructure (scrum-around-and-find-out#64).
It is removed in a later task of the same plan once the migration lands.

## registry.csv

One row per source-file section, header
`repo_path,section,page,action,order` plus an optional trailing `notes`.

- `repo_path`: tracked file, relative to the repo root.
- `section`: empty (whole file) or `L<start>-L<end>` (1-indexed, inclusive).
- `page`: target wiki page name; empty only for `keep`.
- `action`: move, merge-into, split-into, archive-into, copy-into, keep, stub.
  `copy-into` copies the section (whole file when empty) to the page and leaves
  the source in place, so it may sit beside a whole-file `keep` row. A page fed
  by copy-into may also be fed by merge-into or archive-into rows, never by
  move, stub or split-into rows from another source.
- `order`: integer ordering inside a merged or split page; may be blank.

## Check it

    python3 -I check_registry.py registry.csv --repo ..
    python3 -I check_stubs.py stubs.csv --registry registry.csv --repo ..
    python3 -I -m unittest -v

## stubs.csv

Old wiki names that stay for one release as redirect stubs. `check_stubs.py`
requires unique names (case-insensitive), no stub equal to a real page, tracked
`repo_path`, and notes of the form `points to <Page>[ and <Page>]` (or
`points to repo file <path>`) naming pages that exist in registry.csv.

Both checkers: exit 0 clean, 2 offenders (one `<class>: <detail>` per line), 64 usage or
malformed CSV. Rules are in the `check_registry.py` docstring.
