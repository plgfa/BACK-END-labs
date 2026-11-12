#!/usr/bin/env python3
"""Capture PR metadata locally using an already-authenticated GitHub CLI."""
import argparse
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--repo", required=True)
parser.add_argument("--pr", type=int, required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo) or args.pr < 1:
    parser.error("Use owner/repository and a positive PR number.")
prefix = "repos/" + args.repo + "/pulls/" + str(args.pr)
def fetch(path, paginate=False):
    command = ["gh", "api", path] + (["--paginate", "--slurp"] if paginate else [])
    value = json.loads(subprocess.check_output(command, text=True, encoding="utf-8"))
    return [item for page in value for item in page] if paginate else value
data = {"pr": fetch(prefix), "reviews": fetch(prefix + "/reviews?per_page=100", True),
        "files": [{"filename": x["filename"], "status": x["status"]}
                  for x in fetch(prefix + "/files?per_page=100", True)]}
Path(args.output).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8", newline="\n")
print("Saved PR metadata. This file contains no GitHub token.")
