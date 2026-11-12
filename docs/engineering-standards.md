# Engineering Standards

These standards apply to repository maintenance and changes to the learning materials. A lab may add stricter requirements; follow those requirements when they apply.

## Scope and preservation

- Keep each change limited to its stated lab or maintenance goal.
- Preserve the supplied lesson text, starter files, and exercise fixtures unless the task explicitly asks to change them.
- Treat directories named `_git` inside a lab as exercise data. Do not alter their contents unless the lab specifically requires it.
- Do not add homework solutions to the root index or merge unapproved assignment work into `main`.

## Reproducibility

- Document prerequisites and commands needed to complete or verify a lab.
- State the working directory for commands whose behavior depends on it.
- Separate expected results from results actually observed.
- Do not claim a check passed unless it was run and its result was inspected.

## File and security hygiene

- Use UTF-8 text files, LF line endings, and a final newline; use CRLF for Windows batch files.
- Do not commit credentials, private keys, personal tokens, local environment files, IDE state, or generated build output.
- Keep binary assets only when a lab needs them and explain their purpose in the lab documentation.
- Use relative links for repository files and verify that each target exists.

## Shell and Git exercises

- Make scripts fail clearly when prerequisites are missing or a command fails.
- Explain destructive commands before asking a learner to run them, and keep exercises scoped to their designated work directory.
- Preserve published Git history in exercises that teach safe collaboration; use the recovery method specified by the lab.
