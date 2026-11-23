---
allowed-tools: Bash(~/.claude/scripts/pr-risk.sh:*), Bash(__USER_HOME__/.claude/scripts/pr-risk.sh:*), Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr comment:*), Bash(gh pr diff:*), Bash(gh pr view:*), Bash(gh pr list:*), mcp__github_inline_comment__create_inline_comment
description: Code review a pull request
# Modified from the code-review command in Anthropic's official code-review plugin
# (github.com/anthropics/claude-code, plugins/code-review), Apache License 2.0;
# see LICENSE-code-review next to this file. Changes: can review a new head
# commit and no longer skips PRs judged trivial, a "Reviewed at <sha>" summary comment, two review
# agents whose models are set by ~/.claude/scripts/pr-risk.sh, and findings tagged Important, Nit or
# Pre-existing. install.sh replaces __USER_HOME__ with your home path.
---

Provide a code review for the given pull request.

**Agent assumptions (applies to all agents and subagents):**
- All tools are functional and will work without error. Do not test tools or make exploratory calls. Make sure this is clear to every subagent that is launched.
- Only call a tool if it is required to complete the task. Every tool call should have a clear purpose.

To do this, follow these steps precisely:

1. Launch a haiku agent to check if any of the following are true:
   - The pull request is closed
   - The pull request is a draft
   - A code review already exists for the PR's CURRENT head commit: a comment headed "Code review" that says "Reviewed at `<sha>`" with that exact head SHA (get the head with `gh pr view <PR> --json headRefOid`). Other Claude comments on the PR, and code reviews of earlier commits, do NOT stop the review. Run on demand, a new commit can be reviewed again. (Changed 2026-11-05: the old rule stopped on any earlier Claude comment. Since 2026-11-23 `/until-clean` invokes this command once per PR and checks later commits with its own fix check; that limit lives in the skill, not here.)

   If any condition is true, stop and do not proceed.

Note: Still review Claude generated PR's.

2. Launch a haiku agent to return a list of file paths (not their contents) for all relevant CLAUDE.md files including:
   - The root CLAUDE.md file, if it exists
   - Any CLAUDE.md files in directories containing files modified by the pull request

3. Launch a sonnet agent to view the pull request and return a summary of the changes

4. **Two review agents; models by risk.** (Two since 2026-11-23: this is the one full review a PR gets, and a second pair of agents on the same diff was finding almost nothing the first had not.) Decide the models **mechanically, never by judgment**: run `~/.claude/scripts/pr-risk.sh <PR>` (Bash). It prints `RISK=sensitive|normal` (normal only when every changed file is docs, images or styles by file type and no added line has a risky word; anything else, or any error, is sensitive). Never treat a PR as lower risk than the script says.
   - **RISK=sensitive (any PR with code), or the script can't run:** the bug agent on **opus**, the compliance agent on **sonnet**. In step 5, validate bugs with opus and CLAUDE.md issues with sonnet.
   - **RISK=normal (docs, images or styles only):** both on **sonnet**. In step 5, validate with **sonnet** agents.

   Launch the two agents in parallel to independently review the changes. Each agent should return the list of issues, where each issue includes a description, the reason it was flagged (e.g. "CLAUDE.md adherence", "bug") and a tag: **Important** (wrong behaviour, or a clear rule broken), **Nit** (real but minor), or **Pre-existing** (a significant bug in code this PR did not introduce). Where the same mistake appears more than once, the agent reports it once as a class and lists every place, so one fix covers them all. The agents should do the following:

   Compliance agent
   Audit changes for CLAUDE.md compliance. Note: When evaluating CLAUDE.md compliance for a file, you should only consider CLAUDE.md files that share a file path with the file or parents.

   Bug agent
   First scan the diff itself for obvious bugs, flagging only significant ones you can validate from the diff. Then look for problems in the introduced code: security issues, incorrect logic, a test that cannot fail. Only look for issues that fall within the changed code.

   **CRITICAL: We only want HIGH SIGNAL issues.** Flag issues where:
   - The code will fail to compile or parse (syntax errors, type errors, missing imports, unresolved references)
   - The code will definitely produce wrong results regardless of inputs (clear logic errors)
   - Clear, unambiguous CLAUDE.md violations where you can quote the exact rule being broken

   Do NOT flag:
   - Code style or quality concerns
   - Potential issues that depend on specific inputs or state
   - Subjective suggestions or improvements

   If you are not certain an issue is real, do not flag it. False positives erode trust and waste reviewer time.

   In addition to the above, each subagent should be told the PR title and description. This will help provide context regarding the author's intent.

