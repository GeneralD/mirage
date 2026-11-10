# Worker procedure

You implement exactly one issue on repository `GeneralD/mirage` and nothing else. You assume nothing
beyond `docs/hackathon/mvp-cd/PRODUCT.md` and your issue. You ask no questions.

## Hard rules

- You are in your own throwaway git worktree. Never run `git checkout`, `git switch` or `git stash`.
- Never push to `main` or `hackathon/mvp-cd`. Never force-push.
- One plain command per Bash call around `git` and `gh`: no `cd`, `for`, `$(...)`, `git -C`, no shell
  variables, no pipelines into `git`. Use absolute paths. A loop goes in a script.
- Commit messages and PR titles are English Conventional Commits with a scope. No attribution lines.
- Nothing runs in the background: a subagent never receives a background command's completion, so
  it ends without a result. Long commands run in the foreground with the Bash timeout at 600000; one
  that times out before its verdict is run again (builds are incremental).

## Steps

1. `git fetch origin`, then `git reset --hard origin/hackathon/mvp-cd`.
2. Read `docs/hackathon/mvp-cd/PRODUCT.md`, then `gh issue view <n> -R GeneralD/mirage`. Follow
   `Approach`; read the `exemplar` file first and copy its shape. If an API is unclear, check the
   official docs for at most five minutes. Still ambiguous: take the simplest implementation and end
   the PR body with `Decision: <one line>`. A question of which approach is right is not yours:
   comment on the issue, add the label `hk:research`, and proceed with what is known.
3. Implement inside `Scope` only. Tests with the implementation, one per `Interface` item, named as a
   spec sentence. If `Off-limits` or a hot file must be touched: do not implement; comment why, add
   the label `hk:regen`, stop.
4. `make format`, commit what it rewrites, then `scripts/gate -- <the issue's Done command>`.
   UI changes also need the image check in PRODUCT.md; any visual defect is red. While the screen is
   locked (`ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes'` exits 0) no window can be captured: take no image,
   add the label `hk:shot-pending` to the issue, and go on. Never commit a capture taken while locked.
5. Green: commit, `git push origin HEAD:refs/heads/task/<n>`, then
   `gh pr create -R GeneralD/mirage --base hackathon/mvp-cd --head task/<n> --assignee @me --title "<type(scope): summary>" --body-file <file>`.
   The body is the badge row
   `![agent](https://img.shields.io/badge/agent-claude-D97757) ![issue](https://img.shields.io/badge/issue-%23<n>-grey)`,
   a blank line, `Closes #<n>`, the line `Gate: GREEN`, and `Decision:` lines if any. A UI PR commits
   `docs/shots/<n>/after.png` and embeds
   `https://github.com/GeneralD/mirage/blob/task/<n>/docs/shots/<n>/after.png?raw=true`; with the
   screen locked it writes the line `Shot: pending (screen locked)` instead.
6. CI: `gh pr checks <pr> -R GeneralD/mirage --watch --interval 30`, in the foreground (rerun it if
   the call times out). A red check goes to step 8. No checks at all after 5 minutes: proceed; the
   local gate is green and CI absence does not block.
7. `gh pr merge <pr> -R GeneralD/mirage --squash --delete-branch`, then
   `gh issue close <n> -R GeneralD/mirage --reason completed` (a closing keyword does not fire on a
   non-default base). A conflict: `git rebase origin/hackathon/mvp-cd` once, gate, push with a new
   branch name `task/<n>-r1`, and open a new PR. Still conflicting: step 8.
8. Red: regenerate up to twice with the failure log: `git reset --hard origin/hackathon/mvp-cd` and
   implement again rather than patching. Still red: comment the log on the issue, add `hk:regen`, stop.

## Report

Your final message is one line: `#<n> merged`, `#<n> regen(<cause>)`, `#<n> research` or `#<n> timeout`.
