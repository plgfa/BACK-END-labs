# Semgrep Community Edition

The workflow invokes the official, version-pinned Semgrep Docker image directly.
It downloads maintained Registry rulesets `p/default` and `p/csharp`; no custom
security rules, Semgrep account or Semgrep token are required.

`p/default` supplies general security and code-quality rules. `p/csharp` adds
the explicit C# language profile. These scans do not replace builds, tests,
dependency scanning, secret scanning or mentor review.

Findings and scanner/configuration errors fail the job. The reporting adapter
only formats the scanner's JSON; it does not implement security detection.

Registry access requires network connectivity. Rulesets can change independently
of the pinned engine. Download/configuration failures are failures, not clean scans.
Metrics are disabled. The scanner analyzes source in the CI runner.
