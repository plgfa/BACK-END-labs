#!/usr/bin/env python3
"""Mentorship CI 1.3.0; Python 3.12+, standard library only."""
import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath

CONTROL = (".mentorship/", ".semgrep/", ".semgrepignore", ".github/workflows/mentorship-ci.yml", ".github/workflows/mentorship-metadata.yml")
REQUIRED = ("README.md", "CONTRIBUTING.md", ".editorconfig", ".gitattributes", ".gitignore",
            "docs/engineering-standards.md", ".github/pull_request_template.md")
CODE = {".py", ".cs", ".java", ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".go"}
OTHER_CODE = {".c", ".h", ".cc", ".cpp", ".hpp", ".rs", ".rb", ".php", ".kt", ".kts",
              ".scala", ".swift", ".sql", ".ps1", ".sh"}
TEXT = CODE | OTHER_CODE | {".md", ".json", ".yml", ".yaml", ".toml", ".xml", ".txt",
                           ".csv", ".html", ".css", ".scss", ".ini", ".bat", ".cmd"}
GENERATED = {"node_modules", ".venv", "venv", "__pycache__", ".pytest_cache",
             ".mypy_cache", ".next", "bin", "obj", "target", "dist", ".idea"}
BAD_SUFFIX = {".pyc", ".class", ".exe", ".pdb", ".dll", ".log"}


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def digest(path, normalize=False):
    data = Path(path).read_bytes()
    return hashlib.sha256(data.replace(b"\r\n", b"\n") if normalize else data).hexdigest()


def git(root, *args):
    return subprocess.check_output(["git", "-c", "core.quotepath=false", "-c", "core.fsmonitor=false",
                                   "-c", "safe.directory=" + str(Path(root).resolve()), "-C", str(root),
                                   *args], stderr=subprocess.PIPE).decode("utf-8")


def files(root):
    return [p for p in git(root, "ls-files", "-z").split("\0") if p]


def controlled(name):
    return any(name == p or name.startswith(p) for p in CONTROL)


def safe(root, name):
    root, rel = Path(root).resolve(), PurePosixPath(name)
    if rel.is_absolute() or "\\" in name or ".." in rel.parts:
        raise ValueError("Unsafe path: " + name)
    candidate = root
    for part in rel.parts:
        candidate /= part
        if candidate.is_symlink():
            raise ValueError("Symlink is not accepted: " + name)
    if not candidate.resolve().is_relative_to(root):
        raise ValueError("Path escapes repository: " + name)
    return candidate


def field(text, name):
    match = re.search(r"(?im)^\s*(?:-\s*)?" + re.escape(name) + r"\s*:\s*([^\r\n]+)", text)
    return match.group(1).strip().strip(chr(96)) if match else ""


class Report:
    def __init__(self, name, sha=""):
        self.data = {"name": name, "sha": sha, "checks": [], "version": "1.3.0"}

    def add(self, name, failures=None, detail="", status=None):
        failures = failures or []
        self.data["checks"].append({"name": name, "status": status or
            ("Failed" if failures else "Passed"), "detail": detail[:5000],
            "errors": [str(x)[:1200] for x in failures[:20]]})

    @property
    def failed(self):
        return any(c["status"] == "Failed" for c in self.data["checks"])

    def finish(self, output=None):
        self.data["status"] = "Failed" if self.failed else "Passed"
        for c in self.data["checks"]:
            print(c["status"] + " | " + c["name"] + " | " + c["detail"])
            for error in c["errors"]:
                print("  " + error.replace("\n", " ").replace("\r", " "))
        if output:
            Path(output).write_text(json.dumps(self.data, indent=2) + "\n", encoding="utf-8")
        encoded = base64.b64encode(json.dumps(self.data).encode()).decode()
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
                out.write("report=" + encoded + "\n")
        return int(self.failed)


