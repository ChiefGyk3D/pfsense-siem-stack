"""Tests for check_registry.py. Run: python3 -I -m unittest -v"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check_registry.py")
HDR = "repo_path,section,page,action,order\n"


def git(repo, *args):
    subprocess.run(["git", "-C", repo, *args], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class Base(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.repo = os.path.join(self._td.name, "repo")
        os.mkdir(self.repo)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.name", "test")
        git(self.repo, "config", "user.email", "test@example.com")
        self.reg = os.path.join(self._td.name, "registry.csv")

    def add(self, *paths):
        for p in paths:
            full = os.path.join(self.repo, p)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as fh:
                fh.write("x\n")
            git(self.repo, "add", p)

    def run_check(self, csv_text):
        with open(self.reg, "w", newline="") as fh:
            fh.write(csv_text)
        r = subprocess.run(
            [sys.executable, "-I", SCRIPT, self.reg, "--repo", self.repo],
            capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def assertOffender(self, csv_text, cls):
        code, out = self.run_check(csv_text)
        self.assertEqual(code, 2, out)
        self.assertTrue(any(l.startswith(cls + ": ") for l in out.splitlines()), out)

    def assertUsage(self, csv_text):
        code, out = self.run_check(csv_text)
        self.assertEqual(code, 64, out)


class Checks(Base):
    def test_clean(self):
        self.add("README.md", "docs/a.md")
        code, out = self.run_check(
            HDR + "README.md,,,keep,\ndocs/a.md,,Operate-Backups,move,\n")
        self.assertEqual(code, 0, out)

    def test_unregistered(self):
        self.add("README.md", "docs/extra.md")
        self.assertOffender(HDR + "README.md,,,keep,\n", "unregistered")

    def test_unknown_file(self):
        self.add("README.md")
        self.assertOffender(
            HDR + "README.md,,,keep,\nnope.md,,Operate-X,move,\n", "unknown-file")

    def test_duplicate_page_two_moves(self):
        self.add("a.md", "b.md")
        self.assertOffender(
            HDR + "a.md,,Operate-X,move,\nb.md,,Operate-X,move,\n", "page-collision")

    def test_move_plus_merge_collides(self):
        self.add("a.md", "b.md")
        self.assertOffender(
            HDR + "a.md,,Operate-X,move,\nb.md,,Operate-X,merge-into,1\n",
            "page-collision")

    def test_bad_prefix(self):
        self.add("a.md")
        self.assertOffender(HDR + "a.md,,Random-Thing,move,\n", "bad-page-name")

    def test_lowercase_prefix(self):
        self.add("a.md")
        self.assertOffender(HDR + "a.md,,operate-thing,move,\n", "bad-page-name")

    def test_prefix_only_bad(self):
        self.add("a.md")
        self.assertOffender(HDR + "a.md,,Operate-,move,\n", "bad-page-name")

    def test_landing_and_system_names_ok(self):
        self.add("a.md", "b.md", "c.md")
        code, out = self.run_check(
            HDR + "a.md,,Home,move,\nb.md,,_Sidebar,move,\nc.md,,EVE-Forwarder-Setup,move,\n")
        self.assertEqual(code, 0, out)

    def test_case_collision(self):
        self.add("a.md", "b.md")
        self.assertOffender(
            HDR + "a.md,,Operate-Backups,move,\nb.md,,Operate-backups,move,\n",
            "case-collision")

    def test_section_overlap(self):
        self.add("a.md")
        self.assertOffender(
            HDR + "a.md,L1-L10,Operate-A,split-into,1\na.md,L5-L20,Operate-B,split-into,1\n",
            "section-overlap")

    def test_empty_section_with_ranged(self):
        self.add("a.md")
        self.assertOffender(
            HDR + "a.md,,Operate-A,split-into,1\na.md,L1-L5,Operate-B,split-into,1\n",
            "section-overlap")

    def test_bad_range(self):
        self.add("a.md")
        self.assertOffender(HDR + "a.md,L9-L2,Operate-A,move,\n", "section-overlap")
        self.assertOffender(HDR + "a.md,Lx-L2,Operate-A,move,\n", "section-overlap")

    def test_split_single(self):
        self.add("a.md")
        self.assertOffender(HDR + "a.md,L1-L5,Operate-A,split-into,1\n", "split-single")

    def test_split_two_ok(self):
        self.add("a.md")
        code, out = self.run_check(
            HDR + "a.md,L1-L5,Operate-A,split-into,1\na.md,L6-L9,Operate-B,split-into,1\n")
        self.assertEqual(code, 0, out)

    def test_merge_shares_page(self):
        self.add("a.md", "b.md")
        code, out = self.run_check(
            HDR + "a.md,,Operate-X,merge-into,1\nb.md,,Operate-X,merge-into,2\n")
        self.assertEqual(code, 0, out)

    def test_archive_shares_page(self):
        self.add("a.md", "b.md")
        code, out = self.run_check(
            HDR + "a.md,,Archive-Old,archive-into,1\nb.md,,Archive-Old,archive-into,2\n")
        self.assertEqual(code, 0, out)

    def test_keep_with_page_is_usage(self):
        self.add("a.md")
        self.assertUsage(HDR + "a.md,,Operate-X,keep,\n")

    def test_move_without_page_is_usage(self):
        self.add("a.md")
        self.assertUsage(HDR + "a.md,,,move,\n")

    def test_unknown_action_is_usage(self):
        self.add("a.md")
        self.assertUsage(HDR + "a.md,,Operate-X,delete,\n")

    def test_bad_order_is_usage(self):
        self.add("a.md")
        self.assertUsage(HDR + "a.md,,Operate-X,move,first\n")

    def test_missing_header(self):
        self.add("a.md")
        self.assertUsage("repo_path,section,page,action\na.md,,Operate-X,move\n")

    def test_notes_column_with_commas(self):
        self.add("a.md")
        code, out = self.run_check(
            "repo_path,section,page,action,order,notes\n"
            'a.md,,Operate-X,move,,"has, commas"\n')
        self.assertEqual(code, 0, out)

    def test_space_and_comma_in_path(self):
        self.add("my docs/a b.md", "x,y.md")
        code, out = self.run_check(
            HDR + '"my docs/a b.md",,Operate-A,move,\n"x,y.md",,Operate-B,move,\n')
        self.assertEqual(code, 0, out)

    def test_missing_registry_is_usage(self):
        r = subprocess.run(
            [sys.executable, "-I", SCRIPT, os.path.join(self.repo, "none.csv"),
             "--repo", self.repo], capture_output=True, text=True)
        self.assertEqual(r.returncode, 64)

    def test_only_md_counted(self):
        self.add("README.md", "script.sh")
        code, out = self.run_check(HDR + "README.md,,,keep,\n")
        self.assertEqual(code, 0, out)


if __name__ == "__main__":
    unittest.main()
