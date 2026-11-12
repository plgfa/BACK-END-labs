# Mentorship CI - student setup

Version: 1.3.0. Source scans and mutable metadata use separate workflows. One PR dashboard is updated after runs, with a status banner, ownership/review links, check details and the last eight run attempts. No manual submitted SHA is required; self-review is optional. Automatic author assignment and mentor review requests remain enabled.

For an existing integration PR, copy the updated files into the same branch, including .mentorship/bundle.json and .github/pull_request_template.md, and commit them. Remove the Submitted revision field from the existing PR description. Do not create a replacement PR or edit the checksums manually. GitHub and the CI report record the checked commit automatically.

Copy the contents of this archive into the root of your existing mentorship-labs repository. Include the hidden .github, .mentorship and .semgrep directories. Merge directories; update the supplied PR template while preserving any repository-specific guidance. Do not replace your existing .github directory or overwrite your main README.

This archive contains only the files to integrate and this guide. The tests under .mentorship are CI infrastructure, not homework. When upgrading from 1.1.x, delete .semgrep/security.yml and .mentorship/smoke/; they are no longer used. Remove any accidentally committed mentorship-ci-student-* wrapper directory; install only at the repository root.

## 1. Create an integration branch

Start from current main:

~~~bash
git switch main
git pull --ff-only
git switch -c chore/mentorship-ci
~~~

Copy the archive contents into the repository root, then run:

~~~bash
python -m unittest discover -s .mentorship/tests -v
~~~

Python 3.12+ and Git are needed locally. Git Bash or Linux is needed for the passport checker. GitHub runs Semgrep using a pinned container; you do not need a Semgrep account, token or local installation.

Your existing repository must contain the standard baseline: README.md, CONTRIBUTING.md, .editorconfig, .gitattributes, .gitignore, docs/engineering-standards.md and .github/pull_request_template.md. Ask the mentor if any are missing.

## 2. Commit the integration files

~~~bash
git add .github/workflows/mentorship-ci.yml .github/workflows/mentorship-metadata.yml .github/pull_request_template.md .mentorship .semgrep .semgrepignore MENTORSHIP-CI.md
git commit -m "ci(repo): integrate mentorship submission checks"
~~~

Keep this PR separate from homework. Preserve participant information, existing workflows and the engineering standard.

## 3. Open the integration PR

Title: [REPO] Integrate mentorship CI

The PR setup job assigns the PR to its author and requests review from exc3pt1ongit automatically. It preserves existing assignees/reviewers and does not send another request when a mentor has already reviewed this revision. Draft PRs are assigned immediately; review requests wait until the PR is marked ready.

After initial installation, mentor logins are read from the approved base-branch .mentorship/config.json. The initial bootstrap reviewer is packaged as exc3pt1ongit. If another mentor is assigned to you, ask for a tailored package before installation.

Use this body and replace the actual verification result. The self-review section is optional guidance; CI does not require it or enforce checkbox completion:

~~~markdown
## Assignment

- Task ID: REPO
- Assignment reference and revision, if provided: REPO
- AI policy: FORBIDDEN

## Changes

Integrates the mentor-provided Mentorship CI package.

## Verification

Expected outcome: repository standards and Semgrep configuration checks pass.
Actual outcome: REPLACE_WITH_THE_TESTS_YOU_RAN_AND_THEIR_RESULTS

## Known limitations and questions

The first GitHub Actions run and automatic PR comment must be checked on this PR.

## References and AI usage

Mentor-provided Mentorship CI 1.3.0. Declare any participant use of tools accurately.

## Self-review (optional)

- [ ] I reviewed the complete diff and kept this PR separate from homework.
- [ ] I preserved participant metadata, existing workflows and the engineering standard.
- [ ] I ran local validator tests and recorded their actual result.
- [ ] I verified that the author is assigned and the mentor is requested as reviewer.
~~~

No manual commit SHA is required in the PR description or comments.

## 4. Check the results and obtain approval

The source workflow owns Repository standards, Semgrep and Source report. The metadata workflow owns PR setup, Submission metadata and PR dashboard; setup completes before metadata validation. Job names are unique across workflows so required-check selection is unambiguous. A single bot comment shows a status banner, the current commit, linked assignees/reviewers, review state, check results and collapsible details/history. Profile links identify people without repeatedly notifying them. The last eight run attempts link to their complete logs; GitHub retains earlier runs according to repository retention settings. Existing package-generated bot comments are consolidated; human comments are preserved.