def api(endpoint, token):
    if not endpoint.startswith("/") or endpoint.startswith("//"):
        raise ValueError("API endpoint must be relative")
    request = urllib.request.Request(os.environ.get("GITHUB_API_URL", "https://api.github.com") +
        endpoint, headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "mentorship-ci/1.3.0"})
    with urllib.request.urlopen(request, timeout=25) as response:
        return json.load(response)


def paged(endpoint, token):
    answer = []
    for page in range(1, 101):
        batch = api(endpoint + "?per_page=100&page=" + str(page), token)
        answer.extend(batch)
        if len(batch) < 100:
            return answer
    raise ValueError("GitHub pagination limit reached")


def fetch(event_file, output):
    event = load(event_file)
    number = (event.get("pull_request") or {}).get("number") or (event.get("inputs") or {}).get("pr_number")
    if not str(number or "").isdigit():
        raise ValueError("Enter a valid PR number.")
    token = os.environ["GH_TOKEN"]
    prefix = "/repos/" + os.environ["GITHUB_REPOSITORY"] + "/pulls/" + str(number)
    pr = api(prefix, token)
    data = {"pr": pr, "reviews": paged(prefix + "/reviews", token), "files": paged(prefix + "/files", token)}
    Path(output).write_text(json.dumps(data) + "\n", encoding="utf-8")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            for key, value in {"number": number, "sha": pr["head"]["sha"], "base": pr["base"]["sha"],
                              "repository": pr["head"]["repo"]["full_name"]}.items():
                out.write(str(key) + "=" + str(value) + "\n")


def has_review(context, mentors, approved=False):
    current = [r for r in context.get("reviews", []) if
        r.get("commit_id") == context["pr"]["head"]["sha"] and
        r.get("user", {}).get("login", "").lower() in mentors]
    if not approved:
        return any(r.get("state") in {"APPROVED", "COMMENTED", "CHANGES_REQUESTED"} for r in current)
    decisions = {}
    for review in current:
        if review.get("state") in {"APPROVED", "CHANGES_REQUESTED", "DISMISSED"}:
            decisions[review["user"]["login"].lower()] = review["state"]
    return "APPROVED" in decisions.values() and "CHANGES_REQUESTED" not in decisions.values()


def bundle(root):
    manifest = safe(root, ".mentorship/bundle.json")
    if not manifest.is_file():
        return ["Missing .mentorship/bundle.json; install the complete package."]
    expected, failures = load(manifest)["files"], []
    actual = {p for p in files(root) if controlled(p) and p != ".mentorship/bundle.json"}
    if set(expected) != actual:
        failures.append("Control-file inventory differs from bundle.json.")
    for name, wanted in expected.items():
        path = safe(root, name)
        if not path.is_file() or digest(path) != wanted:
            failures.append(name + ": package checksum differs; ask mentor for the approved file.")
    return failures


def policy(root, baseline, context, report):
    baseline = Path(baseline) if baseline else None
    bootstrap = not baseline or not (baseline / ".mentorship/config.json").is_file()
    origin = Path(root) if bootstrap else baseline
    config = load(origin / ".mentorship/config.json")
    errors = bundle(root)
    if not bootstrap:
        paths = {p for p in files(root) + files(baseline) if controlled(p) or p.startswith(".github/workflows/")}
        changed = [p for p in sorted(paths) if not (Path(root) / p).is_file() or
            not (baseline / p).is_file() or digest(Path(root) / p) != digest(baseline / p)]
        if changed and not has_review(context, {u.lower() for u in config["mentors"]}, True):
            errors.append("CI policy changed without mentor APPROVED review of this head: " + ", ".join(changed[:8]))
        elif changed:
            origin, config = Path(root), load(Path(root) / ".mentorship/config.json")
    if bootstrap and not context["pr"].get("title", "").startswith("[REPO] "):
        errors.append("Install this package in a separate [REPO] integration PR first.")
    report.add("CI package and policy", errors, "Bootstrap: mentor reviews initial installation."
               if bootstrap else "Compared with base-branch policy.")
    return config, origin


