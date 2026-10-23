# docs-migration

Temporary tooling for the wiki restructure (scrum-around-and-find-out#64).
It is removed in a later task of the same plan once the migration lands.

## registry.csv

One row per source-file section, header
`repo_path,section,page,action,order` plus an optional trailing `notes`.

- `repo_path`: tracked file, relative to the repo root.
- `section`: empty (whole file) or `L<start>-L<end>` (1-indexed, inclusive).
- `page`: target wiki page name; empty only for `keep`.
- `action`: move, merge-into, split-into, archive-into, keep, stub.
- `order`: integer ordering inside a merged or split page; may be blank.

## Check it

    python3 -I check_registry.py registry.csv --repo ..
    python3 -I -m unittest -v

Exit 0 clean, 2 offenders (one `<class>: <detail>` per line), 64 usage or
malformed CSV. Rules are in the `check_registry.py` docstring.
