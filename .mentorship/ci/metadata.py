"""Run policy and PR metadata checks with the approved base-branch validator."""
import argparse
import importlib.util
from pathlib import Path


def check(root, baseline, context_file, validator):
    spec = importlib.util.spec_from_file_location("approved_ci", Path(validator) / ".mentorship/ci/ci.py")
    ci = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ci)
    context = ci.load(context_file)
    report = ci.Report("Submission metadata", context["pr"]["head"]["sha"])
    try:
        config, _ = ci.policy(Path(root).resolve(), baseline, context, report)
        ci.metadata(context, config, report, ci.git(root, "rev-parse", "HEAD").strip())
    except (ValueError, KeyError, OSError) as exc:
        report.add("Metadata execution", [str(exc)])
    return report.finish()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("root", "baseline", "context", "validator"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    raise SystemExit(check(args.root, args.baseline, args.context, args.validator))