def metadata(context, config, report, actual):
    pr = context["pr"]
    title, body = pr.get("title") or "", pr.get("body") or ""
    maintenance = title.startswith("[REPO] ")
    match = re.fullmatch(r"\[([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*)\] ([A-Z][^\r\n]{7,})", title)
    task, errors = match.group(1) if match else "", []
    if not match:
        errors.append("PR title: use [TASK-ID] Imperative description, or [REPO] for maintenance.")
    if not maintenance and task not in config["assignments"]:
        errors.append("Unknown Task ID " + task + "; ask mentor to register the homework.")
    branch = pr["head"]["ref"]
    branch_prefix = r"(?:feat|fix|refactor|test|docs|chore)/"
    branch_pattern = branch_prefix + ("" if maintenance else re.escape(task.lower()) + "-") + r"[a-z0-9]+(?:-[a-z0-9]+)*"
    exception = config.get("branch_exceptions", {}).get(pr["base"]["repo"]["full_name"] + "#" + str(pr["number"]), {})
    if not re.fullmatch(branch_pattern, branch) and not (exception.get("branch") == branch and exception.get("reason")):
        errors.append("Branch: use <type>/" + ("<description>" if maintenance else task.lower() + "-<description>") +
                      ". Existing PRs need a mentor-recorded branch exception; do not close the PR to rename it.")
    if field(body, "Task ID") != task:
        errors.append("PR description: Task ID must match the title.")
    for heading in ("Assignment", "Changes", "Verification", "Known limitations and questions",
                    "References and AI usage"):
        if not re.search(r"(?im)^##\s+" + re.escape(heading) + r"\s*$", body):
            errors.append("PR description: missing ## " + heading)
    spec = config["assignments"].get(task, {})
    ref, ai = ("REPO", "FORBIDDEN") if maintenance else (spec.get("assignment_ref"), spec.get("ai_policy"))
    if ref and field(body, "Assignment reference and revision, if provided") != ref:
        errors.append("PR description: assignment reference must be " + ref + ".")
    if ai and field(body, "AI policy") != ai:
        errors.append("PR description: AI policy must be " + ai + ".")
    if maintenance and any(p["filename"].startswith("assignments/") for p in context["files"]):
        errors.append("[REPO] maintenance cannot contain assignment changes.")
    report.add("PR metadata and assignment ID", errors)
    errors, sha = [], pr["head"]["sha"]
    if actual != sha:
        errors.append("Head changed after checkout; rerun for the latest head.")
    report.add("Checked-out PR revision", errors)
    mentors = {u.lower() for u in config["mentors"]}
    requested = {u["login"].lower() for u in pr.get("requested_reviewers", [])}
    if pr.get("draft"):
        report.add("Mentor reviewer", status="Pending", detail="Draft PR: review request is deferred until ready for review.")
    else:
        report.add("Mentor reviewer", [] if requested & mentors or has_review(context, mentors) else [
            "Request review from " + ", ".join(config["mentors"]) + " or obtain their review of this head."])
    author = pr["user"]["login"]
    report.add("Author assignee", [] if author.lower() in {u["login"].lower() for u in pr.get("assignees", [])}
               else ["Assign the PR to its author (" + author + ")."])
    return task, maintenance


