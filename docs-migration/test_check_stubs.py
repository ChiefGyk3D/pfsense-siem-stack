"""Tests for check_stubs.py. Run: python3 -I -m unittest -v"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check_stubs.py")
HDR = "repo_path,section,page,action,order,notes\n"
REG = (HDR + "a.md,,Operate-Backups,move,1,\n"
       "b.md,,Install-Quick-Start,move,1,\n"
       "c.md,,,keep,1,\n")


def git(repo, *args):
    subprocess.run(["git", "-C", repo, *args], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class Stubs(unittest.TestCase):
    def setUp(self):
        self._td = tempfile.TemporaryDirectory()
        self.addCleanup(self._td.cleanup)
        self.repo = os.path.join(self._td.name, "repo")
        os.mkdir(self.repo)
        git(self.repo, "init", "-q")
        for p in ("a.md", "b.md", "c.md", "d.md"):
            with open(os.path.join(self.repo, p), "w") as fh:
                fh.write("x\n")
            git(self.repo, "add", p)
        self.reg = os.path.join(self._td.name, "registry.csv")
        self.stubs = os.path.join(self._td.name, "stubs.csv")

    def run_check(self, stub_text, reg_text=REG):
        with open(self.reg, "w", newline="") as fh:
            fh.write(reg_text)
        with open(self.stubs, "w", newline="") as fh:
            fh.write(stub_text)
        r = subprocess.run(
            [sys.executable, "-I", SCRIPT, self.stubs, "--registry", self.reg,
             "--repo", self.repo], capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def assertOffender(self, stub_text, cls, reg_text=REG):
        code, out = self.run_check(stub_text, reg_text)
        self.assertEqual(code, 2, out)
        self.assertTrue(any(l.startswith(cls + ": ") for l in out.splitlines()), out)

    def test_clean(self):
        code, out = self.run_check(
            HDR + "a.md,,Old-Name,stub,1,old wiki name; points to Operate-Backups\n"
            "b.md,,Other-Old,stub,1,points to Operate-Backups and Install-Quick-Start\n")
        self.assertEqual(code, 0, out)

    def test_duplicate_case_insensitive(self):
        self.assertOffender(
            HDR + "a.md,,Old-Name,stub,1,points to Operate-Backups\n"
            "b.md,,old-name,stub,1,points to Operate-Backups\n", "stub-duplicate")

    def test_stub_equals_real_page(self):
        self.assertOffender(
            HDR + "a.md,,operate-backups,stub,1,points to Operate-Backups\n",
            "stub-is-real-page")

    def test_untracked_repo_path(self):
        self.assertOffender(
            HDR + "nope.md,,Old-Name,stub,1,points to Operate-Backups\n",
            "stub-untracked")

    def test_target_page_missing(self):
        self.assertOffender(
            HDR + "a.md,,Old-Name,stub,1,points to Operate-Nothing\n", "stub-target")

    def test_no_target_in_notes(self):
        self.assertOffender(
            HDR + "a.md,,Old-Name,stub,1,old wiki name for one release\n", "stub-target")

    def test_one_bad_target_among_good(self):
        self.assertOffender(
            HDR + "a.md,,Old-Name,stub,1,points to Operate-Backups and Operate-Nothing\n",
            "stub-target")

    def test_repo_file_target(self):
        code, out = self.run_check(
            HDR + "c.md,,Old-Name,stub,1,points to repo file c.md\n")
        self.assertEqual(code, 0, out)
        self.assertOffender(
            HDR + "c.md,,Old-Name,stub,1,points to repo file zzz.md\n", "stub-target")

    def test_non_stub_action_offends(self):
        self.assertOffender(
            HDR + "a.md,,Old-Name,move,1,points to Operate-Backups\n", "stub-action")

    def test_malformed_is_usage(self):
        code, out = self.run_check("nonsense\n")
        self.assertEqual(code, 64, out)


if __name__ == "__main__":
    unittest.main()
