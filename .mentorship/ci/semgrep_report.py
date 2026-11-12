"""Translate official Semgrep JSON into the shared PR report; never run a scan."""
import argparse
import json
from pathlib import Path

from ci import Report, load


def summarize(path, exit_code, sha):
    report = Report("Semgrep", sha)
    try:
        data = load(path)
        findings, errors = data["results"], data["errors"]
        scanned = data["paths"]["scanned"]
        if not all(isinstance(value, list) for value in (findings, errors, scanned)):
            raise ValueError("Invalid Semgrep JSON structure.")
        problems = [str(hit["path"]) + ":" + str(hit["start"]["line"]) + ": " +
                    str(hit["check_id"]) + ": " + str(hit["extra"]["message"]) for hit in findings]
        problems.extend("Scanner error: " + str(error.get("message", error)) for error in errors)
        if exit_code not in (0, 1) or exit_code == 1 and not findings:
            problems.append("Semgrep exited with code " + str(exit_code) + "; open the scan logs.")
        report.add("Community rules scan", problems,
                   str(len(findings)) + " findings; " + str(len(scanned)) + " files scanned. " +
                   "Registry rules: p/default and p/csharp.",
                   status="Not applicable" if not scanned and not problems else None)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        report.add("Scan execution", ["Missing or invalid Semgrep report: " + str(exc)])
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--exit-code", type=int, required=True)
    args = parser.parse_args()
    sha = load(args.context)["pr"]["head"]["sha"]
    raise SystemExit(summarize(Path(args.input), args.exit_code, sha).finish())