def formatting(root, tracked, report):
    errors = []
    for name in tracked:
        path = safe(root, name)
        if name.startswith(".mentorship/checkers/") or not path.is_file():
            continue
        if path.suffix.lower() not in TEXT and path.name not in {
                ".editorconfig", ".gitattributes", ".gitignore", ".semgrepignore", "Dockerfile"}:
            continue
        data = path.read_bytes()
        try:
            data.decode("utf-8")
        except UnicodeDecodeError:
            errors.append(name + ": use UTF-8.")
            continue
        if data.startswith(b"\xef\xbb\xbf"):
            errors.append(name + ": remove UTF-8 BOM.")
        if data and not data.endswith(b"\n"):
            errors.append(name + ": add a final newline.")
        if path.suffix.lower() in {".bat", ".cmd"}:
            if b"\n" in data.replace(b"\r\n", b"") or b"\r" in data.replace(b"\r\n", b""):
                errors.append(name + ": use CRLF for .bat/.cmd.")
        elif b"\r" in data:
            errors.append(name + ": use LF.")
    report.add("Text formatting", errors, "Tracked text; upstream checker preserved verbatim.")


def hygiene(root, tracked, report):
    errors = []
    for name in tracked:
        path = PurePosixPath(name)
        basename = path.name.lower()
        env = basename == ".env" or basename.startswith(".env.")
        example = basename == ".env.example" or basename.startswith(".env.") and basename.endswith(".example")
        if env and not example:
            errors.append(name + ": actual environment file must not be tracked.")
        elif {p.lower() for p in path.parts[:-1]} & GENERATED or path.suffix.lower() in BAD_SUFFIX:
            errors.append(name + ": generated/local file must not be tracked.")
        if basename in {"id_rsa", "id_ed25519", "terraform.tfstate"} or basename.endswith(".tfstate.backup"):
            errors.append(name + ": sensitive key/state must not be tracked.")
        candidate = safe(root, name)
        if candidate.is_file() and candidate.stat().st_size > 5 * 1024 * 1024:
            errors.append(name + ": exceeds 5 MiB; agree an exception with the mentor.")
    report.add("Repository hygiene", errors, "Known paths/filenames; not a complete secret scanner.")


def markdown_links(text):
    fence = chr(96) * 3
    clean = re.sub(r"(?ms)^" + fence + r"[^\n]*\n.*?^" + fence + r"[ \t]*$",
                   lambda m: "\n" * m.group().count("\n"), text)
    clean = re.sub(chr(96) + r"[^" + chr(96) + r"\n]+" + chr(96), "", clean)
    for m in re.finditer(r"!?\[[^\]\n]*\]\((<?[^\s\n]+>?)(?:\s+\"[^\"]*\")?\)", clean):
        yield m.group(1).strip("<>"), clean[:m.start()].count("\n") + 1
    for m in re.finditer(r"(?m)^\s*\[[^\]]+\]:\s*(<?[^\s\n]+>?)", clean):
        yield m.group(1).strip("<>"), clean[:m.start()].count("\n") + 1


def links(root, tracked, context, report):
    pr, errors = context["pr"], []
    sources = [(p, safe(root, p).read_text(encoding="utf-8")) for p in tracked if p.endswith(".md")]
    sources.append(("PR description", pr.get("body") or ""))
    repo, headref, sha = pr["base"]["repo"]["full_name"], pr["head"]["ref"], pr["head"]["sha"]
    for name, text in sources:
        for target, line in markdown_links(text):
            label, url = name + ":" + str(line), urllib.parse.urlsplit(target)
            if target.startswith("("):
                errors.append(label + ": malformed link; remove extra parentheses.")
                continue
            if url.scheme or url.netloc:
                prefix = "/" + repo + "/"
                if url.netloc.lower() != "github.com" or not url.path.lower().startswith(prefix.lower()):
                    continue
                tail = urllib.parse.unquote(url.path[len(prefix):])
                if not tail.startswith(("blob/", "tree/")):
                    continue
                rest = tail.split("/", 1)[1]
                ref = next((r for r in sorted({headref, sha}, key=len, reverse=True)
                            if rest.startswith(r + "/")), None)
                if not ref:
                    errors.append(label + ": own-repository source link must use current PR branch or full head SHA.")
                    continue
                relative = rest[len(ref) + 1:]
            elif target.startswith("#") or not url.path:
                continue
            else:
                parent = "" if name == "PR description" else str(PurePosixPath(name).parent)
                resolved = (Path(root) / parent / urllib.parse.unquote(url.path)).resolve()
                if not resolved.is_relative_to(Path(root).resolve()):
                    errors.append(label + ": link escapes repository.")
                    continue
                relative = resolved.relative_to(Path(root).resolve()).as_posix()
            if not safe(root, relative).exists():
                errors.append(label + ": target does not exist: " + relative)
    report.add("Markdown links", errors, "Local/current-PR targets; external URLs and heading anchors not fetched.")