5. For each issue found in the previous step, launch parallel subagents to validate the issue. These subagents should get the PR title and description along with a description of the issue. The agent's job is to review the issue to validate that the stated issue is truly an issue with high confidence. For example, if an issue such as "variable is not defined" was flagged, the subagent's job would be to validate that is actually true in the code. Another example would be CLAUDE.md issues. The agent should validate that the CLAUDE.md rule that was violated is scoped for this file and is actually violated. Use Opus subagents for bugs and logic issues, and sonnet agents for CLAUDE.md violations (all sonnet when step 4 said RISK=normal).

6. Filter out any issues that were not validated in step 5. This step will give us our list of high signal issues for our review.

7. Output a summary of the review findings to the terminal:
   - If issues were found, list each issue with a brief description.
   - If no issues were found, state: "No issues found. Checked for bugs and CLAUDE.md compliance."

   If `--comment` argument was NOT provided, stop here. Do not post any GitHub comments.

   If `--comment` argument IS provided and NO issues were found, post a summary comment using `gh pr comment` and stop.

   If `--comment` argument IS provided and issues were found, continue to step 8.

8. Create a list of all comments that you plan on leaving. This is only for you to make sure you are comfortable with the comments. Do not post this list anywhere.

9. Post a short summary comment headed "## Code review" with the line "Reviewed at `<full head SHA>`." and the number of issues found by tag (Important, Nit, Pre-existing). List any Pre-existing issues in that summary only, marked "file as an issue, not for this PR"; they get no inline comment. Then post inline comments for each Important and Nit issue, each starting with its tag, using `mcp__github_inline_comment__create_inline_comment` with `confirmed: true`. For each comment:
   - Provide a brief description of the issue
   - For small, self-contained fixes, include a committable suggestion block
   - For larger fixes (6+ lines, structural changes, or changes spanning multiple locations), describe the issue and suggested fix without a suggestion block
   - Never post a committable suggestion UNLESS committing the suggestion fixes the issue entirely. If follow up steps are required, do not leave a committable suggestion.

   **IMPORTANT: Only post ONE comment per unique issue. Do not post duplicate comments.**

Use this list when evaluating issues in Steps 4 and 5 (these are false positives, do NOT flag):

- Pre-existing issues that are minor (a significant one is reported once, tagged Pre-existing, for an issue; never as this PR's fault)
- Something that appears to be a bug but is actually correct
- Pedantic nitpicks that a senior engineer would not flag
- Issues that a linter will catch (do not run the linter to verify)
- General code quality concerns (e.g., lack of test coverage, general security issues) unless explicitly required in CLAUDE.md
- Issues mentioned in CLAUDE.md but explicitly silenced in the code (e.g., via a lint ignore comment)

Notes:

- Use gh CLI to interact with GitHub (e.g., fetch pull requests, create comments). Do not use web fetch.
- Create a todo list before starting.
- You must cite and link each issue in inline comments (e.g., if referring to a CLAUDE.md, include a link to it).
- If no issues are found and `--comment` argument is provided, post a comment with the following format:

---

## Code review

Reviewed at `<full head SHA>`.

No issues found. Checked for bugs and CLAUDE.md compliance.

---

- When linking to code in inline comments, follow the following format precisely, otherwise the Markdown preview won't render correctly: https://github.com/anthropics/claude-code/blob/c21d3c10bc8e898b7ac1a2d745bdc9bc4e423afe/package.json#L10-L15
  - Requires full git sha
  - You must provide the full sha. Commands like `https://github.com/owner/repo/blob/$(git rev-parse HEAD)/foo/bar` will not work, since your comment will be directly rendered in Markdown.
  - Repo name must match the repo you're code reviewing
  - # sign after the file name
  - Line range format is L[start]-L[end]
  - Provide at least 1 line of context before and after, centered on the line you are commenting about (eg. if you are commenting about lines 5-6, you should link to `L4-7`)
