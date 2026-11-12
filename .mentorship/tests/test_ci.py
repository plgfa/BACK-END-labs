"""Regression tests; no assignment answers or student data are distributed."""
import contextlib
import copy
import importlib.util
import io
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

PACKAGE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("mentorship_ci", PACKAGE / ".mentorship/ci/ci.py")
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


def seal(root):
    manifest = {p.relative_to(root).as_posix(): ci.digest(p)
                for p in root.rglob("*") if p.is_file() and
                ci.controlled(p.relative_to(root).as_posix()) and
                p.relative_to(root).as_posix() != ".mentorship/bundle.json" and
                "__pycache__" not in p.parts}
    (root / ".mentorship/bundle.json").write_text(
        json.dumps({"version": "1.3.1", "files": manifest}, indent=2) + "\n", encoding="utf-8", newline="\n")


class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        for name in (".mentorship", ".semgrep", ".github"):
            shutil.copytree(PACKAGE / name, self.root / name,
                            ignore=shutil.ignore_patterns("__pycache__"))
        shutil.copyfile(PACKAGE / ".semgrepignore", self.root / ".semgrepignore")
        for name in ci.REQUIRED:
            path = self.root / name
            if not path.exists():
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("# Baseline\n", encoding="utf-8", newline="\n")
        seal(self.root)
        self.run_git("init", "-q")
        self.run_git("config", "user.email", "ci@example.invalid")
        self.run_git("config", "user.name", "CI regression")
        self.commit()
        sha = ci.git(self.root, "rev-parse", "HEAD").strip()
        self.context = {"pr": {"number": 1, "title": "[REPO] Integrate mentorship checks",
            "body": self.body("REPO", "REPO", sha), "user": {"login": "student"},
            "requested_reviewers": [{"login": "exc3pt1ongit"}], "assignees": [{"login": "student"}],
            "head": {"sha": sha, "ref": "chore/integrate-ci", "repo": {"full_name": "student/mentorship-labs"}},
            "base": {"sha": sha, "repo": {"full_name": "student/mentorship-labs"}},
            "html_url": "https://github.com/student/mentorship-labs/pull/1"},
            "reviews": [], "files": [{"filename": ".mentorship/config.json", "status": "added"}]}
        self.config = ci.load(self.root / ".mentorship/config.json")

    def tearDown(self):
        self.temp.cleanup()

    def run_git(self, *args):
        subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True)

    def commit(self):
        self.run_git("add", "-f", ".")
        self.run_git("commit", "--allow-empty", "-qm", "test fixture")

    @staticmethod
    def body(task, ref, sha):
        return ("## Assignment\n- Task ID: " + task +
            "\n- Assignment reference and revision, if provided: " + ref +
            "\n- AI policy: FORBIDDEN\n\n"
            "## Changes\nScoped work.\n\n## Verification\nExpected outcome: PASS. Actual outcome: PASS.\n\n"
            "## Known limitations and questions\nNone.\n\n## References and AI usage\nNo AI used.\n\n"
            "## Self-review\n- [x] I reviewed the diff.\n")

    def report(self, action, *args):
        report = ci.Report("Test", self.context["pr"]["head"]["sha"])
        action(*args, report)
        return report

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))
        self.run_git("add", "-f", name)

    def metadata(self, context=None):
        report = ci.Report("Test")
        ci.metadata(context or self.context, self.config, report,
                    self.context["pr"]["head"]["sha"])
        return report

    def test_metadata_valid(self):
        self.assertFalse(self.metadata().failed)

    def test_pr_reporter_has_pull_request_write_permission(self):
        workflow = (PACKAGE / ".github/workflows/mentorship-ci.yml").read_text(encoding="utf-8")
        reporter = workflow.split("\n  report:\n", 1)[1]
        permission = re.search(r"(?m)^      pull-requests: (\w+)$", reporter)
        self.assertIsNotNone(permission)
        self.assertEqual("write", permission.group(1))
        self.assertNotIn("uses: actions/checkout", reporter)

    def test_setup_runs_before_read_only_analysis(self):
        workflow = (PACKAGE / ".github/workflows/mentorship-metadata.yml").read_text(encoding="utf-8")
        prepare = workflow.split("\n  prepare:\n", 1)[1].split("\n  metadata:\n", 1)[0]
        self.assertIn("pull-requests: write", prepare)
        self.assertNotIn("uses: actions/checkout", prepare)
        self.assertIn("needs: [prepare]", workflow)
        workflow = (PACKAGE / ".github/workflows/mentorship-ci.yml").read_text(encoding="utf-8")
        for name, following in (("standards", "semgrep"), ("semgrep", "report")):
            job = workflow.split("\n  " + name + ":\n", 1)[1].split("\n  " + following + ":\n", 1)[0]
            self.assertNotIn("needs: [prepare]", job)
            self.assertNotIn("pull-requests: write", job)

    def test_unknown_task(self):
        self.context["pr"]["title"] = "[CS-SETUP-99] Complete environment passport"
        self.assertTrue(self.metadata().failed)

    def test_mismatched_body_id(self):
        self.context["pr"]["body"] = self.context["pr"]["body"].replace("Task ID: REPO", "Task ID: WRONG")
        self.assertTrue(self.metadata().failed)

    def test_wrong_assignment_reference(self):
        self.context["pr"]["body"] = self.context["pr"]["body"].replace("provided: REPO", "provided: LESSON")
        self.assertTrue(self.metadata().failed)

    def test_wrong_ai_policy(self):
        self.context["pr"]["body"] = self.context["pr"]["body"].replace("FORBIDDEN", "FORBIDEN")
        self.assertTrue(self.metadata().failed)

    def test_manual_submitted_revision_is_optional(self):
        self.assertNotIn("Submitted revision", self.context["pr"]["body"])
        self.assertFalse(self.metadata().failed)

    def test_legacy_submitted_revision_is_ignored(self):
        self.context["pr"]["body"] += "\n- Submitted revision: REPLACE_WITH_FULL_HEAD_SHA\n"
        self.assertFalse(self.metadata().failed)

    def test_wrong_checkout_revision(self):
        report = ci.Report("Test")
        ci.metadata(self.context, self.config, report, "0" * 40)
        self.assertTrue(report.failed)

    def test_no_reviewer(self):
        self.context["pr"]["requested_reviewers"] = []
        self.assertTrue(self.metadata().failed)

    def test_draft_defers_reviewer_without_failing(self):
        self.context["pr"]["draft"] = True
        self.context["pr"]["requested_reviewers"] = []
        report = self.metadata()
        self.assertFalse(report.failed)
        reviewer = next(item for item in report.data["checks"] if item["name"] == "Mentor reviewer")
        self.assertEqual("Pending", reviewer["status"])

    def test_review_of_current_revision_counts(self):
        self.context["pr"]["requested_reviewers"] = []
        self.context["reviews"] = [{"user": {"login": "exc3pt1ongit"},
            "state": "CHANGES_REQUESTED", "commit_id": self.context["pr"]["head"]["sha"]}]
        self.assertFalse(self.metadata().failed)

    def test_old_review_does_not_count(self):
        self.context["pr"]["requested_reviewers"] = []
        self.context["reviews"] = [{"user": {"login": "exc3pt1ongit"},
            "state": "APPROVED", "commit_id": "0" * 40}]
        self.assertTrue(self.metadata().failed)

    def test_dismissed_review_does_not_count(self):
        self.context["pr"]["requested_reviewers"] = []
        self.context["reviews"] = [{"user": {"login": "exc3pt1ongit"},
            "state": "DISMISSED", "commit_id": self.context["pr"]["head"]["sha"]}]
        self.assertTrue(self.metadata().failed)

    def test_missing_assignee(self):
        self.context["pr"]["assignees"] = []
        self.assertTrue(self.metadata().failed)

    def test_wrong_assignee(self):
        self.context["pr"]["assignees"] = [{"login": "someone-else"}]
        self.assertTrue(self.metadata().failed)

    def test_unchecked_self_review(self):
        self.context["pr"]["body"] += "- [ ] Not checked.\n"
        self.assertFalse(self.metadata().failed)

    def test_malformed_checked_box(self):
        self.context["pr"]["body"] += "- [ x] Invalid check.\n"
        self.assertFalse(self.metadata().failed)

    def test_self_review_section_is_optional(self):
        self.context["pr"]["body"] = self.context["pr"]["body"].split("## Self-review", 1)[0]
        self.assertFalse(self.metadata().failed)

    def test_branch_format(self):
        self.context["pr"]["head"]["ref"] = "Feat/wrong_name"
        self.assertTrue(self.metadata().failed)

    def test_documented_branch_exception(self):
        self.context["pr"]["head"]["ref"] = "legacy"
        self.config["branch_exceptions"] = {"student/mentorship-labs#1": {
            "branch": "legacy", "reason": "Preserve an existing reviewed PR."}}
        self.assertFalse(self.metadata().failed)

    def test_policy_approval_can_be_revoked(self):
        sha = self.context["pr"]["head"]["sha"]
        self.context["reviews"] = [
            {"user": {"login": "exc3pt1ongit"}, "state": state, "commit_id": sha}
            for state in ("APPROVED", "CHANGES_REQUESTED")]
        self.assertFalse(ci.has_review(self.context, {"exc3pt1ongit"}, True))

    def test_maintenance_cannot_hide_lab_change(self):
        self.context["files"] = [{"filename": "assignments/x/source.py"}]
        self.assertTrue(self.metadata().failed)

    def test_good_format(self):
        self.assertFalse(self.report(ci.formatting, self.root, ci.files(self.root)).failed)

    def test_missing_newline(self):
        self.write("example.json", "{}")
        self.assertTrue(self.report(ci.formatting, self.root, ci.files(self.root)).failed)

    def test_crlf_rejected_for_source(self):
        self.write("example.py", "print(1)\r\n")
        self.assertTrue(self.report(ci.formatting, self.root, ci.files(self.root)).failed)

    def test_bom_rejected(self):
        self.write("example.md", b"\xef\xbb\xbftext\n")
        self.assertTrue(self.report(ci.formatting, self.root, ci.files(self.root)).failed)

    def test_non_utf8_rejected(self):
        self.write("example.txt", b"\xff\n")
        self.assertTrue(self.report(ci.formatting, self.root, ci.files(self.root)).failed)

    def test_crlf_allowed_for_cmd(self):
        self.write("example.cmd", "@echo off\r\n")
        self.assertFalse(self.report(ci.formatting, self.root, ci.files(self.root)).failed)

    def test_env_rejected(self):
        self.write(".env", "SYNTHETIC=1\n")
        self.assertTrue(self.report(ci.hygiene, self.root, ci.files(self.root)).failed)

    def test_example_env_allowed(self):
        self.write(".env.example", "SYNTHETIC=\n")
        self.assertFalse(self.report(ci.hygiene, self.root, ci.files(self.root)).failed)

    def test_uppercase_env_rejected(self):
        self.write(".ENV", "SYNTHETIC=1\n")
        self.assertTrue(self.report(ci.hygiene, self.root, ci.files(self.root)).failed)

    def test_dependency_directory_rejected(self):
        self.write("node_modules/example/index.js", "export {};\n")
        self.assertTrue(self.report(ci.hygiene, self.root, ci.files(self.root)).failed)

    def test_compiled_binary_rejected(self):
        self.write("app.dll", b"\x00test")
        self.assertTrue(self.report(ci.hygiene, self.root, ci.files(self.root)).failed)

    def test_good_local_link(self):
        self.write("README.md", "[Standard](docs/engineering-standards.md)\n")
        self.assertFalse(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_broken_link(self):
        self.write("README.md", "[Missing](missing.md)\n")
        self.assertTrue(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_bad_markdown_parentheses(self):
        self.context["pr"]["body"] += "[Passport]((https://github.com/example))\n"
        self.assertTrue(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_nonexistent_branch_link(self):
        self.write("README.md", "[Source](https://github.com/student/mentorship-labs/blob/not-a-branch/README.md)\n")
        self.assertTrue(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_branch_with_slashes_in_link(self):
        self.write("README.md", "[Source](https://github.com/student/mentorship-labs/blob/chore/integrate-ci/README.md)\n")
        self.assertFalse(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_reference_link(self):
        self.write("README.md", "[Docs][d]\n\n[d]: missing.md\n")
        self.assertTrue(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_code_block_is_not_a_link(self):
        fence = chr(96) * 3
        self.write("README.md", fence + "md\n[Example](missing.md)\n" + fence + "\n")
        self.assertFalse(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_parent_relative_link(self):
        self.write("docs/test.md", "[Root](../README.md)\n")
        self.assertFalse(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_escaping_link(self):
        self.write("README.md", "[Outside](../../outside.md)\n")
        self.assertTrue(self.report(ci.links, self.root, ci.files(self.root), self.context).failed)

    def test_safe_path_rejects_traversal(self):
        with self.assertRaises(ValueError):
            ci.safe(self.root, "../outside")

    def test_policy_manifest_integrity(self):
        self.assertEqual([], ci.bundle(self.root))

    def test_missing_control_file(self):
        (self.root / ".semgrep/README.md").unlink()
        self.assertTrue(ci.bundle(self.root))

    def test_modified_control_file(self):
        self.write(".semgrep/README.md", "rules: []\n")
        self.assertTrue(ci.bundle(self.root))

    def test_self_resealed_policy_requires_approval(self):
        baseline = Path(self.temp.name) / "baseline"
        shutil.copytree(self.root, baseline)
        self.write(".semgrep/README.md", "rules: []\n")
        seal(self.root)
        self.run_git("add", "-f", ".")
        report = ci.Report("Policy")
        ci.policy(self.root, baseline, self.context, report)
        self.assertTrue(report.failed)

    def test_additional_workflow_requires_mentor_review(self):
        baseline = Path(self.temp.name) / "baseline"
        shutil.copytree(self.root, baseline)
        self.write(".github/workflows/other.yml", "name: Other\n")
        report = ci.Report("Policy")
        ci.policy(self.root, baseline, self.context, report)
        self.assertTrue(report.failed)

    def test_existing_other_workflow_is_preserved(self):
        self.write(".github/workflows/other.yml", "name: Existing\n")
        baseline = Path(self.temp.name) / "baseline"
        shutil.copytree(self.root, baseline)
        report = ci.Report("Policy")
        ci.policy(self.root, baseline, self.context, report)
        self.assertFalse(report.failed)

    def test_approved_policy_update(self):
        baseline = Path(self.temp.name) / "baseline"
        shutil.copytree(self.root, baseline)
        self.write(".semgrepignore", "# Reviewed policy adjustment.\n")
        seal(self.root)
        self.run_git("add", "-f", ".")
        self.context["reviews"] = [{"user": {"login": "exc3pt1ongit"}, "state": "APPROVED",
                                   "commit_id": self.context["pr"]["head"]["sha"]}]
        report = ci.Report("Policy")
        ci.policy(self.root, baseline, self.context, report)
        self.assertFalse(report.failed)

    def test_bootstrap_requires_maintenance_pr(self):
        self.context["pr"]["title"] = "[CS-SETUP-02] Complete the environment passport"
        report = ci.Report("Policy")
        ci.policy(self.root, None, self.context, report)
        self.assertTrue(report.failed)

    def test_whole_maintenance_submission(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, ci.standards(self.root, None, self.context))

    def test_source_checks_do_not_repeat_mutable_metadata(self):
        self.context["pr"]["assignees"] = []
        self.context["pr"]["requested_reviewers"] = []
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, ci.standards(self.root, None, self.context))
        self.assertTrue(self.metadata().failed)

    def run_metadata_scope(self):
        spec = importlib.util.spec_from_file_location("metadata_runner", PACKAGE / ".mentorship/ci/metadata.py")
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        context = Path(self.temp.name) / "context.json"
        context.write_text(json.dumps(self.context), encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            return runner.check(self.root, Path(self.temp.name) / "empty-base", context, self.root)

    def test_metadata_scope_does_not_scan_source(self):
        self.write("bad.py", b"print(1)\r\n")
        self.assertEqual(0, self.run_metadata_scope())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(1, ci.standards(self.root, None, self.context))

    def test_metadata_scope_enforces_policy(self):
        self.write(".semgrep/README.md", "Tampered policy.\n")
        self.assertEqual(1, self.run_metadata_scope())

    def test_split_workflow_triggers_and_reporting_lock(self):
        code = (PACKAGE / ".github/workflows/mentorship-ci.yml").read_text(encoding="utf-8")
        meta = (PACKAGE / ".github/workflows/mentorship-metadata.yml").read_text(encoding="utf-8")
        self.assertIn("types: [opened, reopened, synchronize]", code)
        self.assertNotIn("pull_request_review:", code)
        self.assertIn("types: [submitted, dismissed]", meta)
        self.assertNotIn("  semgrep:\n", meta)
        self.assertNotIn("  standards:\n", meta)
        self.assertIn("group: mentorship-code-", code)
        self.assertIn("group: mentorship-metadata-", meta)
        for workflow in (code, meta):
            report = workflow.split("\n  report:\n", 1)[1]
            self.assertIn("group: mentorship-report-", report)
            self.assertIn("cancel-in-progress: false", report)
            self.assertIn("checks: read", report)
            self.assertNotIn("uses: actions/checkout", report)
        self.assertEqual(code.split("\n  report:\n", 1)[1].split("          script: |", 1)[1],
                         meta.split("\n  report:\n", 1)[1].split("          script: |", 1)[1])
        code_jobs = re.findall(r"(?m)^    name: (.+)$", code)
        meta_jobs = re.findall(r"(?m)^    name: (.+)$", meta)
        self.assertFalse(set(code_jobs) & set(meta_jobs))

    def test_fork_submission_rejected(self):
        self.context["pr"]["head"]["repo"]["full_name"] = "other/mentorship-labs"
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(1, ci.standards(self.root, None, self.context))

    def test_report_marks_failures(self):
        report = ci.Report("Example")
        report.add("Broken", ["file.py:2: expected correction"])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(1, report.finish())

    def test_report_na_not_a_failure(self):
        report = ci.Report("Example")
        report.add("No code", status="Not applicable", detail="No source.")
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, report.finish())

    def test_api_pagination(self):
        with patch.object(ci, "api", side_effect=[[{}] * 100, [{"id": 101}]]) as api:
            self.assertEqual(101, len(ci.paged("/test", "synthetic")))
            self.assertIn("page=2", api.call_args[0][0])

    def test_api_rejects_absolute_endpoint(self):
        with self.assertRaises(ValueError):
            ci.api("https://example.invalid/", "synthetic")

    def test_fetch_does_not_write_token(self):
        event = Path(self.temp.name) / "event.json"
        output = Path(self.temp.name) / "context.json"
        event.write_text('{"pull_request":{"number":1}}', encoding="utf-8", newline="\n")
        with patch.dict(os.environ, {"GH_TOKEN": "SYNTHETIC_TOKEN", "GITHUB_REPOSITORY": "student/mentorship-labs"}):
            with patch.object(ci, "api", return_value=self.context["pr"]), patch.object(ci, "paged", return_value=[]):
                ci.fetch(event, output)
        self.assertNotIn("SYNTHETIC_TOKEN", output.read_text(encoding="utf-8"))

    def test_untrusted_checker_is_not_executed(self):
        lab = self.root / "lab"
        lab.mkdir()
        (lab / "check_passport.sh").write_text("echo forged\n", encoding="utf-8", newline="\n")
        report = ci.Report("Checker")
        with patch.object(ci.subprocess, "run") as run:
            ci.checker(lab, {"checker": "dotnet-passport"}, self.root, report)
            run.assert_not_called()
        self.assertTrue(report.failed)

    def prepare_lab(self):
        task = "CS-SETUP-02"
        rel = "assignments/csharp-setup/cs-setup-02-environment-passport"
        self.context["pr"]["title"] = "[CS-SETUP-02] Complete the environment passport"
        self.context["pr"]["head"]["ref"] = "feat/cs-setup-02-environment-passport"
        self.context["pr"]["body"] = self.body(task, "ASG.LANG.CS.SETUP.02", self.context["pr"]["head"]["sha"])
        text = ("# Environment passport\n- Task ID: CS-SETUP-02\n"
            "- Assignment reference and revision, if provided: ASG.LANG.CS.SETUP.02\n"
            "- AI policy: FORBIDDEN\n\n## Prerequisites\nGit Bash.\n\n"
            "## Verification\nWorking directory: " + rel + "\nExpected outcome: PASS.\nActual outcome: PASS.\n"
            "## Known Limitations\nNone.\n## References and AI Usage\nCourse starter; no AI used.\n")
        for name in self.config["assignments"][task]["required_files"]:
            self.write(rel + "/" + name, "{}\n" if name.endswith(".json") else "Fixture\n")
        self.write(rel + "/README.md", text)
        self.write("README.md", "| CS-SETUP-02 | Passport | [Source](" + rel + ") | " + self.context["pr"]["html_url"] + " |\n")
        self.context["files"] = [{"filename": rel + "/README.md", "status": "added"}]
        return self.root / rel

    def test_catalogue_distinguishes_lesson_and_homework(self):
        self.assertEqual("LANG.CS.SETUP.L01", self.config["assignments"]["CS-SETUP-02"]["lesson"])
        self.assertEqual("LANG.CS.SETUP.L04", self.config["assignments"]["CS-SETUP-01"]["lesson"])
        self.assertEqual(len(self.config["assignments"]), len({s["assignment_ref"] for s in self.config["assignments"].values()}))

    def test_metadata_accepts_matching_lab_folder(self):
        self.prepare_lab()
        self.assertFalse(self.metadata().failed)

    def test_metadata_rejects_task_id_of_another_lab(self):
        self.prepare_lab()
        self.context["files"] = [{"filename": "assignments/csharp-basics/cs-basics-01-ticketcalc/Program.cs",
                                  "status": "added"}]
        report = self.metadata()
        self.assertTrue(report.failed)
        self.assertIn("does not match the changed lab folder", json.dumps(report.__dict__, default=str))

    def test_metadata_ignores_removed_lab_files(self):
        self.prepare_lab()
        self.context["files"].append({"filename": "assignments/csharp-basics/cs-basics-01-old/Program.cs",
                                      "status": "removed"})
        self.assertFalse(self.metadata().failed)

    def test_unknown_task_warns_against_changing_id(self):
        self.context["pr"]["title"] = "[CS-SETUP-99] Complete environment passport"
        self.assertIn("Do not change the Task ID", json.dumps(self.metadata().__dict__, default=str))

    def test_catalogue_registers_executed_language_homework(self):
        for task, ref in {"CS-BASICS-01": "ASG.LANG.CS.BASICS.01", "JAVA-COLL-01": "ASG.LANG.JAVA.COLL.01",
                          "JS-BASICS-01": "ASG.LANG.JS.BASICS.01", "PY-BASICS-01": "ASG.LANG.PY.BASICS.01"}.items():
            self.assertEqual(ref, self.config["assignments"][task]["assignment_ref"])

    def test_valid_lab_structure(self):
        expected = self.prepare_lab()
        report = ci.Report("Lab")
        found = ci.lab_check(self.root, self.context, self.config, "CS-SETUP-02", False, report)
        self.assertEqual(expected, found)
        self.assertFalse(report.failed)

    def test_wrong_lab_id(self):
        lab = self.prepare_lab()
        self.write(lab.relative_to(self.root).as_posix() + "/README.md", "# Wrong\n- Task ID: LANG.CS.SETUP.L01\n")
        report = ci.Report("Lab")
        ci.lab_check(self.root, self.context, self.config, "CS-SETUP-02", False, report)
        self.assertTrue(report.failed)

    def test_missing_required_asset(self):
        lab = self.prepare_lab()
        (lab / "apps/Report8.runtimeconfig.json").unlink()
        report = ci.Report("Lab")
        ci.lab_check(self.root, self.context, self.config, "CS-SETUP-02", False, report)
        self.assertTrue(report.failed)

    def test_wrong_working_directory(self):
        lab = self.prepare_lab()
        text = (lab / "README.md").read_text(encoding="utf-8").replace("Working directory: assignments/", "Working directory: wrong/assignments/")
        self.write(lab.relative_to(self.root).as_posix() + "/README.md", text.replace("cs-setup-02-environment-passport", "cs-setup-02-enviroment-passport"))
        report = ci.Report("Lab")
        ci.lab_check(self.root, self.context, self.config, "CS-SETUP-02", False, report)
        self.assertTrue(report.failed)

    def test_working_directory_cannot_hide_wrong_prefix(self):
        lab = self.prepare_lab()
        text = (lab / "README.md").read_text(encoding="utf-8").replace("Working directory: assignments/", "Working directory: wrong/assignments/")
        self.write(lab.relative_to(self.root).as_posix() + "/README.md", text)
        report = ci.Report("Lab")
        ci.lab_check(self.root, self.context, self.config, "CS-SETUP-02", False, report)
        self.assertTrue(report.failed)

    def test_working_directory_accepts_dot_prefix(self):
        lab = self.prepare_lab()
        text = (lab / "README.md").read_text(encoding="utf-8").replace("Working directory: assignments/", "Working directory: ./assignments/")
        self.write(lab.relative_to(self.root).as_posix() + "/README.md", text)
        report = ci.Report("Lab")
        ci.lab_check(self.root, self.context, self.config, "CS-SETUP-02", False, report)
        self.assertFalse(report.failed)

    def test_unrelated_lab_change(self):
        self.prepare_lab()
        self.context["files"].append({"filename": "assignments/other/source.py", "status": "modified"})
        report = ci.Report("Lab")
        ci.lab_check(self.root, self.context, self.config, "CS-SETUP-02", False, report)
        self.assertTrue(report.failed)

    def test_checker_uses_trusted_script_without_token(self):
        lab = self.prepare_lab()
        shutil.copyfile(self.root / ".mentorship/checkers/check_passport.sh", lab / "check_passport.sh")
        report = ci.Report("Checker")
        result = subprocess.CompletedProcess([], 0, "PASS\n", "")
        with patch.dict(os.environ, {"GH_TOKEN": "SYNTHETIC_SECRET"}):
            with patch.object(ci.subprocess, "run", return_value=result) as run:
                ci.checker(lab, self.config["assignments"]["CS-SETUP-02"], self.root, report)
                self.assertNotIn("GH_TOKEN", run.call_args.kwargs["env"])
                self.assertIn(".mentorship/checkers", run.call_args.args[0][1])
        self.assertFalse(report.failed)

    def test_checker_timeout_fails(self):
        lab = self.prepare_lab()
        shutil.copyfile(self.root / ".mentorship/checkers/check_passport.sh", lab / "check_passport.sh")
        report = ci.Report("Checker")
        with patch.object(ci.subprocess, "run", side_effect=subprocess.TimeoutExpired("bash", 30)):
            ci.checker(lab, self.config["assignments"]["CS-SETUP-02"], self.root, report)
        self.assertTrue(report.failed)

    def test_stale_recorded_checker_output(self):
        lab = self.prepare_lab()
        shutil.copyfile(self.root / ".mentorship/checkers/check_passport.sh", lab / "check_passport.sh")
        self.write(lab.relative_to(self.root).as_posix() + "/passport.md", "$ bash check_passport.sh\nPASS  C6 old result\nРЕЗУЛЬТАТ: PASS\n")
        report = ci.Report("Checker")
        result = subprocess.CompletedProcess([], 0, "PASS  C6 new result\n\nРЕЗУЛЬТАТ: PASS\n", "")
        with patch.object(ci.subprocess, "run", return_value=result):
            ci.checker(lab, self.config["assignments"]["CS-SETUP-02"], self.root, report)
        self.assertTrue(report.failed)


if __name__ == "__main__":
    unittest.main()