def lab_check(root, context, config, task, maintenance, report):
    if maintenance or task not in config["assignments"]:
        report.add("Assignment structure", status="Not applicable", detail="Maintenance/unknown task.")
        return None
    spec = config["assignments"][task]
    module = Path(root) / "assignments" / spec["module"]
    candidates = [p for p in module.glob(task.lower() + "-*") if p.is_dir()] if module.is_dir() else []
    if len(candidates) != 1:
        report.add("Assignment structure", ["Create exactly one assignments/" + spec["module"] +
                   "/" + task.lower() + "-<short-name>/ directory."])
        return None
    lab, errors = candidates[0], []
    rel = lab.relative_to(root).as_posix()
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", lab.name):
        errors.append(rel + ": use lowercase kebab-case.")
    for change in context["files"]:
        name = change["filename"]
        if name.startswith("assignments/") and change.get("status") != "removed" and not name.startswith(rel + "/"):
            errors.append(name + ": unrelated assignment change.")
    readme = lab / "README.md"
    if not readme.is_file():
        errors.append(rel + ": missing README.md.")
    else:
        text = readme.read_text(encoding="utf-8")
        wanted = {"Task ID": task, "Assignment reference and revision, if provided":
                  spec["assignment_ref"], "AI policy": spec["ai_policy"]}
        for name, value in wanted.items():
            if field(text, name) != value:
                errors.append(rel + "/README.md: " + name + " must be " + value + ".")
        for heading in ("Prerequisites", "Verification", "Known Limitations", "References and AI Usage"):
            if not re.search(r"(?im)^##\s+" + heading + r"\s*$", text):
                errors.append(rel + "/README.md: missing ## " + heading + ".")
        if not re.search("expected outcome", text, re.I) or not re.search("actual outcome", text, re.I):
            errors.append(rel + "/README.md: state expected outcome and actual outcome.")
        for number, line in enumerate(text.splitlines(), 1):
            if re.search("working directory", line, re.I):
                match = re.search(r"(?<![a-zA-Z0-9_./-])((?:\./)?assignments/[a-zA-Z0-9_./-]+)", line)
                if not match or match.group(1).removeprefix("./").rstrip("/") != rel:
                    errors.append(rel + "/README.md:" + str(number) + ": working directory must be " + rel + ".")
    index = (Path(root) / "README.md").read_text(encoding="utf-8")
    row = next((s for s in index.splitlines() if re.search(r"\|\s*" + re.escape(task) + r"\s*\|", s)), "")
    if not row or rel not in row or context["pr"]["html_url"] not in row:
        errors.append("README.md: index " + task + " with its actual lab path and PR URL.")
    for name in spec.get("required_files", []):
        if not safe(lab, name).is_file():
            errors.append(rel + "/" + name + ": required file missing.")
    report.add("Assignment structure", errors)
    return lab