| Event | Work performed |
| --- | --- |
| PR opened, reopened or updated with commits | Setup, metadata/policy, repository checks and Semgrep |
| Description/title, draft state, assignee or reviewer changed | Setup and metadata/policy only |
| Review submitted or dismissed | Setup and metadata/policy only |
| Review text edited | No run |

Metadata events cannot cancel a source scan. Reports serialize updates to one comment, reject obsolete commits and retain source failures during metadata-only runs. Source results for an earlier commit are never presented as current. The reporting job reads GitHub check results if a source report is delayed. Only one report is kept, even when both workflows complete together.

If a check fails, read its message, fix the issue in the same PR and rerun applicable local checks. Do not remove rules or suppress findings to make the PR pass.

If setup or commenting fails with a permissions/access error, ask the mentor to check Actions policy and collaborator access. Do not add a personal token. The metadata setup and reporting jobs request issues/pull-requests write permissions and never check out or execute repository code. Analysis jobs remain read-only.

Automation is idempotent. It adds only missing metadata and preserves other users' assignments/review requests. If an API write cannot be confirmed, setup fails visibly and dependent analysis waits for the access issue to be fixed. Closed and fork PRs are not modified.

Wait for mentor approval before merging. Green CI is not approval. The initial integration needs manual review because main has no earlier CI policy to compare against.

GitHub Actions must be enabled. Private-repository runs use the owner's included allowance; this package does not change billing settings or require paid Semgrep features.

CI jobs publish results on the PR. To prevent merges when checks fail, the owner must configure branch protection or a ruleset requiring PR setup, Submission metadata, Repository standards and Semgrep, plus mentor approval. This is a separate repository setting, not something installing a workflow enables automatically. GitHub plan restrictions may apply to private repositories; ask the mentor if protection is unavailable. Never change repository visibility to bypass a plan restriction.

## 5. Use it for language assignments

- Submit language assignments, including setup homework, through branches and PRs. Earlier non-coding homework does not need retroactive submission.
- Use the short task ID recorded in .mentorship/config.json, its course assignment reference, and the configured module directory.
- For example, CS-SETUP-02 maps to ASG.LANG.CS.SETUP.02, taught in lesson LANG.CS.SETUP.L01.
- Keep the PR title, lab README, root index and directory consistent. Use a branch such as feat/cs-setup-02-environment-passport.
- If you need the PR URL for the root index, open a Draft PR, add the URL and commit. Request the mentor's review when the PR is ready.
- Check that PR setup has assigned the author and requested mentor review. If these are already set, it makes no duplicate request. A mentor's review of the exact current revision also satisfies reviewer presence.
- Do not rename an existing PR branch in a way that closes its review history. Ask for a scoped, mentor-approved exception.
- Unapproved additions or merges of assignment code into main are a serious violation unless a different workflow was explicitly agreed with the mentor.

## Coverage and limits

The catalog registers 22 homework IDs. Semgrep Community Edition runs with the official pinned scanner image and maintained Registry rulesets p/default and p/csharp. Findings and scanner/configuration errors fail CI. Network access is required to download rules; rules can change independently of the pinned scanner. No Semgrep account or token is required. The adapter only formats official scanner JSON; it does not implement scanning or custom rules. See .semgrep/README.md.

The bundled executable assignment checker currently covers CS-SETUP-02. Other assignments show Not run for their assignment-specific checker until the mentor adds an approved stack check. Run and document the builds/tests required by your assignment. Semgrep is not a compiler, test runner, full secrets scanner or proof of correctness.

CI checks selected text formatting and file hygiene, required metadata, reviewer/assignee, structure, local Markdown targets and current-PR source links. It automatically verifies that the checkout matches the current PR commit. It does not require a manually copied SHA or a completed self-review checklist, crawl external URLs or validate heading anchors.

Semgrep scans languages covered by the selected community rules. A green scan does not establish coverage for every language or file. If no applicable source is scanned, the report states Not applicable. Ask the mentor for additional language rules and assignment-specific checks when needed.

Only the mentor approves changes to protected CI files, rules, the catalog and exceptions. The package checksums must remain intact. Do not edit bundle.json to hide a modification.

This mentor-provided infrastructure does not grant permission to use generative AI for assignments marked FORBIDDEN.

## Source attribution

The supplied passport checker is preserved from nerdy-solutions/ed-mentorship-content, commit 471cd4e3445bd593afc924cfc58784587f621708, labs/starters/ASG.LANG.CS.SETUP.02/check_passport.sh. Original attribution and ownership remain in effect. No homework solutions or private mentor guides are included.

Semgrep and the referenced GitHub actions retain their own licenses. The package references their pinned versions; it does not redistribute their binaries.