def checker(lab, spec, origin, report):
    if not lab:
        report.add("Assignment checker", status="Not applicable", detail="No resolved lab/maintenance PR.")
        return
    if not spec.get("checker"):
        report.add("Assignment checker", status="Not run", detail="No approved lightweight checker is configured for this assignment. "
                   "Run the assignment's documented build/tests locally and provide results for mentor review.")
        return
    if spec["checker"] != "dotnet-passport":
        report.add("Assignment checker", ["Unknown checker; ask mentor to update package."])
        return
    trusted, supplied = Path(origin) / ".mentorship/checkers/check_passport.sh", lab / "check_passport.sh"
    if not supplied.is_file() or digest(supplied, True) != digest(trusted, True):
        report.add("Assignment checker", ["check_passport.sh differs from supplied course checker."])
        return
    try:
        env = {k: v for k, v in os.environ.items() if k.upper() in
               {"PATH", "SYSTEMROOT", "WINDIR", "COMSPEC", "TEMP", "TMP", "HOME", "LANG"}}
        run = subprocess.run(["bash", trusted.resolve().as_posix(), "passport.md"], cwd=lab, env=env,
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30)
        errors = [] if run.returncode == 0 else [
            "Checker exit " + str(run.returncode) + ": " + run.stdout[-3500:] + run.stderr[-1000:]]
        passport = (lab / "passport.md").read_text(encoding="utf-8")
        transcript = re.split(r"(?m)^\s*\$\s*bash\s+check_passport\.sh[^\n]*\n", passport)[-1]
        recorded = [s.strip() for s in transcript.splitlines() if re.match(r"\s*(?:PASS\s+C\d|FAIL\s+C\d|РЕЗУЛЬТАТ:)", s)]
        actual = [s.strip() for s in run.stdout.splitlines() if s.strip()]
        if run.returncode == 0 and recorded and recorded != actual:
            errors.append("passport.md: recorded checker output differs from this run; rerun and refresh the transcript.")
        report.add("Assignment checker", errors, run.stdout[-4000:])
    except (OSError, subprocess.TimeoutExpired) as exc:
        report.add("Assignment checker", [str(exc)])


def standards(root, baseline, context, output=None):
    root, report = Path(root).resolve(), Report("Repository standards", context["pr"]["head"]["sha"])
    try:
        tracked = files(root)
        for name in tracked:
            safe(root, name)
        config, origin = policy(root, baseline, context, Report("Policy selection"))
        # Policy and mutable PR fields have a separate required metadata job.
        title = context["pr"].get("title") or ""
        match = re.match(r"\[([^\]]+)\]", title)
        task, maintenance = match.group(1) if match else "", title.startswith("[REPO] ")
        if git(root, "rev-parse", "HEAD").strip() != context["pr"]["head"]["sha"]:
            raise ValueError("Head changed after checkout; rerun for the latest head.")
        errors = [p + ": missing baseline file." for p in REQUIRED if not safe(root, p).is_file()]
        if context["pr"]["base"]["repo"]["full_name"] != context["pr"]["head"]["repo"]["full_name"]:
            errors.append("Use a branch in mentorship-labs; fork PRs are not supported.")
        report.add("Repository baseline", errors)
        formatting(root, tracked, report)
        hygiene(root, tracked, report)
        links(root, tracked, context, report)
        lab = lab_check(root, context, config, task, maintenance, report)
        checker(lab, config["assignments"].get(task, {}), origin, report)
    except (ValueError, KeyError, OSError, UnicodeError, subprocess.SubprocessError) as exc:
        report.add("Validator execution", [str(exc)])
    return report.finish(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["fetch", "standards", "verify-bundle"])
    parser.add_argument("--root", default=".")
    parser.add_argument("--baseline")
    parser.add_argument("--context")
    parser.add_argument("--event", default=os.environ.get("GITHUB_EVENT_PATH"))
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        if args.command == "fetch":
            fetch(args.event, args.output)
            return 0
        if args.command == "verify-bundle":
            errors = bundle(args.root)
            for error in errors:
                print("Failed | " + error)
            if not errors:
                print("Passed | Package checksums")
            return int(bool(errors))
        if not args.context:
            parser.error("--context required; use fetch in CI or a local fixture.")
        return standards(
            args.root, args.baseline, load(args.context), args.output)
    except (ValueError, KeyError, OSError) as exc:
        print("Failed | CI execution | " + str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
