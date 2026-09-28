# Gaps

- Q: For the plan and visibility the prime-game repo will actually have, what merge-time enforcement does GitHub provide: protected branches, required status checks, required CODEOWNERS review, and rulesets that block force-push or deletion? If a private repo on GitHub Free has none of these, which client-side mechanism reliably takes over?
  - why: Several critiques rest the permissions design on 'GitHub branch protection as the non-negotiable backstop', and KICKOFF 5.4 assumes a protected main, required CI and required CODEOWNERS review. GitHub's plans page says protected branches, required reviewers and code owners in PRIVATE repos come with Pro or Team (https://docs.github.com/en/get-started/learning-about-github/githubs-plans). The rulesets page says rulesets are for GitHub Team and Enterprise customers (https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets). The gh account is a personal account (xperiaroco2) and the repo does not exist yet. If it ends up private on Free, a PreToolUse guard hook (push to main, force-push, branch delete, recursive rm) and a committed git pre-push hook change from optional to the only enforcement. Required CI and CODEOWNERS review would then be convention only, and the permissions and hooks section and its options list would change.
- Q: How can agents perform the KICKOFF 5.1 board and issue operations non-interactively with gh 2.88.1? That covers: token scopes; moving an item between Status columns (item-edit IDs); which transitions the built-in Project workflows already automate, and whether they are available on a user-owned project; whether the designer can edit a user-owned project; and whether `gh issue create --template` works with YAML issue forms or only with Markdown templates.
  - why: The digest has no coverage of section 5 mechanics, but start-task and finish-task, the engine-request flow and the permission allowlist all depend on them. A local `gh auth status` shows token scopes 'gist', 'read:org', 'repo', 'workflow', with NO `project` scope, and the gh manual says 'The minimum required scope for the token is: project' (https://cli.github.com/manual/gh_project). So every board operation would fail today, and each human needs a `gh auth refresh -s project` step that `doctor` should check. The built-in workflows set Status to Done when an item is closed or its PR is merged, by default (https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations). That may cut the skills down to setting In progress and In review, or they may need to look up field and option IDs. If gh cannot fill YAML issue forms, agents must build bodies and labels by hand, which affects the choice between forms and Markdown templates and 'how humans phrase requests'. gh project item-edit is a write, so it needs an allow or ask decision.
- Q: What is the safe way for an agent to create and edit Godot 4.7.2 content .tres files and level sub-scene .tscn files? Specifically: how uid= headers, ext_resource uids and script .uid sidecars must be handled; what `--headless --import` and the editor do with missing, duplicate or mismatched UIDs (warn, rewrite files, or break references); and what the open Godot editor does when the agent changes a scene or resource the designer has open (reload prompt, or a silent overwrite on the next save)?
  - why: The designer's agent works almost entirely in content .tres data and level sub-scenes, and KICKOFF lets the designer hand-edit layout in the editor at the same time. The toolchain research covered .gd parse checks only; none of the 10 topics covered text authoring of resources or scenes. The answers decide:
- whether the new-mechanic and new-level-piece skills hand-write text or generate files through a headless GDScript tool that uses ResourceSaver/PackedScene;
- whether `check` must fail on UID warnings, duplicates or files rewritten by import;
- the working rule between the designer and her own agent (close the scene first, work in a worktree, or the agent never touches a .tscn that is open);
- whether 'scenes are single-owner' also needs a human-vs-own-agent rule.
- Q: When a subagent's frontmatter, an Agent call or a workflow stage selects `fable` (the obvious reading of KICKOFF's 'strongest model' for code-reviewer), on the humans' Pro/Max plans does it bill usage credits, show a consent prompt, or silently continue on the default model? Does that differ for background subagents and workflow agents? Does `availableModels` in the shared .claude/settings.json (or an Agent(model:fable) deny) reliably block it at the subagent and workflow level? And how do subagents and ultracode fan-out count against plan limits?
  - why: KICKOFF section 0 says to stop and ask before anything that costs money. model-config.md says 'Depending on your plan and seat tier, Fable usage can bill to usage credits', that the consent prompt appears in interactive sessions, and that once the user continues on Fable 'Claude Code doesn't show the prompt again'. Mid-session, dismissing the prompt makes Claude Code continue 'on your default model' (https://code.claude.com/docs/en/model-config.md). Two risks follow. A code-reviewer routed to Fable could either spend money after a single consent, or be silently downgraded, which would make the 'strongest model' routing claim false. Either way, the per-subagent model options, the routing-verification method and the ultracode effort policy all change, possibly adding an availableModels guard to shared settings.
- Q: Where should machine-specific env (GODOT_BIN, GODOT_GUI_BIN, PYTHON_BIN, GDTOOLKIT_DIR) live so that it reliably reaches PowerShell and Bash tool calls, command hooks, subagents and workflow agents in Desktop 2.1.281 local sessions, including Desktop worktree sessions on Windows? The candidates are project .claude/settings.local.json, the env key in ~/.claude/settings.json, the Desktop 'local environment editor', or .worktreeinclude copying settings.local.json into each worktree.
  - why: KICKOFF 6 prescribes settings.local.json. A local check shows it works for tool calls in the main checkout: this Desktop session sees GODOT_BIN, PYTHON_BIN and GDTOOLKIT_DIR. The research found, however, that on Windows the file is read from the session's starting directory, so Desktop worktree sessions under .claude/worktrees/ do not see it. desktop.md says 'To set environment variables for local sessions, use the local environment editor or add to the env key in ~/.claude/settings.json', and that .worktreeinclude copies gitignored files into new worktrees. It is unverified whether a copied settings.local.json is honoured without trust issues, and whether hooks and subagents inherit settings env. This decides the worktree recommendation, the Python hook launch option that depends on $PYTHON_BIN, what `doctor` checks, and the designer's setup steps.
- Q: Does KICKOFF 5.2's design of a single docs/INTERVENTIONS.md with every entry appended at the end survive GitHub PR merges when both humans' branches append entries? Can `merge=union` in .gitattributes fix it for GitHub's mergeability check and merge button, or only for local rebase? The same question applies to other shared append-style files such as CREDITS.md and rule lists in root CLAUDE.md.
  - why: The proposal must say how rules get added from INTERVENTIONS lessons, and the memory critique proposes that every lesson PR appends an entry. Two branches appending at EOF produce a textual conflict. Search results indicate GitHub's server-side mergeability ignores merge=union: the open community discussion #9288 (https://github.com/orgs/community/discussions/9288) and several repo issues report PRs stuck as CONFLICTING. If that is confirmed, the proposal should offer these options instead:
- per-entry files (docs/interventions/YYYY-MM-DD-slug.md, mirroring the ADR naming);
- merge=union plus a mandatory local rebase in finish-task before the PR and before merge;
- a single writer.
The choice changes the finish-task skill and the INTERVENTIONS section.

# Gap answers

## For the plan and visibility prime-game will actually have, what merge-time enforcement does GitHub provide (protected branches, required status checks, required CODEOWNERS review, rulesets blocking force-push/deletion)? If a private repo on GitHub Free has none, which client-side mechanism reliably takes over?
confidence: high

DIRECT ANSWER
1. The plan that matters belongs to the account that owns the repo. Who enables a setting, and what plan that person has, makes no difference (gap1-06). A personal repo uses the owner's plan (xperiaroco2). An org repo uses the org's plan.
2. A PRIVATE repo on GitHub Free gets no merge-time enforcement from the server. This is true for a personal Free account and for a Free org. Protected branches, rulesets, required status checks, required code-owner review, and auto-merge all require Pro, Team or Enterprise for private repos (gap1-01..05, gap1-15, gap1-16). I checked this against the live API on this account: on the user's existing private personal repo and on the private repos of the Free org BaidarkaStudio, GET branch protection, GET rulesets and GET rules-for-branch all return 403 "Upgrade to GitHub Pro or make this repository public to enable this feature." (gap1-07, gap1-08). Required status checks have no separate mechanism. They exist only as a branch-protection setting or a ruleset rule. Without either, "collaborators can merge the branch at any time" (gap1-10). Code owners are also gated to public repos on Free (gap1-04). So on private Free, KICKOFF 5.4's "protected main, required CI, required CODEOWNERS review" can only be convention.
3. The critique misreads rulesets. The about-rulesets page's product callout says rulesets are available in PUBLIC repos on Free (personal and org) and in public AND private repos on Pro, Team and GHEC. The "Team and Enterprise" sentence in the body refers to org-level and multi-repo rulesets. Only PUSH rulesets (file path/size/extension) are limited to Team in private repos (gap1-05). A public repo on Free, or a private repo on Pro, gets the full branch-ruleset set: block force pushes (on by default), restrict deletions, require PR, require code-owner review, required status checks.
4. Even with server-side protection there is a gap: the engineer would be the owner and admin, and admins bypass classic branch protection by default. "Do not allow bypassing the above settings" must be enabled. Also, on personal repos, classic bypass lists are org-only (gap1-11). Owners and admins can merge without approval, and `gh pr merge --admin` bypasses requirements (gap1-13, gap1-29). Rulesets are the better tool. They apply to everyone except the actors on the bypass list, and a bypass can be limited to "For pull requests only" (gap1-12). Whether a personal repo's ruleset bypass list accepts the repo-admin role is inferred, not confirmed.
5. Current state: prime-game does not exist yet under xperiaroco2 or BaidarkaStudio (404). So step 3 (`gh api repos/<owner>/<repo> --jq .visibility,.owner.type`) must be run after the repo is created (gap1-09). BaidarkaStudio is on the "free" plan, and the user is its admin (gap1-08).

CLIENT-SIDE FALLBACK (what reliably takes over on private Free). It has two layers, and neither is enough alone:
(a) A committed git pre-push hook, enabled per clone by `doctor` with `git config core.hooksPath <dir>`. Git applies it to every push from any shell or GUI that uses git: Claude's Bash, Claude's PowerShell, and Rider via git CLI (Rider is inferred). It sees each ref update on stdin: deletions arrive as (delete) with an all-zero oid, and a non-zero exit aborts the whole push (gap1-17). I tested this locally with a hook committed at mode 100755 and git 2.49.0.windows.1. It blocked `git push origin main`, `git -C <dir> push origin HEAD:main`, `git push origin +main`, `--force` and `--force-with-lease` on a feature branch, `--delete` and `:branch`, from both Git Bash and PowerShell. Ordinary feature-branch pushes still went through (gap1-20). Its limits:
- `git push --no-verify` and `git -c core.hooksPath=/dev/null push` bypass it completely (gap1-19, gap1-18, gap1-20).
- It only exists in clones where `doctor` ran, because config is not carried by clone (gap1-21, inferred).
- It cannot see server-side actions: `gh pr merge` (including `--admin` and `-d`), GitHub web-UI merges, and `gh api -X DELETE .../git/refs/...` (gap1-29, inferred).
- It cannot tell a force-with-lease rebase of your own branch from a destructive force. Blocking all non-fast-forward pushes conflicts with KICKOFF's "rebase on main before opening a PR" once a branch has been pushed. Policy choice: allow non-ff on your own `<area>/<issue>-*` branches, or require a fresh branch name after a rebase.
(b) A Claude Code PreToolUse guard hook in the committed .claude/settings.json, with matcher "Bash|PowerShell" (and Edit|Write for the hook files). It exits 2 or returns permissionDecision "deny". This is the only layer that sees the command text before it runs: deny rules are text matches that `git -C . push`, `git -c ... push` or `git 'push'` get around, and the Windows sandbox is not available (gap1-22, gap1-28). An exit-2 PreToolUse hook blocks before permission rules are evaluated, even when an allow rule matches. Exit 1 does NOT block (gap1-23, gap1-24). It should deny:
- `--no-verify` on push
- `-c core.hooksPath=` overrides and `git config core.hooksPath` changes
- `gh pr merge --admin`
- `gh pr merge` unless `gh pr checks` is green and, when the PR touches the other human's CODEOWNERS paths, `gh pr view --json reviews` shows an APPROVED review from that human. This reproduces KICKOFF 5.4's semantics exactly.
- `gh api` DELETE on refs
- recursive rm / Remove-Item -Recurse outside tools/out/
It covers both Bash and PowerShell tool calls (PowerShell rules and hooks are supported, gap1-25, gap1-26). It does NOT cover humans acting outside Claude (web UI, Rider), and an agent could edit it unless it lives in a protected path. `.claude/` and `.git/` are Claude Code protected directories; a custom `tools/githooks/` is not. Keeping the git hooks under `.claude/` or denying Edit/Write to them is the inferred mitigation (gap1-27).
Also on private Free, CODEOWNERS will not auto-request reviewers (gap1-04, inferred for the exact behaviour), so the agent must add the reviewer explicitly. CI still runs and reports status, but nothing blocks merge except (b).
Deny rules in settings.json stay as the first cheap layer, not a boundary (gap1-22).

HUMAN OPTIONS (for approval; none applied):
A. Public repo on personal Free. $0. Full rulesets, protected branches and code owners. Trade-off: game source, design docs and hidden-role logic are world-readable.
B. Private repo on xperiaroco2 upgraded to GitHub Pro. Protected branches, code owners, required reviewers and branch rulesets in private repos (gap1-01, gap1-05). The current Pro price is not shown on github.com/pricing, so it is unconfirmed. The designer joins as a collaborator with write access.
C. Private repo in an org on Team: $4 USD per user/month ("for the first 12 months*" per pricing page). Either a new 2-member org or BaidarkaStudio. The latter currently shows 6 filled seats, so the per-seat cost would be higher (inferred).
D. Private repo on Free with local-only enforcement: layers (a)+(b) become the ONLY enforcement, and required CI and CODEOWNERS review are convention enforced by (b) for agent actions only.
Recommendation for the options list: whichever of A–D is chosen, ship (a)+(b). In A–C they are defense-in-depth, because the owner-admin bypasses by default and `--admin` exists. In D they are the whole design. If A–C is chosen, prefer a ruleset on main with no admin bypass, or an admin bypass limited to "For pull requests only":
- block force pushes
- restrict deletions
- require PR
- required status checks (unique job names)
- require code-owner review
Verify on the first real PR: GitHub's code-owner rule applies to ALL owned files, including the author's own area, and authors cannot approve their own PRs (gap1-13). A required code-owner review may therefore block a human's PR touching only their own area. That is stricter than KICKOFF 5.4, and the bypass setting or the approval count must account for it (gap1-32, inferred).

### facts
- **gap1-01** GitHub Free for personal accounts: 'unlimited private repositories with a limited feature set'. GitHub Pro adds, under 'Advanced tools and insights in private repositories': Required pull request reviewers, Multiple pull request reviewers, Protected branches, Code owners, Auto-linked references, Pages, Wikis, insights. Free's feature list contains none of these.  
  src: https://docs.github.com/en/get-started/learning-about-github/githubs-plans (source: https://raw.githubusercontent.com/github/docs/main/content/get-started/learning-about-github/githubs-plans.md) (official-docs)
- **gap1-02** GitHub Free for organizations adds only GitHub Community support, team access controls and 2,000 Actions minutes. GitHub Team adds in private repos: required PR reviewers, multiple and team PR reviewers, protected branches, code owners, scheduled reminders, and more.  
  src: https://docs.github.com/en/get-started/learning-about-github/githubs-plans (official-docs)
- **gap1-03** Product callout of about-protected-branches: 'Protected branches are available in public repositories with GitHub Free and GitHub Free for organizations. Protected branches are also available in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server.'  
  src: https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/protected-branches.md (rendered at https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) (official-docs)
- **gap1-04** Code owners gating: 'You can define code owners in public repositories with GitHub Free and GitHub Free for organizations, and in public and private repositories with GitHub Pro, GitHub Team, GitHub Enterprise Cloud, and GitHub Enterprise Server.' Code owners must have write permission and are 'automatically requested for review' where the feature applies. Requiring code-owner approval needs an admin to enable required reviews.  
  src: https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/code-owners.md ; https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners (official-docs)
- **gap1-05** Rulesets product callout: 'Rulesets are available in public repositories with GitHub Free and GitHub Free for organizations, and in public and private repositories with GitHub Pro, GitHub Team, and GitHub Enterprise Cloud.' 'Push rulesets are available for the GitHub Team plan in internal and private repositories.' The body sentence about 'customers on GitHub Team and GitHub Enterprise plans' concerns rulesets applied to multiple repositories in an organization.  
  src: https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/repo-rules.md ; https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets (official-docs)
- **gap1-06** 'On GitHub.com, each account has its own plan... If your personal account is a member of an organization on GitHub, you may have access to different features when you use resources owned by that organization than when you use resources owned by your personal account.'  
  src: https://docs.github.com/en/get-started/using-github-docs/about-versions-of-github-docs (official-docs)
- **gap1-07** On xperiaroco2's existing PRIVATE personal repo, GET branches/main/protection, GET rulesets and GET rules/branches/main all return HTTP 403 'Upgrade to GitHub Pro or make this repository public to enable this feature.' On a PUBLIC personal repo, GET protection returns 404 'Branch not protected', meaning the feature is available but not configured.  
  src: local-test: gh api repos/xperiaroco2/<private-repo>/branches/main/protection ; gh api repos/xperiaroco2/<private-repo>/rulesets ; gh api repos/xperiaroco2/<private-repo>/rules/branches/main ; gh api repos/xperiaroco2/<public-repo>/branches/main/protection (local-test)
- **gap1-08** The org BaidarkaStudio reports plan.name 'free' (seats 3, filled_seats 6), and xperiaroco2 is an active admin. Its 3 private repos return the same 403 'Upgrade to GitHub Pro or make this repository public...' for protection and rulesets.  
  src: local-test: gh api orgs/BaidarkaStudio --jq .plan ; gh api user/memberships/orgs/BaidarkaStudio ; gh api repos/BaidarkaStudio/<repo>/branches/main/protection (local-test)
- **gap1-09** repos/xperiaroco2/prime-game and repos/BaidarkaStudio/prime-game both return 404, so the repo does not exist yet and visibility/owner.type cannot be checked. `gh api user --jq .plan` returns null; the likely reason is that the token scopes (gist, read:org, repo, workflow) do not expose plan (inferred). D:\prime-game is not yet a git repo.  
  src: local-test: gh api repos/xperiaroco2/prime-game ; gh api repos/BaidarkaStudio/prime-game ; gh auth status ; gh api user --jq .plan (local-test)
- **gap1-10** Required status checks exist as a branch-protection setting and as the ruleset rule 'Require status checks to pass before merging'. 'If required status checks aren't enabled, collaborators can merge the branch at any time.' No other required-check mechanism is documented for Free.  
  src: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets (official-docs)
- **gap1-11** Classic branch protection by default disables force pushes and deletion of matching branches. 'By default, the restrictions of a branch protection rule don't apply to people with admin permissions'; the 'Do not allow bypassing the above settings' option applies them to admins. 'Actors may only be added to bypass lists when the repository belongs to an organization.'  
  src: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches (official-docs)
- **gap1-12** Ruleset rules include Restrict deletions, Block force pushes ('This rule is enabled by default'), Require a pull request before merging (with optional require review from code owners), and Require status checks to pass. Bypass is granted to listed roles or actors (repository admins, maintain/write roles, teams, apps), and a bypass can be set 'For pull requests only' so the actor must open a PR.  
  src: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets ; https://raw.githubusercontent.com/github/docs/main/data/reusables/repositories/rulesets-bypass-step.md ; https://raw.githubusercontent.com/github/docs/main/data/reusables/repositories/rulesets-branch-tag-bypass-optional-step.md (official-docs)
- **gap1-13** 'Repository owners and administrators can merge a pull request even if it hasn't received an approving review...' and 'Pull request authors cannot approve their own pull requests.'  
  src: https://raw.githubusercontent.com/github/docs/main/data/reusables/repositories/request-changes-tips.md (official-docs)
- **gap1-15** Auto-merge for pull requests is available in public repos with Free (personal and org), and in public and private repos with Pro, Team, GHEC and GHES.  
  src: https://raw.githubusercontent.com/github/docs/main/data/reusables/gated-features/auto-merge.md (official-docs)
- **gap1-16** github.com/pricing lists Free ($0), Team ('$4 USD per user/month', shown with 'for the first 12 months*') and Enterprise ('Starting at $21 USD per user/month'). Protected branches, Code owners, Required reviewers and Repository rules are not included for Free private repos. The pricing page does not list GitHub Pro, so the current Pro price is unconfirmed.  
  src: https://github.com/pricing (official-docs)
- **gap1-17** githooks: the hooks directory defaults to $GIT_DIR/hooks but 'can be changed via the core.hooksPath configuration variable'. Hooks without the executable bit are ignored. pre-push receives '<local-ref> SP <local-object-name> SP <remote-ref> SP <remote-object-name> LF' on stdin; a ref to be deleted arrives with <local-ref> '(delete)' and an all-zeroes object name. 'If this hook exits with a non-zero status, git push will abort without pushing anything.'  
  src: https://git-scm.com/docs/githooks#_pre_push (official-docs)
- **gap1-18** core.hooksPath: 'The path can be either absolute or relative. A relative path is taken as relative to the directory where the hooks are run' (the worktree root for non-bare repos). 'You can also disable all hooks entirely by setting core.hooksPath to /dev/null... git -c core.hooksPath=/dev/null ...'  
  src: https://git-scm.com/docs/git-config#Documentation/git-config.txt-corehooksPath (official-docs)
- **gap1-19** git push '--no-verify': 'Toggle the pre-push hook... With --no-verify, the hook is bypassed completely.'  
  src: https://git-scm.com/docs/git-push#Documentation/git-push.txt---no-verify (official-docs)
- **gap1-20** Scratch repo test (git 2.49.0.windows.1): pre-push committed at tools/githooks with mode 100755, and `git config core.hooksPath tools/githooks`. It BLOCKED (rc=1): `git push origin main`, `git -C <dir> push origin HEAD:main`, `git push origin +main`, `git push --force origin feat/1`, `git push --force-with-lease origin feat/1`, `git push origin --delete feat/1`, `git push origin :feat/1`, and from PowerShell `git push origin main` and `git push origin --delete feat/2`. It ALLOWED a normal feature push. It was BYPASSED by `git push --no-verify origin HEAD:main` and `git -c core.hooksPath=/dev/null push --force origin feat/1`.  
  src: local-test: scratchpad/hooktest (bare remote.git + work clone), Git Bash and PowerShell (local-test)
- **gap1-21** core.hooksPath is stored in git config ($GIT_DIR/config for --local), which is not versioned content. Each clone or machine must run doctor (git config core.hooksPath ...) before the hook is active.  
  src: https://git-scm.com/docs/git-config#FILES (inferred)
- **gap1-22** Claude Code: 'A Bash rule matches the command text Claude writes... isn't a security boundary around the program.' `Bash(git push *)` stops `git push origin main` but not `git -C . push origin main`, `git -c push.default=current push origin main` or `git 'push' origin main`. For command-text logic use a PreToolUse hook.  
  src: https://code.claude.com/docs/en/permissions#bash-rule-limits (official-docs)
- **gap1-23** PreToolUse hooks 'run before the permission prompt, for every tool except EndConversation'. 'A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed.' Deny and ask rules are still evaluated even if a hook returns allow.  
  src: https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks (official-docs)
- **gap1-24** 'Without valid JSON on stdout, Claude Code treats exit code 1 as a non-blocking error and proceeds with the action... If your hook is meant to enforce a policy, use exit 2.' PreToolUse decision control uses hookSpecificOutput.permissionDecision (allow/deny/ask/defer).  
  src: https://code.claude.com/docs/en/hooks#exit-code-2 (official-docs)
- **gap1-25** PowerShell permission rules use the same shape as Bash rules. Claude Code parses the PowerShell AST and checks each subcommand of a compound command independently. The PreToolUse matcher covers built-in tools including Bash and PowerShell.  
  src: https://code.claude.com/docs/en/permissions ; https://code.claude.com/docs/en/hooks#pretooluse (official-docs)
- **gap1-26** Hook 'shell' field accepts 'bash' or 'powershell' and defaults to 'bash'. On Windows the shell form runs in Git Bash, or in PowerShell when Git Bash isn't installed.  
  src: https://code.claude.com/docs/en/hooks (official-docs)
- **gap1-27** Claude Code protected directories include .git, .husky and .claude (except .claude/worktrees); allow rules do not pre-approve writes there. A custom hooks dir such as tools/githooks is not protected, so hosting git hooks under .claude/ or denying Edit/Write to them via the guard is an inferred mitigation.  
  src: https://code.claude.com/docs/en/permission-modes#protected-paths (official-docs)
- **gap1-28** 'The sandbox is built into Claude Code and runs on macOS, Linux, and WSL2. Native Windows is not supported.'  
  src: https://code.claude.com/docs/en/sandboxing (official-docs)
- **gap1-29** `gh pr merge` merges 'a pull request on GitHub'. It has `--admin` ('Use administrator privileges to merge a pull request that does not meet requirements') and `-d/--delete-branch` ('Delete the local and remote branch after merge'). Because the merge is server-side, a local pre-push hook does not see it (inferred).  
  src: local-test: gh pr merge --help (gh 2.88.1) (local-test)
- **gap1-30** KICKOFF 5.4 assumes 'main is protected, always green', 'CI must pass. CODEOWNERS review is required when a PR touches the other person's area.' Section 6 asks to deny or confirm force-push, pushing to main, deleting branches, rm -rf outside tools/out/, and editing .github/workflows/.  
  src: D:\prime-game\KICKOFF.md (lines 361, 367, 415-417) (repo)
- **gap1-31** D:\prime-game\.gitattributes contains '* text=auto eol=lf', and system git config has core.autocrlf=true. Extensionless hook scripts will therefore be checked out with LF.  
  src: local-test: cat D:/prime-game/.gitattributes ; git config --system core.autocrlf (local-test)
- **gap1-32** With 'require review from code owners', any PR modifying owned content must be approved by a code owner, including files the author owns. Since authors cannot self-approve, a human's PR touching only their own area may be blocked unless admin or ruleset bypass or approval settings allow it. This is stricter than KICKOFF 5.4 and should be verified on the first real PR.  
  src: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets (inferred)
## How can agents perform the KICKOFF 5.1 board and issue operations non-interactively with gh 2.88.1? This covers token scopes, moving items between Status columns (item-edit IDs), which transitions the built-in Project workflows automate and whether they work on a user-owned project, whether the designer can edit a user-owned project, and whether `gh issue create --template` works with YAML issue forms.
confidence: high

DIRECT ANSWER

1. Token scopes. Today every board operation fails. The local token has 'gist, read:org, repo, workflow' and no project scope. `gh project list` already fails with "missing required scopes [read:project]" (gap2-01..05). Each human must run `gh auth refresh -s project` once. It is a browser/device flow that an agent cannot finish, and it adds to the existing scopes (gap2-08). The same scope is needed for `gh issue create/edit --project` (gap2-06).
   - Trap: without the scope, `gh issue view --json projectItems` does not error. gh swallows the read:project error and returns [] (gap2-07). So `doctor` must check the scope directly. One way: `gh auth status --active --json hosts`, then test whether the `scopes` string contains 'project'. With --json this command always exits 0, so doctor must parse the output rather than rely on the exit code (gap2-09).
   - GitHub Actions cannot help on a user-owned project. GITHUB_TOKEN has no project access, and a classic PAT with project+repo would be needed (gap2-25).

2. Moving Status on gh 2.88.1. Only ID-based editing exists, one field per call (gap2-10). The recipe:
   - One-time: `gh project view N --owner O --format json` gives `.id` (PVT_...). `gh project field-list N --owner O --format json` gives the Status field's `id` and `options[{id,name}]` (gap2-13).
   - Per move: `gh project item-add N --owner O --url <issue-url> --format json` gives `.id`. This call is idempotent: it returns the existing item ID (gap2-11, gap2-12). Without --format it prints nothing in agent shells. Then run `gh project item-edit --id ITEM --project-id PID --field-id SID --single-select-option-id OPT`.
   - The project, field and option IDs are stable and can be cached in a committed config. Status options keep their IDs as long as they are edited with their `id`; recreating them clears item values (gap2-15).
   - `gh project item-list N --owner O --query "assignee:@me -status:Done" --format json` exists in 2.88.1 (gap2-14).
   - gh 2.97.0 (2026-07-31) added a name-based form: `gh project item-edit N --owner O --url <issue> --field Status --value "In progress"`. It matches names case-insensitively and does not auto-add the item (gap2-16). The same release fixed 4 security advisories, one of them token exposure in `gh auth status` (gap2-17). The latest release is 2.101.0.
   - PowerShell 5.1 strips embedded double quotes from arguments passed to native exes. A `--jq 'select(.name=="Status")'` therefore breaks. Use Git Bash, write `\"`, or use `--%` (gap2-38).

3. What the built-in workflows automate:
   - On by default: an item closed becomes Done, and a PR merged becomes Done (gap2-18).
   - Auto-close issue: when Status is set to Done, the issue is closed. It is on by default for new projects (gap2-19). So agents must never set Done by hand. Done should come from a PR containing "Closes #n" being merged into main, which closes the issue; closing keywords only work on the default branch (gap2-37).
   - "Pull request linked to issue" (added Nov 2025) sets the issue to In progress when a linked PR exists. Whether it is on by default is not documented (gap2-20).
   - "Item added" can set a Status on add (gap2-21).
   - Auto-add (adding repo items that match a filter) is limited to 1 workflow on GitHub Free, 5 on Pro/Team and 20 on Enterprise. It never adds existing items (gap2-22).
   - Workflows can only be read (name, enabled) or deleted through the API. Configuring them is UI-only (gap2-23).
   - No doc limits built-in workflows to organization projects, so they should work on a user-owned project. This is inferred (gap2-24).
   - Net effect: the skills only need to set In progress (start-task) and In review (finish-task). Backlog can come from auto-add plus "Item added". Ready is a human triage step.
   - Race risk (inferred): the "PR linked" workflow may set In progress after finish-task has set In review. It should be disabled, or pointed at In review if the UI lets you choose the target status.

4. Can the designer edit a user-owned project? Yes, with two steps. The project owner invites the designer as a project collaborator with the Write role (Settings > Manage access, or GraphQL updateProjectV2Collaborators). Project access does not grant repository access, and items from a private repo are only visible to people with repo access (gap2-26, gap2-27). So the designer also needs repo collaborator access, which also makes them assignable (gap2-28). The designer's gh token also needs the project scope.
   - gh resolves `--project <title>` only among the viewer's own projects, projects linked to the repo, and the repo's organization projects (gap2-29). So the project should be linked to the repo with `gh project link N --owner O --repo R`.

5. `gh issue create --template` works with neither YAML forms nor Markdown templates in agent shells.
   - gh reads templates through GraphQL `repository.issueTemplates`. For repos that only have YAML forms this returns []. I checked godot and yt-dlp, which return [], while vscode and cli/cli list their .md templates (gap2-30, gap2-31). Issue forms support in gh has been an open request since 2022 (cli/cli#5865, gap2-32).
   - Even Markdown templates are unusable non-interactively. `--template` is rejected together with `--body`/`--body-file`, and without a TTY gh demands `--title` and `--body`. Our agent shells have no TTY on stdout (gap2-30, gap2-34).
   - gh applies only the template's title and body. Template labels and assignees are applied server-side only when the template name is sent in `createIssue(issueTemplate:)` (gap2-33).
   - So agents must always build the body themselves and use `gh issue create --title ... --body-file <tmp> --label ... --assignee ... --milestone ... [--project <title>]`.

OPTIONS FOR HUMAN APPROVAL (nothing applied)

A. Scope and gh version
- A1: Each human runs `gh auth refresh -s project` (required in any case). `doctor` checks the scope through `gh auth status --json`.
- A2 (my recommendation): also upgrade gh to 2.97.0 or later, for name-based item-edit and the security fixes. This is an install, so it is the humans' call.
- A3: stay on 2.88.1 and use the ID recipe with cached IDs.

B. Where the project lives
- B1: user-owned by the engineer. Invite the designer as project Write collaborator and as repo collaborator, and link the project to the repo.
- B2: a free organization, which gives a base role for members. Auto-add is still 1 workflow on Free.

C. How board moves are wrapped
- C1 (my recommendation): a task-runner subcommand, for example `board move <issue> <status>`. It does item-add plus item-edit, reads cached IDs, refuses Done, and checks the scope. The allowlist then only needs the runner.
- C2: skills call gh directly, and the allowlist gets `Bash(gh project item-add *)`, `Bash(gh project item-edit *)` and `Bash(gh project item-list|view|field-list *)`, plus the same `PowerShell(...)` rules.
- C3: put item-edit under ask. That means a prompt at every start-task and finish-task.
- In every case: deny or ask for `gh project delete|item-delete|field-delete|close|edit *`. Rules only match the literal command form (gap2-39).

D. Workflow configuration (UI, done once by the owner)
- Keep Item closed → Done, PR merged → Done and Auto-close on Done.
- Set Item added → Backlog, and one auto-add filter `is:issue` on the repo.
- Decide whether to disable "PR linked → In progress" or retarget it.
- After scopes are granted, verify with `gh api graphql` that projectV2.workflows{name enabled} shows the expected state.

E. Issue templates
- E1: YAML forms, for when humans file issues in the browser. You get required fields and dropdowns, and labels/projects are applied for web submissions. But gh cannot see the forms, so agents must duplicate each form's "### Field" body layout and its labels. The feature is also still in public preview (gap2-35).
- E2 (my recommendation, since humans dictate to agents): Markdown templates with front matter for labels and assignees (gap2-36). Agents read the local `.github/ISSUE_TEMPLATE/*.md`, fill the body and pass `--label` explicitly. The template stays the single source of truth for the web UI and for agents.
- E3: E2 plus `gh api graphql createIssue(issueTemplate:)`, so the server applies template labels and assignees.
- Also recommended: set GH_PROMPT_DISABLED=1 in the settings env so gh never waits on a prompt (gap2-34).

### facts
- **gap2-01** Local gh is 2.88.1 (2026-03-12), logged in as xperiaroco2 via keyring; token scopes are 'gist', 'read:org', 'repo', 'workflow' (no project/read:project).  
  src: local-test: gh --version; gh auth status (local-test)
- **gap2-02** gh project: 'The minimum required scope for the token is: project'; verify with gh auth status, add with gh auth refresh -s project.  
  src: https://cli.github.com/manual/gh_project (official-docs)
- **gap2-03** With the current token, `gh project list --owner @me` fails with 'your authentication token is missing required scopes [read:project]' (exit 1), and a GraphQL projectsV2 query returns INSUFFICIENT_SCOPES.  
  src: local-test: gh project list --owner "@me"; gh api graphql viewer.projectsV2 (local-test)
- **gap2-04** OAuth scopes: project = 'Grants read/write access to user and organization projects'; read:project = read-only access.  
  src: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps (official-docs)
- **gap2-05** Projects GraphQL API: queries need read:project, mutations need project scope.  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects (official-docs)
- **gap2-06** gh issue create and gh issue edit help: adding an issue to projects (or editing its projects) requires the project scope; run gh auth refresh -s project.  
  src: local-test: gh issue create --help; gh issue edit --help (local-test)
- **gap2-07** gh v2.88.1 treats the read:project scope error as ignorable when fetching issue projectItems (ProjectsV2IgnorableError), so `gh issue view --json projectItems` returns [] instead of failing without the scope; projectItems JSON contains only status and project title (no item id).  
  src: https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/issue/shared/lookup.go ; https://github.com/cli/cli/blob/v2.88.1/api/queries_projects_v2.go ; https://github.com/cli/cli/blob/v2.88.1/api/export_pr.go (repo)
- **gap2-08** gh auth refresh opens a browser/device flow; --scopes adds scopes and previously added scopes are kept; the minimum set (repo, read:org, gist) cannot be removed; --clipboard copies the device code.  
  src: local-test: gh auth refresh --help ; https://cli.github.com/manual/gh_auth_refresh (local-test)
- **gap2-09** `gh auth status --active --json hosts` returns per-account objects with login, state, tokenSource and a 'scopes' string (here 'gist, read:org, repo, workflow'); with --json the command always exits 0 regardless of auth issues.  
  src: local-test: gh auth status --help; gh auth status --active --json hosts (local-test)
- **gap2-10** gh 2.88.1 `project item-edit` has only ID flags: --id, --project-id, --field-id, --single-select-option-id (plus --text/--number/--date/--iteration-id/--clear); for non-draft issues the project ID is required and only one field value can be updated per invocation.  
  src: local-test: gh project item-edit --help (local-test)
- **gap2-11** In gh v2.88.1, item-add with --format json exports the created item as {id,title,body,type,url}; without --format it prints only 'Added item' and only when stdout is a TTY (nothing in agent shells).  
  src: https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/project/item-add/item_add.go ; https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/project/shared/queries/queries.go (repo)
- **gap2-12** addProjectV2ItemById returns the existing item ID if the item is already in the project; you cannot add and update an item in the same call; updateProjectV2ItemFieldValue cannot change Assignees, Labels, Milestone or Repository.  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-api-to-manage-projects (official-docs)
- **gap2-13** gh v2.88.1 JSON export: project view includes 'id' (node ID); field-list returns fields[{id,name,type,options[{id,name}]}].  
  src: https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/project/shared/queries/queries.go (repo)
- **gap2-14** gh 2.88.1 `project item-list` supports --query with Projects filter syntax (e.g. "assignee:@me -status:Done"); JSON items carry id, content and field values keyed by camelCased field name (e.g. status).  
  src: local-test: gh project item-list --help ; https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/project/shared/queries/queries.go (local-test)
- **gap2-15** UpdateProjectV2FieldInput.singleSelectOptions overwrites the existing options; ProjectV2SingleSelectFieldOptionInput.id 'preserve[s] the option's identity during updates, preventing item field values from being cleared'.  
  src: local-test: gh api graphql introspection of UpdateProjectV2FieldInput and ProjectV2SingleSelectFieldOptionInput (local-test)
- **gap2-16** gh v2.97.0 (2026-07-31) added name-based item-edit (PR #13807, merged 2026-07-20): item-edit N --owner O --url <issue> --field Status --value "In Progress"; names match case-insensitively; it does not auto-add items that are not in the project. The latest release is 2.101.0 (2026-09-15).  
  src: https://github.com/cli/cli/releases/tag/v2.97.0 ; https://github.com/cli/cli/pull/13807 ; https://cli.github.com/manual/gh_project_item-edit ; https://github.com/cli/cli/releases (changelog)
- **gap2-17** gh v2.97.0 fixed four security advisories including GHSA-cg6r-mpgc-h9mm (authentication token exposure in gh auth status).  
  src: https://github.com/cli/cli/releases/tag/v2.97.0 (changelog)
- **gap2-18** Built-in workflows: by default, when issues or PRs in the project are closed their Status is set to Done, and when PRs are merged their Status is set to Done; workflows are managed in the project's menu > Workflows > Edit > Save and turn on workflow; examples include setting Status to Todo when an item is added.  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations (official-docs)
- **gap2-19** Auto-close issue workflow closes issues when their project Status changes to Done (or a chosen status); it is enabled by default for new projects; anyone with write or admin access can enable it on existing projects.  
  src: https://github.blog/changelog/2024-04-25-github-issues-projects-auto-close-issue-project-workflow/ (changelog)
- **gap2-20** A default workflow 'Pull request linked to issue' sets the issue's Status to 'In progress' whenever a linked PR exists (Nov 2025); the changelog does not say whether it is on by default or for which projects.  
  src: https://github.blog/changelog/2025-11-06-improved-onboarding-flow-for-github-projects/ (changelog)
- **gap2-21** Built-in automations can set Status when an item is added (the doc's example is Todo on addition).  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations (official-docs)
- **gap2-22** Auto-add workflow limits: GitHub Free 1, Pro 5, Team 5, Enterprise Cloud/Server 20; filters support is:, label:, reason:, assignee:, no:; existing matching items are not added, only items created or updated after it is enabled.  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/adding-items-automatically (official-docs)
- **gap2-23** GraphQL ProjectV2 exposes workflows (ProjectV2Workflow: name, enabled, number); the only workflow mutation is deleteProjectV2Workflow, with no create, enable or configure mutation.  
  src: local-test: gh api graphql introspection of Mutation and ProjectV2Workflow (local-test)
- **gap2-24** No primary doc restricts built-in workflows to organization-owned projects; the only plan-based limit found is the auto-add count.  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/using-the-built-in-automations (inferred)
- **gap2-25** GITHUB_TOKEN is scoped to the repository and cannot access projects; for user-owned projects, Actions need a classic personal access token with project and repo scopes (a GitHub App is recommended for organization projects).  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/automating-projects-using-actions (official-docs)
- **gap2-26** User-level projects: individual collaborators can be invited with Read (view), Write (view and edit) or Admin (also add collaborators) via Settings > Manage access; this affects only the project, not the repositories; items from a private repo are visible only to people with access to that repo.  
  src: https://docs.github.com/en/issues/planning-and-tracking-with-projects/managing-your-project/managing-access-to-your-projects (official-docs)
- **gap2-27** GraphQL mutation updateProjectV2Collaborators(projectId, collaborators) exists, with ProjectV2Roles NONE/READER/WRITER/ADMIN.  
  src: local-test: gh api graphql introspection of UpdateProjectV2CollaboratorsInput and ProjectV2Roles (local-test)
- **gap2-28** Issues can be assigned to yourself, commenters, anyone with write permissions to the repository, and organization members with read permissions; max 10 assignees.  
  src: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/assigning-issues-and-pull-requests-to-other-github-users (official-docs)
- **gap2-29** gh v2.88.1 resolves --project titles from ProjectsV2 owned by the current user, ProjectsV2 linked to the repository, and ProjectsV2 of the repository's organization; `gh project link N --owner O --repo R` exists.  
  src: https://github.com/cli/cli/blob/v2.88.1/api/queries_repo.go ; local-test: gh project link --help (repo)
- **gap2-30** gh v2.88.1 issue create rejects --template together with --body/--body-file ('`--template` is not supported when using `--body` or `--body-file`') and, without a prompt-capable terminal, requires --title and --body ('must provide `--title` and `--body` when not running interactively'); the template is only applied in interactive or --editor mode; templates come from GraphQL repository.issueTemplates.  
  src: https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/issue/create/create.go ; https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/pr/shared/templates.go ; local-test: GH_PROMPT_DISABLED=1 gh issue create -R xperiaroco2/nonexistent-zz9 --template 'Bug report' --title x [--body y] (local-test)
- **gap2-31** GraphQL repository.issueTemplates returns [] for godotengine/godot (bug_report.yml) and yt-dlp/yt-dlp (six .yml forms), but lists the .md templates of microsoft/vscode and cli/cli.  
  src: local-test: gh api repos/<r>/contents/.github/ISSUE_TEMPLATE vs gh api graphql repository.issueTemplates (local-test)
- **gap2-32** cli/cli#5865 'Support for issue forms' (opened 2022-06-30) is still open: forms are 'not detected at all' by gh issue create; #11681 ('no templates found' for a YAML-only repo) was closed as its duplicate.  
  src: https://github.com/cli/cli/issues/5865 ; https://github.com/cli/cli/issues/11681 (issue)
- **gap2-33** gh applies only the template's title and body, and sends the template name as issueTemplate; GraphQL CreateIssueInput.issueTemplate 'assigns labels and assignees from the template to the issue'; IssueTemplate exposes about, assignees, body, filename, labels, name, title, type.  
  src: https://github.com/cli/cli/blob/v2.88.1/pkg/cmd/issue/create/create.go ; local-test: gh api graphql introspection of CreateIssueInput and IssueTemplate (repo)
- **gap2-34** gh CanPrompt() is false unless both stdin and stdout are TTYs (or when neverPrompt is set); in the Claude Code Bash and PowerShell tools stdout is not a TTY; GH_PROMPT_DISABLED (any value) disables interactive prompting.  
  src: https://github.com/cli/cli/blob/v2.88.1/pkg/iostreams/iostreams.go ; local-test: python sys.stdout.isatty() in both tools; gh help environment (local-test)
- **gap2-35** Issue forms are 'currently in public preview'; top-level keys include name, description, body, assignees, labels, title, type and projects (the person opening the issue must have write permission for the listed projects); responses are converted to Markdown and added to the issue body.  
  src: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms (official-docs)
- **gap2-36** Markdown issue templates support YAML front matter such as name, about, title, labels, assignees and type; config.yml supports blank_issues_enabled and contact_links; templates become available once merged to the default branch.  
  src: https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository (official-docs)
- **gap2-37** Closing keywords (close/closes/closed/fix/fixes/fixed/resolve/resolves/resolved) only take effect when the PR targets the default branch; merging a linked PR into the default branch closes the issue.  
  src: https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue (official-docs)
- **gap2-38** Windows PowerShell 5.1.26100 strips embedded double quotes when passing arguments to native exes: '.fields[] | select(.name=="Status")' arrives as select(.name==Status); escaping as \" or using --% preserves them; Git Bash passes them intact.  
  src: local-test: PowerShell & $env:PYTHON_BIN -c 'print(sys.argv)' vs Git Bash (local-test)
- **gap2-39** Claude Code Bash permission rules use Bash(cmd sub *) (':*' is equivalent); each subcommand of a compound command must match an allow rule; deny/ask rules apply if any subcommand matches; PowerShell rules have the same shape (PowerShell(...)); rules match the literal command text and are not a security boundary.  
  src: https://code.claude.com/docs/en/permissions (official-docs)
## What is the safe way for an agent to create and edit Godot 4.7.2 content .tres files and level sub-scene .tscn files? This covers the uid= headers, ext_resource uids and script .uid sidecars; what `--headless --import` and the editor do with missing, duplicate or mismatched UIDs; and what the open editor does when the agent changes a scene or resource the designer has open.
confidence: high

DIRECT ANSWER

Only a few UID mistakes break anything, and those break it silently. Everything else, Godot either tolerates or repairs.

- **Safe:** hand-written .tres and .tscn text is fine as long as every uid in it is either absent or correct.
- **Dangerous: a wrong uid that belongs to another existing file.** This happens when a uid is copy-pasted from a template .tres, or when a file is copied together with its .uid sidecar. Godot follows the uid, ignores `path=`, and prints no warning at all when the reference is loaded. The next editor save then rewrites `path=` to point at the wrong file.
- **The open editor never merges.** When the agent changes a scene that is open in the designer's editor, she gets a modal dialog the next time the editor window gains focus. Its buttons are "Reload from disk" (her unsaved edits in that scene are lost) and "Ignore external changes" (the editor immediately re-saves its own copy over the agent's file). A plain Ctrl+S or Save All before reloading also overwrites the agent's file, with no check.
- **Open .tres files reload without any prompt.** A changed .tres that the editor has loaded is reloaded silently on focus. Any unsaved inspector edits to it are discarded.

So the agent must never write a .tscn or .tres that is open in the designer's editor.

1) HOW 4.7.2 HANDLES UIDS (tested in a scratch project with 4.7.2 and checked against the source)

**Where uids live**
- .tres and .tscn files keep their uid in the header (`[gd_resource ... format=3 uid="uid://..."]`, `[gd_scene format=3 uid=...]`). They never get a .uid sidecar.
- Scripts (.gd) keep their uid in a `<file>.gd.uid` sidecar, which must be committed.
- `load_steps` is deprecated since 4.6. Nodes gain `unique_id=` from 4.6 on.

**Header uid missing**
- Everything loads by path. `--import`, loading and the running editor print nothing, and no file is rewritten.
- The first editor save adds the header uid, the ext_resource uids and the node unique_ids. It keeps hand-written `id=` values and all content, and drops `load_steps`.

**Stale ext_resource uid (not registered anywhere), correct path**
- `--import` prints nothing, because it does not load scenes.
- Loading prints `ext_resource, invalid UID: ... - using text path instead` and loads the correct file.
- An editor save replaces it with the real uid.

**ext_resource uid that belongs to a different existing file**
- The load silently returns the other file (tested: `path=c.tres` with d's uid gave D). No warning anywhere.
- A re-save rewrote `path=` to d.tres.

**Duplicate header uid, or duplicate script sidecar**
- `--import` only warns: `UID duplicate detected between X and Y`. Exit code is 0 and no file is rewritten.
- Whichever file is scanned last owns the uid. Every reference by that uid then silently resolves to it (tested: dup_ref.tscn with `path=a.tres` loaded b.tres).
- A *running* editor behaves differently when it discovers a new file whose uid is already used by an existing file. It rewrites the new file's header with a fresh uid and warns `Duplicate UID detected ... changed automatically`.
- It also rewrites the header of any newly added .tres or .tscn that has a uid (tested: `load_steps` was stripped). This does not apply to .gd sidecars.

**Missing script .uid sidecar**
- `--import` creates the sidecar, so a new untracked file appears.
- With a local `.godot` cache it warns `Missing .uid file ... re-created from cache`.
- On a fresh clone or in CI it silently creates a *new random* uid. Every .tres that referenced the old uid then warns `invalid UID` at load and falls back to the path.

**Import in general**
- `--headless --import` never rewrote an existing .tres or .tscn (checked with md5). It only adds .uid sidecars for scripts that lack one.
- Warnings are printed in English even with the Ukrainian editor UI. The exit code stays 0, so `check` has to parse the output.

**Generating files through ResourceSaver**
- In a plain `godot --headless -s tool.gd` run, `ResourceSaver.save` writes NO uids: no header uid and no ext_resource uids. The reason is that uid assignment is a callback that only the editor's filesystem installs.
- In editor context, `godot --headless -e -s tool.gd` (the tool waits until the first scan finishes), the output matched an editor save in every respect: header uid, ext_resource uids read from the sidecar or header, and node unique_ids. An in-place save kept the file's existing uid.
- This `-e -s` combination is not a documented workflow. It works in 4.7.2 (local test) and prints leaked-RID ERROR lines on exit.

**Hand-typed uids**
- Hand-typed uids are unsafe. The encoding has only 34 characters (a–y, 0–8) and at most 13 digits, so a made-up string may not round-trip. Generate uids with `ResourceUID.create_id()`.

2) WHAT THE OPEN EDITOR DOES WHEN FILES CHANGE ON DISK (source at 4.7.2-stable; not tested in the GUI)

**When it notices**
- On OS focus-in the editor runs `scan_changes()` and `_scan_external_changes()`.
- It compares each open scene's file time (1-second resolution on Windows) with the time it recorded. If the file is newer, it shows the dialog "Files have been modified outside Godot" with three buttons:
  - "Reload from disk": closes and reopens the scene, so unsaved edits are lost.
  - "Ignore external changes": calls `_save_scene`, overwriting the agent's file.
  - Cancel: nothing is resolved. The dialog comes back on the next focus-in, and any save in between overwrites the agent's file, because `_save_scene` has no timestamp check.

**Loaded .tres files**
- A changed .tres that is in the ResourceCache (for example, used by the open level) is reloaded silently on focus-in via `reload_from_file`.
- The unsaved-edits check below is only in the script editor; nothing in this path checks for unsaved inspector changes.

**Sub-scenes instanced in an open level**
- When the level's tab is activated, the editor sees that a sub-scene's file time changed. It re-packs the level, keeping local overrides, re-instantiates it and clears its undo history.

**Scripts**
- With `auto_reload_scripts_on_external_change` (default true), scripts reload silently unless they have unsaved changes in the script editor. In that case the editor asks.

**Settings that make it worse**
- `interface/editor/behavior/save_on_focus_loss` (default false): if enabled, it saves the current scene on *every* focus-out, even when nothing changed. A change the agent writes while the editor has focus is then overwritten with no prompt.
- `import_resources_when_unfocused` (default false): if enabled, the editor rescans every 0.5 s while unfocused, so the rewrites of new files described above happen while the agent is still working.
- `run/auto_save/save_before_running` (default true): F5 saves unsaved scenes.

3) OPTIONS FOR AGENT_WORKFLOW.md (for your approval; nothing has been applied)

**A. How the new-mechanic and new-level-piece skills write files**
- **A1 (recommended):** the agent writes the text by hand and then runs `tools normalize <files>`. That is an editor-context headless tool (`godot --headless -e -s`, waiting for the first scan). It loads each file and saves it through ResourceSaver; for .tscn it instantiates the scene in edit mode (`GEN_EDIT_STATE_MAIN`) and packs it, the way the editor does.
  - Rules: new files never copy a header uid (omit it and let normalize assign one), and .uid sidecars are never copied.
  - Pros: readable diffs, and files end up exactly as the designer's editor would save them, so her later saves produce small diffs.
  - Cons: relies on the undocumented `-e -s` combination, so it needs a smoke test on every Godot upgrade.
- **A2:** A generator tool for each content type that builds resources in code (a data dict goes in, a saved file comes out). It is always canonical, but it is more engine-side tooling for the engineer and gives the designer's agent less direct control.
- **A3:** Hand-write with fresh uids from a `uid` command, plus the static lint below. No engine tricks are needed, but ext_resource uids have to be copied correctly, and nodes lack unique_id until the designer's first save.
- **A4:** Hand-write path-only files with no uids at all. This is the simplest and can never point at the wrong file. The cost is uid noise in the first editor save and no protection when files move, so it is not recommended as the long-term form.

**B. `check` policy (recommended)**
- Run `--headless --import`. Fail on any output line matching `UID duplicate detected`, `Duplicate UID detected`, `Missing .uid file`, `invalid UID` or `Unrecognized UID`.
  - Known noise: issue #117362 reports `Unrecognized UID` errors at startup for uids used in project.godot. It was fixed only in 4.8. So reference main_scene and bus layout by `res://` path, or allowlist those lines.
- Fail if `git status --porcelain` after the import shows new or modified files. In practice that means a new `*.uid`, i.e. a script committed without its sidecar.
- Add a load pass: a runtime script that loads every .tres and .tscn under content/ and levels/, failing on any WARNING or ERROR line.
- Add a static UID lint (Python or GDScript, no engine needed). It checks that:
  - every uid is unique across .tres/.tscn headers, .uid sidecars and .import `[remap]` uids;
  - every ext_resource uid resolves to the same file as its `path=`. This is the one failure Godot itself never reports;
  - every .gd has a .uid sidecar;
  - optionally, content/ and levels/ files have a header uid and no `load_steps`.

**C. Working rule between the designer and her agent**
- **C1 (recommended): a close-first handoff.** The agent never writes, normalizes or git-pulls a .tscn or .tres that is open in the editor. The designer saves and closes that tab first (or the agent asks her to), and reopens it afterwards.
  - Content .tres that the open level only *uses* may be edited, provided she has no unsaved inspector edits to them.
  - Editing a sub-scene that is instanced in an open level is acceptable; she re-activates the level tab to pick it up.
  - Keep `save_on_focus_loss` off. If a reload prompt appears anyway, always click "Reload from disk", never "Ignore external changes".
  - Possible enforcement (not verified): a PreToolUse hook that blocks Edit/Write on .tscn/.tres files listed under `open_scenes` in `.godot/editor/editor_layout.cfg` while a GUI Godot process is running. That list is written with a delay, so it is only a heuristic.
- **C2: a worktree for the agent.** No dialogs appear while the agent works, and its headless `-e` or `--import` runs do not write to the `.godot` caches of her live editor. On the other hand, every worktree needs its own import, she cannot see the work in progress without opening the worktree as a project, and merging back into her checkout while scenes are open brings back the rule from C1.
- **C3: concurrent editing, relying on the dialog.** Not recommended, because either side can lose work silently.

**D. Single-owner scenes**
- Yes: "scenes are single-owner" also needs a human-vs-own-agent clause. Suggested wording: "a scene has one writer at a time: the editor tab or the agent, never both."
- The designer does spatial layout in the editor. The agent creates new sub-scenes and edits .tres data, and touches an existing level .tscn only on request with the tab closed.

**Not verified**
- None of the GUI dialog behavior was run; it is taken from the source.
- The following are inferred: behavior when the current tab is not re-activated, a same-second write escaping the timestamp check, and interference from two editor processes on one `.godot` folder.

Scratch test project: C:\Users\xperi\AppData\Local\Temp\claude\D--prime-game\40c5c58a-0dc5-4821-beca-a406804c7d8a\scratchpad\uidlab (tools/check.gd, gen.gd, gen_ed.gd, rescan_ed.gd, resave_ed.gd; logs in the parent scratchpad folder). Godot source files downloaded at 4.7.2-stable are in scratchpad\src.

### facts
- **gap3-01** Since Godot 4.4, scripts and shaders get a `<file>.uid` sidecar generated by the editor. `*.uid` must be committed and must not be in .gitignore. If UID references break, Godot still resolves them by path (the path is stored as a fallback) but prints a warning. Moving files outside the editor produces warnings until the dependent scenes are re-saved.  
  src: https://godotengine.org/article/uid-changes-coming-to-godot-4-4/ (blog)
- **gap3-02** 4.7 TSCN format: the header is `[gd_scene format=3 uid=...]` or `[gd_resource type=... format=3 uid=...]`. `load_steps` (pre-4.6) is deprecated and should be ignored. Nodes may have `unique_id=` (only in scenes saved with 4.6+, 'not guaranteed to be present'). ext_resource has type, uid, path and id.  
  src: https://docs.godotengine.org/en/4.7/engine_details/file_formats/tscn.html (official-docs)
- **gap3-03** The text loader reports custom UID support, so .tres and .tscn never get a .uid sidecar (should_create_uid_file returns false). Their uid lives only in the header.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/resource_format_text.cpp#L1580-L1582 and https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/resource_loader.cpp#L1428-L1440 (repo)
- **gap3-04** When loading an ext_resource whose uid is registered, the uid's path REPLACES the text path. Only when the uid is unknown does it print 'ext_resource, invalid UID: ... - using text path instead' and use the path.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/resource_format_text.cpp#L491-L506 (repo)
- **gap3-05** Test: wrong.tscn has `path=res://content/c.tres` but carries d.tres's uid. It loaded d.tres ('D') with no warning, in both runtime and editor mode.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab -s res://tools/check.gd (local-test)
- **gap3-06** Test: an editor-context re-save of wrong.tscn rewrote the ext_resource to `uid="uid://dhky75l4fxvbj" path="res://content/d.tres"`, so the wrong uid became canonical. An editor-context re-save of stale.tscn (unknown uid) replaced the uid with c.tres's real uid and kept the path.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab -e -s res://tools/gen_ed.gd (local-test)
- **gap3-07** Test: stale.tscn (unregistered ext uid, correct path) prints 'res://levels/stale.tscn:3 - ext_resource, invalid UID: uid://rvkbqxst06kv - using text path instead: res://content/c.tres' at load and loads the correct file. `--import` itself printed nothing for it.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab --import ; then -s res://tools/check.gd (local-test)
- **gap3-08** On the first scan (which is what `--import` runs), a duplicate uid only produces WARN 'UID duplicate detected between %s and %s.' and set_id() re-points the uid to the file scanned later. No file is rewritten.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp#L1398-L1411 (repo)
- **gap3-09** Test: a.tres and b.tres share a uid. `--import` printed 'WARNING: UID duplicate detected between res://content/b.tres and res://content/a.tres.' with exit code 0 and no files rewritten (md5 identical). dup_ref.tscn (`path=a.tres`, dup uid) then loaded b.tres ('B') silently, and load('uid://cljv4llohlgi1') returned b.tres.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab --import ; "$GODOT_BIN" --headless --path uidlab -s res://tools/check.gd (local-test)
- **gap3-10** Test: a newly copied .tres with a duplicate uid (copied_from_d.tres) run through `--import` against an existing .godot cache got a warning only; md5 was unchanged and the header kept the duplicated uid.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab --import (local-test)
- **gap3-11** In a running editor (a non-first scan, ACTION_FILE_ADD), a new file whose uid is used by another existing file gets a new uid written into its header via ResourceSaver::set_uid, with WARN 'Duplicate UID detected for Resource at ... The new file UID was changed automatically.' Otherwise, set_uid is still called to 're-assign' the existing uid, which rewrites the header line.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp#L920-L949 (repo)
- **gap3-12** ResourceFormatSaverText::set_uid rewrites the header in canonical form (`[gd_resource type=.. script_class=.. format=N uid=..]`) through a .uidren temp file and a rename.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/resource_format_text.cpp#L2161-L2229 (repo)
- **gap3-13** Test (editor context, EditorFileSystem.scan_sources after writing files): copied_from_c.tres (c's uid) was rewritten to a new uid with the 'Duplicate UID detected ... changed automatically' warning. new_legacy.tres had `load_steps=2` stripped from its header. new_nouid.tres (no uid) was left untouched.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab -e -s res://tools/rescan_ed.gd (local-test)
- **gap3-14** PR #100927 (4.4) added the automatic new-uid-on-duplicate behavior. It says this works for scenes and resources but not for scripts, because set_uid is not implemented for .uid files, and that copying the .uid file along with a file is something 'you shouldn't do'.  
  src: https://github.com/godotengine/godot/pull/100927 (repo)
- **gap3-15** Test: copying item_data.gd together with its .uid produced 'UID duplicate detected between res://scripts/item_data_copy.gd and res://scripts/item_data.gd.' from `--import` (exit code 0), and uid_to_path of that uid then returned item_data_copy.gd.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab --import ; -s res://tools/check_script.gd (local-test)
- **gap3-16** A missing script .uid is created during the scan. If the uid was known from the cache, it warns 'Missing .uid file for path "%s". The file was re-created from cache.'; otherwise it silently creates a new uid.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp#L1384-L1395 (repo)
- **gap3-17** Test: deleting item_data.gd.uid while .godot was present gave the 're-created from cache' warning and the same uid. Deleting .godot as well (fresh-clone simulation) silently produced a NEW uid (uid://b1amlyk8cof6q), after which every .tres referencing the old uid printed 'invalid UID ... using text path instead' at load. `--import` also silently created .uid sidecars for new scripts, which show up as untracked files in git status.  
  src: local-test: rm scripts/item_data.gd.uid [.godot]; "$GODOT_BIN" --headless --path uidlab --import; git status --short (local-test)
- **gap3-18** `--import`: 'Starts the editor, waits for any resources to be imported, and then quits. Implies --editor and --quit.' `-s/--script`: 'Run a script.' `-e/--editor`: 'Start the editor instead of running the scene.' No combined `-e -s` workflow is documented.  
  src: https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html (official-docs)
- **gap3-19** ResourceSaver::get_resource_id_for_path returns INVALID_ID unless a callback is installed, and only EditorFileSystem installs it. The text saver uses it for the header uid (generate=true) and for ext_resource uids (generate=false).  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/resource_saver.cpp#L285-L294 ; https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp#L3817 ; https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/resource_format_text.cpp#L1812-L1816 (repo)
- **gap3-20** Test: in a runtime-mode `-s` tool (editor_hint=false), ResourceSaver.save wrote `[gd_resource type="Resource" script_class="ItemData" format=3]` and ext_resources without uid. The same tool in editor mode (`-e -s`, waiting for EditorFileSystem to stop scanning) wrote a header uid and ext_resource uids (script uid taken from its sidecar). An in-place save of c.tres kept uid://gr8upidggmur.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab -s res://tools/gen.gd vs -e -s res://tools/gen_ed.gd (local-test)
- **gap3-21** Test: an editor-style save (instantiate with GEN_EDIT_STATE_MAIN, pack, then ResourceSaver.save in place, in editor context) of a hand-written room scene added the header uid and the ext_resource uid, dropped load_steps, and added unique_id to every node. It kept the hand-written ext id '1_item', the sub_resource id 'BoxMesh_floor' and all property lines.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab -e -s res://tools/resave_ed.gd ; diff hand_room.orig.tscn levels/hand_room.tscn (local-test)
- **gap3-22** At pack time, nodes with an unassigned or clashing unique_id get a new random one.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/packed_scene.cpp#L1099-L1123 (repo)
- **gap3-23** UID text uses 34 characters (a-y, 0-8; 'z' and '9' are never used) and at most 13 digits. text_to_id masks to 63 bits. create_id_for_path is seeded from the project name, the lower-cased path and the file MD5.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/resource_uid.cpp#L42-L155 (repo)
- **gap3-24** On NOTIFICATION_APPLICATION_FOCUS_IN the editor calls EditorFileSystem::scan_changes() and _scan_external_changes(). On focus-out, if interface/editor/behavior/save_on_focus_loss is set, it calls _save_scene_silently().  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L1049-L1068 (repo)
- **gap3-25** _scan_external_changes flags an open scene when FileAccess::get_modified_time(scene) > the recorded modified time, and pops up the 'Files have been modified outside Godot' dialog. Its buttons are 'Reload from disk' (_reload_modified_scenes: _remove_edited_scene then open_scene) and 'Ignore external changes' (custom action 'resave', which calls _resave_externally_modified_scenes and then _save_scene for each changed scene).  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L1550-L1632 ; https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L9354-L9379 (repo)
- **gap3-26** Issue #106410 and PR #106714 (4.5) confirm the intent that 'Ignore External Changes' re-saves the externally modified scenes, i.e. writes the editor's version over the external edit.  
  src: https://github.com/godotengine/godot/issues/106410 ; https://github.com/godotengine/godot/pull/106714 (issue)
- **gap3-27** EditorNode::_save_scene packs and saves without checking the on-disk timestamp, so any save of a stale open scene overwrites external changes.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L2466-L2540 (repo)
- **gap3-28** _save_scene_silently (used by save_on_focus_loss) saves the current scene unconditionally, even when unmodified. The setting defaults to false. The docs say 'scenes and scripts are saved when the editor loses focus'.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L2432-L2441 ; https://github.com/godotengine/godot/blob/4.7.2-stable/editor/settings/editor_settings.cpp#L535 ; https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/EditorSettings.xml#L1018-L1020 (repo)
- **gap3-29** Changed non-imported files that are already in the ResourceCache are queued as reloads. EditorNode::_resources_changed then calls res->reload_from_file() (copy_from the freshly loaded file), with no prompt and no check for unsaved edits.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/file_system/editor_file_system.cpp#L1018-L1026 ; https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L1291-L1325 ; https://github.com/godotengine/godot/blob/4.7.2-stable/core/io/resource.cpp#L263-L276 (repo)
- **gap3-30** When a scene tab is activated, EditorData::check_and_update_scene checks whether any instanced or inherited sub-scene file's mtime changed. If so, it re-packs the open scene from memory (keeping local changes as diffs), re-instantiates it, and EditorNode clears that scene's undo history.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_data.cpp#L722-L800 ; https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L4747-L4753 (repo)
- **gap3-31** The script editor: with text_editor/behavior/files/auto_reload_scripts_on_external_change (default true), changed scripts reload silently unless the tab has unsaved changes, in which case a conflict dialog is shown.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/script/script_editor_plugin.cpp#L803-L840 ; https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/EditorSettings.xml#L1502-L1505 (repo)
- **gap3-32** If interface/editor/behavior/import_resources_when_unfocused is true (default false), a 0.5 s timer runs EditorFileSystem::scan_changes while unfocused. run/auto_save/save_before_running defaults to true, and Save All only saves scenes with unsaved changes.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L1103-L1107 ; https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L2590-L2615 ; https://github.com/godotengine/godot/blob/4.7.2-stable/editor/settings/editor_settings.cpp#L556 (repo)
- **gap3-33** On Windows, Godot's file modified time has 1-second resolution (FILETIME / 10^7), and the scene check uses `date > last_date`. So an agent write in the same second as the editor's last save or open of that scene would not trigger the dialog. The consequence is inferred.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/file_access_windows.cpp#L412-L455 (inferred)
- **gap3-34** The editor saves the list of open scenes as `open_scenes` and `current_scene` in .godot/editor/editor_layout.cfg, and writes it with a delay on scene switch and open. Using it as a signal for a PreToolUse hook is inferred and only a heuristic.  
  src: https://github.com/godotengine/godot/blob/4.7.2-stable/editor/editor_node.cpp#L6278-L6309 (inferred)
- **gap3-35** Issue #117362: 'Unrecognized UID' errors at editor start for uid:// references in project.godot (main_scene, default_bus_layout), reported on 4.6.1. The fix PR #123024 was merged 2026-09-07 with milestone 4.8, after the 4.7.2-stable tag commit dated 2026-08-17.  
  src: https://github.com/godotengine/godot/issues/117362 ; https://github.com/godotengine/godot/pull/123024 (issue)
- **gap3-36** Test: import and load warnings (WARN_PRINT) were printed in English even though the editor UI and progress messages were Ukrainian. `--import` returned exit code 0 with duplicate-UID warnings. Headless `-e -s` runs print 'RID allocations ... leaked at exit' ERROR lines on quit.  
  src: local-test: "$GODOT_BIN" --headless --path uidlab --import ; -e -s res://tools/gen_ed.gd (local-test)
- **gap3-37** Headless editor runs (`--import`, `-e -s`) write .godot/uid_cache.bin, .godot/editor/filesystem_cache10, global_script_class_cache.cfg and project_metadata.cfg. Running them on the same folder as the designer's open GUI editor could interfere with its caches (inferred, not tested).  
  src: local-test: ls uidlab/.godot uidlab/.godot/editor after runs (inferred)
## If a subagent's frontmatter, an Agent call or a workflow stage selects `fable` on the humans' Pro/Max plans, does Claude Code bill usage credits, show a consent prompt, or quietly continue on the default model? Is that different for background subagents and workflow agents? Does `availableModels` in the shared .claude/settings.json, or an Agent(model:fable) deny rule, reliably block it at the subagent and workflow level? And how do subagents and ultracode fan-out count against plan limits?
confidence: medium

DIRECT ANSWER

1. Whether Fable costs money depends on the plan. It does not depend on whether a subagent or a workflow sends the request.
- Pro, and Team standard seats: Fable is not included in the plan. Every Fable request uses paid usage credits from the first token. That covers the main session, subagents and workflow agents (gap4-02). Usage credits are off by default (gap4-04).
- Max: Fable is included, but only up to 50% of the weekly limit, tracked as a separate "Weekly · Fable" bucket. Past that, Fable uses usage credits if they are turned on (gap4-03, gap4-37).
- On this machine the logged-in account is Max 5x (gap4-11). The designer's plan is unknown. If the designer is on Pro, a shared agent file with `model: fable` means money from the first request in their sessions.
- Subagent and workflow-agent requests count against the same limits as the main conversation (gap4-25).

2. The consent prompt is documented only at the session level.
- In an interactive session it appears once. After someone picks "continue on Fable", it never appears again. From then on, Fable requests bill without asking. That this also covers subagent and workflow requests is inferred.
- Dismissing the prompt mid-session continues the turn on the default model. That is the silent downgrade (gap4-05).
- `-p` and Agent SDK runs never show a prompt and bill without asking (gap4-06).
- Background sessions, Remote Control and agent-team teammates hold the prompt for 5 minutes (`dialogExpiry`). Then the turn ends and nothing is sent (gap4-07, gap4-08).
- The Desktop Code tab is an SDK-hosted session running bundled Claude Code 2.1.281 (gap4-10). On 2.1.281, an unanswered Fable prompt there switched models. Only 2.1.282 changed it to end the turn instead (gap4-09).
- NOT documented: what happens when a foreground subagent, a background subagent (`run_in_background`) or a workflow `agent()` requests Fable before consent was given. It could raise the prompt, fail, or run on another model (gap4-12). The workflows page names only permission prompts and usage-limit waits as reasons a run pauses (gap4-13).
- This cannot be tested without risking a charge, so the setup should make it impossible rather than rely on it.
- Separately, Fable and Opus 5.5 requests flagged by the cybersecurity safety filter re-run on Opus 4.8, with a notice in the transcript. This matters for `netcode-security-reviewer` (gap4-31).

3. `availableModels` mostly works; an `Agent(model:fable)` deny rule does not.
- The docs say `availableModels` applies to subagent frontmatter, the Agent tool's `model` parameter, `CLAUDE_CODE_SUBAGENT_MODEL`, skills, teammates, background-agent dispatch and workflow agents (gap4-15, gap4-17).
- A blocked `fable` falls back to the inherited session model, with a warning. The warning appears in interactive sessions and in the `/workflows` progress view (gap4-16, gap4-17).
- It is valid in project settings (gap4-18). But outside managed settings, the user, project and local lists are merged together. So it is a shared guard that either human can widen in their own user or local settings, not enforcement.
- Hard enforcement needs managed settings. `deniedModels` and `availableModelsMatch` are managed-only and need 2.1.283; the bundled version is 2.1.281 (gap4-19).
- It does not constrain the Default option (the account's default model), but Fable is never the default (gap4-20). The `best` alias resolves to Fable where Fable is available (gap4-21). An allowlist without fable most likely makes `best` fall back to opus (inferred).
- An `Agent(model:fable)` deny matches only the literal value `fable` when Claude passes it in an Agent tool call (gap4-22). It misses:
  - `model: fable` set in frontmatter
  - `claude-fable-5-1` and `best`
  - the environment variable
  - a Fable model inherited from the main session
  - every workflow stage, because the Workflow tool's input has no model field (gap4-23, gap4-24)
- Such a rule can only supplement `availableModels`, not replace it.

4. Fan-out spends plan limits, and money only if usage credits are on.
- Every subagent and workflow agent sends its own requests against the same plan limits (gap4-25, gap4-26).
- Ultracode runs xhigh effort and can start several workflows per request. It also turns off the "Large workflow" warning, the 20-subagent concurrency cap and the first-launch approval in auto mode (gap4-27).
- Default workflow size guidance is fewer than 10 agents, or fewer than 5 on Pro. Up to 16 agents run at once, with at most 1000 per run (gap4-28).
- Interactive runs pause at a usage limit. Runs in background sessions or `-p` do not (gap4-29).
- Workflow agents inherit the session model unless the script names one. A session on Fable therefore turns the whole fan-out into Fable (gap4-34).
- If usage credits are ON, going past any plan limit switches to pay-as-you-go automatically with no confirmation per request, for every model (gap4-04). Ultracode plus credits on means spending with no cap unless a monthly spend limit is set.
- Fable costs 2.5x Opus 5.5 per token at list price (gap4-30).

5. Version skew. Desktop runs 2.1.281, but the `claude` on PATH is 2.1.195 (gap4-10). 2.1.195 predates several features the options below rely on: Fable 5.1, `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, the workflow-agent restricted-model warning, the consent deadline, and the usage-limit pause.

OPTIONS FOR APPROVAL (not applied)
- O1 (recommended):
  - Set `code-reviewer` to `model: opus` (Opus 5.5).
  - Reword the claim as "the strongest model included in both plans".
  - Add `"availableModels": ["opus","sonnet","haiku"]` to the shared `.claude/settings.json` as a guard.
  - Verify routing (see "Routing verification" below).
- O2: O1 plus extra deny rules `Agent(model:*fable*)` and `Agent(model:best)`. Optionally add a PreToolUse hook on `Workflow` that rejects scripts containing `fable` or `best`.
- O3: Fable only as an engineer opt-in.
  - A personal `~/.claude/agents/code-reviewer-deep.md` with `model: fable`, plus `fable` in the engineer's own `.claude/settings.local.json` `availableModels` (the lists merge).
  - Called only on explicit request, never inside workflows.
  - Costs part of the Max 5x weekly Fable allowance.
- O4 (not recommended): `model: fable` in the shared agent file with no guard. Pro pays from the first request, Max burns the Fable bucket, and the silent-downgrade paths make "strongest model" unverifiable.
- O5 (not recommended): set `CLAUDE_CODE_SUBAGENT_MODEL=opus` plus `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`. This forces every subagent, teammate and workflow agent onto one model and removes the haiku or sonnet routing for cheaper agents (gap4-33).
- Account-level, done by the humans outside the repo: keep usage credits OFF on both accounts, or set a monthly spend limit at claude.ai/settings/usage. This is the only hard stop on money. Also, never select Fable or `best` in the Desktop model dropdown for ultracode sessions. Optional: set `dialogExpiry` in user settings.
- Effort policy changes:
  - Run ultracode sessions on Opus 5.5.
  - Set `workflowSizeGuideline` in the shared settings (for example `"medium"`).
  - Use cheaper per-stage models (haiku or sonnet) for mechanical stages.
  - Test each new workflow on a small slice first.

Routing verification:
- `/tasks` shows the model on each subagent row (2.1.242 and later).
- The transcripts at `~/.claude/projects/D--prime-game/<session>/subagents/**/agent-*.jsonl` record the serving model on each message, including workflow agents. This was checked locally (gap4-32).
- These give ground truth, which matters because there is an open, unconfirmed report of Fable requests being served by another model without warning (gap4-36).

### facts
- **gap4-01** Neither Fable model is the account-type default on any plan; select explicitly (/model fable or --model fable). The `fable` alias resolves to Fable 5.1 (v2.1.257+), Fable 5 on earlier versions.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **gap4-02** Pro plans and standard Team seats: Fable 5/5.1 aren't included in plan usage limits; 'Fable models run on pay-as-you-go usage credits from the start'.  
  src: https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan (official-docs)
- **gap4-03** Max plans: Fable 5 and 5.1 are included; 'You can use up to 50% of your weekly usage limits on Fable models at no extra cost'; after that, keep using Fable with usage credits or switch models.  
  src: https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan (official-docs)
- **gap4-04** Usage credits are disabled by default and enabled in Settings > Usage; once enabled with funds, usage switches to pay-as-you-go at API rates when plan limits are exceeded with no per-request confirmation; monthly spend cap and auto-reload are available; they apply to Claude Code.  
  src: https://support.claude.com/en/articles/12429409-manage-usage-credits-for-paid-claude-plans (official-docs)
- **gap4-05** In interactive sessions Claude Code shows a consent prompt before a Fable request bills usage credits; mid-session dismissal continues the turn on the default model; 'After you choose to continue on Fable using usage credits, Claude Code doesn't show the prompt again.' The /model picker marks the row 'Requires usage credits'.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **gap4-06** In non-interactive mode (-p) and through the Agent SDK, Claude Code never shows the consent prompt; a Fable request that would bill usage credits is billed without asking.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **gap4-07** With Remote Control, in a background session (agent view), or in an agent-team teammate session, the mid-session consent prompt is held until dialogExpiry (5 min default); if unanswered the turn ends without sending, the model is unchanged, and consent is asked again on the next message. The unanswered-prompt error messages name 'the session's Fable model'.  
  src: https://code.claude.com/docs/en/errors.md (official-docs)
- **gap4-08** dialogExpiry (User or managed scope; 60s/5m/10m/never; default 5m) sets the deadline for dialogs forwarded to Remote Control or an SDK host, and on v2.1.236+ bounds the mid-session Fable usage-credits consent prompt; on timeout Claude Code continues with its no-action default.  
  src: https://code.claude.com/docs/en/settings-reference.md (official-docs)
- **gap4-09** v2.1.282 changelog: 'Fixed an unanswered Fable usage-credits prompt switching models in SDK-hosted sessions such as Claude Desktop; the turn now ends instead'.  
  src: https://code.claude.com/docs/en/changelog (changelog)
- **gap4-10** The Desktop Code tab session runs bundled Claude Code 2.1.281 (CLAUDE_CODE_EXECPATH=...\AppData\Roaming\Claude\claude-code\2.1.281\claude.exe, CLAUDE_CODE_ENTRYPOINT=claude-desktop, CLAUDE_AGENT_SDK_VERSION=0.3.281), while `claude` on PATH (~/.local/bin/claude) reports 2.1.195.  
  src: local-test: env | grep CLAUDE; "$CLAUDE_CODE_EXECPATH" --version; claude --version (local-test)
- **gap4-11** The account logged in on this machine has oauthAccount.organizationRateLimitTier = 'default_claude_max_5x' (Max 5x); additionalModelOptionsCache lists claude-fable-5-1[1m]. The designer's plan is not visible from here.  
  src: local-test: python read of ~/.claude.json (keys matching plan/tier/fable only) (local-test)
- **gap4-12** No primary source documents whether a Fable request from a foreground subagent, background subagent or workflow agent triggers the consent prompt, fails, or runs on another model when consent has not been given; the model-config and errors docs describe consent only at session level.  
  src: https://code.claude.com/docs/en/model-config.md (inferred)
- **gap4-13** Workflow runtime: 'No mid-run user input — A run pauses on its own only for agent permission prompts and a usage-limit wait'.  
  src: https://code.claude.com/docs/en/workflows.md (official-docs)
- **gap4-14** Subagent model order: per-invocation `model` param > frontmatter `model` (inherit = main model) > CLAUDE_CODE_SUBAGENT_MODEL > main model. A family alias such as `fable` resolves to the main session's exact model when the main session is in that family. Workflow agents use the same order; a model the script names for a stage counts as the per-invocation model; otherwise they run on the session model.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **gap4-15** When availableModels is set it applies to the main session model, alias env vars, fast mode, subagent frontmatter `model`, the Agent tool's `model` parameter, teammate models, CLAUDE_CODE_SUBAGENT_MODEL, skill/command model frontmatter, advisorModel, and the background-agent dispatch picker.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **gap4-16** For a blocked subagent model: a blocked family alias runs on the newest permitted version of that family; if the allowlist permits no version of the family (or for other blocked values), the subagent runs on the inherited model. In interactive sessions a warning names the requested and substituted models.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **gap4-17** When the availableModels allowlist blocks a model a workflow script requests for an agent, the agent runs on a substituted model and the /workflows progress view shows a warning naming both. Changelog 2.1.223 added this warning for workflow agents, forked skills, slash commands and resumed background agents.  
  src: https://code.claude.com/docs/en/workflows.md (official-docs)
- **gap4-18** availableModels scope is 'Any file' (user, project .claude/settings.json, local, managed). If managed settings define it, that list alone applies; otherwise lists from user, project and local settings are concatenated and deduplicated. An entry naming a specific version disables that family's wildcard.  
  src: https://code.claude.com/docs/en/settings-reference.md (official-docs)
- **gap4-19** deniedModels and availableModelsMatch are Managed-scope only, require Claude Code v2.1.283+, and are ignored with a warning in user, project and local settings and --settings.  
  src: https://code.claude.com/docs/en/settings-reference.md (official-docs)
- **gap4-20** With default prefix matching, availableModels leaves the /model Default option on the account's runtime default unless enforceAvailableModels is set.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **gap4-21** The `best` alias 'Uses the model the fable alias resolves to where Fable is available to you, otherwise the same model as opus'.  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **gap4-22** Deny/ask rules can match a top-level input parameter, e.g. `Agent(model:opus)`. The value is compared against the literal input before normalization (alias does not match a full ID); `*` wildcards are supported; a parameter the model omits is never matched.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **gap4-23** The Workflow tool's input is {script | name | scriptPath, args, resumeFromRunId}; it has no model field, and stage models live inside the script string. Conclusion (inferred): no Agent(model:...) rule can see workflow stage models.  
  src: https://code.claude.com/docs/en/agent-sdk/typescript.md (inferred)
- **gap4-24** Workflow agent() options include `model` (per-agent override; the default is to inherit the main-loop model) and `agentType` (uses a custom subagent from the same registry as the Agent tool).  
  src: local-test: bundled /workflow-authoring skill text loaded in this session (Claude Code 2.1.281) (local-test)
- **gap4-25** Each subagent 'sends its own requests, which count toward the same usage limits as your main conversation'; /usage on Pro/Max shows usage attribution including subagents.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **gap4-26** Workflow runs 'count toward your plan's usage and rate limits'; a single run can use meaningfully more tokens; a 'Large workflow' warning (advisory only) appears above 25 agents or 1.5M projected tokens.  
  src: https://code.claude.com/docs/en/workflows.md (official-docs)
- **gap4-27** Ultracode = xhigh effort plus automatic workflow planning for every substantive task; one request can become several workflows; on subscriptions it reaches session or weekly limits sooner. While it is on, the Large workflow warning, the concurrent subagent limit and the auto-mode first-launch approval are skipped.  
  src: https://code.claude.com/docs/en/workflows.md (official-docs)
- **gap4-28** Workflow size guideline defaults to medium (<10 agents), or small (<5) on Pro with v2.1.271+; settable via the workflowSizeGuideline key in any settings file (advisory). Up to 16 concurrent agents by default; 1,000 agents per run.  
  src: https://code.claude.com/docs/en/workflows.md (official-docs)
- **gap4-29** From v2.1.271, a workflow pauses at a claude.ai usage limit and resumes after reset, only if the session is interactive on a subscription, autoContinueAtUsageLimit is on, the reset is within 24h and the run hasn't already waited twice. It does not pause in -p, the Agent SDK, background sessions, Remote Control or teammate sessions.  
  src: https://code.claude.com/docs/en/workflows.md (official-docs)
- **gap4-30** API list pricing: Claude Fable 5.1 $10/$50 per MTok input/output; Claude Opus 5.5 $4/$20; Sonnet 5.5 $2/$10; Haiku 4.5 $1/$5.  
  src: https://platform.claude.com/docs/en/about-claude/models/overview (official-docs)
- **gap4-31** Fable 5.1, Fable 5 and Opus 5.5 run safety classifiers; cybersecurity-flagged requests re-run on Opus 4.8 and biology-flagged ones on Opus 5, with a transcript notice; switchModelsOnFlag=false pauses instead (interactive) or errors (-p).  
  src: https://code.claude.com/docs/en/model-config.md (official-docs)
- **gap4-32** /tasks names the model on each subagent row (v2.1.242+). Locally, workflow agent transcripts at ~/.claude/projects/D--prime-game/<session>/subagents/workflows/<wf_id>/agent-*.jsonl record a per-message "model" field (this run's agents show claude-opus-5-5 and claude-haiku-4-5-20251001).  
  src: local-test: grep -o '"model":"[^"]*"' ~/.claude/projects/D--prime-game/40c5c58a-.../subagents/workflows/*/agent-*.jsonl (local-test)
- **gap4-33** Setting CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 (v2.1.257+) applies one model to every subagent, teammate and workflow agent, ignoring per-spawn and definition models.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **gap4-34** User report: a 16-agent audit workflow launched while the session model was claude-fable-5 ran all 16 subagents on Fable in parallel (2,448 Fable messages in 18 minutes) without cost confirmation.  
  src: https://github.com/anthropics/claude-code/issues/84667 (issue)
- **gap4-35** User reports (Desktop Code tab, Max 20x and Team): an Opus session with `model: fable` subagents consumed the 'Weekly · Fable' bucket; the usage banner mislabels it as the Opus limit.  
  src: https://github.com/anthropics/claude-code/issues/93046 (issue)
- **gap4-36** Open, unconfirmed report: requests for claude-fable-5/5-1, including an Agent-tool subagent pinned to Fable, were answered by another model (e.g. claude-opus-4-8) with HTTP 200 and no visible warning; only transcript/modelUsage show it.  
  src: https://github.com/anthropics/claude-code/issues/91747 (issue)
- **gap4-37** Changelog 2.1.251: fixed `claude --bg --model fable` on Max plans asking for usage credits while the interactive session still had Fable allowance; 2.1.283: fixed the weekly Fable limit not appearing in /usage.  
  src: https://code.claude.com/docs/en/changelog (changelog)
- **gap4-38** The project has only .claude/settings.local.json (no shared settings.json yet); ~/.claude/settings.json contains an undocumented key "skipWorkflowUsageWarning": true and no model/availableModels; no C:\Program Files\ClaudeCode managed-settings file exists.  
  src: local-test: ls D:/prime-game/.claude; grep model|available|workflow ~/.claude/settings.json; ls 'C:/Program Files/ClaudeCode' (local-test)
- **gap4-39** Workflow agents' prompt cache lasts 5 minutes by default even on a subscription (subagentPromptCacheTtl can set 1h); agents with identical model, effort, agent type, tools, schema and cwd share a cache prefix.  
  src: https://code.claude.com/docs/en/workflows.md (official-docs)
## Where should machine-specific env (GODOT_BIN, GODOT_GUI_BIN, PYTHON_BIN, GDTOOLKIT_DIR) live so that it reliably reaches PowerShell and Bash tool calls, command hooks, subagents and workflow agents in Desktop 2.1.281 local sessions, including Desktop worktree sessions on Windows?
confidence: medium

DIRECT ANSWER (proposal only; nothing has been changed)
The most reliable single location is the `env` key in each human's `~/.claude/settings.json` (%USERPROFILE%\.claude\settings.json). Claude Code reads that file from the same place whatever the session's working directory is, so a Desktop worktree session under .claude/worktrees/ gets it too. Desktop starts Claude Code with `--setting-sources=user,project,local`, so user settings are loaded. Env from user settings is applied at startup with no trust check. Claude Code writes `env` values into its own process environment, so PowerShell and Bash tool calls, command hooks, subagents and workflow agents all inherit them.

KICKOFF §6's `.claude/settings.local.json` also works in the main checkout. I confirmed that locally: this workflow agent sees all four variables in both shells, and that file is their only source. It is not reliable for Desktop worktree sessions on Windows as things stand. On Windows the local file is read from the session's primary working directory, which is the worktree, not the repository root. The file is gitignored, so it is not checked out into the worktree.

It becomes reliable only if you add both of these:
(a) a `.worktreeinclude` in the repo root listing `.claude/settings.local.json`;
(b) a real entry for that file in the repo's `.gitignore`. KICKOFF line 147 already requires this.

The entry in (b) is essential on this machine. The global excludes file (~/.config/git/ignore) contains `**/.claude\settings.local.json` with a backslash. Git reads a backslash as an escape, so that line does not ignore the file. `git check-ignore` returned exit 1 in a scratch repo, and git listed the file as untracked. `.worktreeinclude` only copies files git considers ignored, so without (b) nothing would be copied, and `git add -A` could commit the file.

A copied, untracked settings.local.json raises no trust problem:
- Trust is keyed on the main checkout's root, including for worktrees.
- Desktop runs Claude Code in SDK stream-json mode, which counts as trusted, and in that mode project and local `env` apply at startup.
- The permissions doc's trust table lists the `env` block as "Used" even when only a parent folder is trusted.

The limit is that the copy is a snapshot. Worktrees created before the `.worktreeinclude` existed, or before a path changed, keep stale or missing values.

OPTIONS FOR APPROVAL
A. Keep project `.claude/settings.local.json` (KICKOFF §6), plus a `.worktreeinclude` entry and a repo `.gitignore` entry.
   - Pros: scoped to this project; the agent can write it for the human; a changed value takes effect in the running session when the file is saved.
   - Cons: snapshot copy per worktree; depends on the repo `.gitignore` entry because the global exclude line is broken; on Windows, "don't ask again" approvals made in a worktree stay in that worktree's copy.
B. `env` in `~/.claude/settings.json` (user scope).
   - Pros: reaches every Claude Code session on the machine in any checkout or worktree, including Desktop, the CLI and IDE sessions; no trust gate; desktop.md names it for local sessions.
   - Cons: applies to every project on the machine; does not reach Desktop preview/dev servers; it is outside the repo, so the agent must ask before editing it; if a project or local settings file sets the same key, that value wins.
C. Desktop local environment editor (environment dropdown → Local → gear icon).
   - Pros: applies to every Desktop local session and preview server; stored encrypted.
   - Cons: GUI-only, so agents can neither script nor inspect it, and `doctor` can only see the effect; does not reach CLI sessions, such as the `claude` 2.1.195 on PATH in Rider's terminal; encryption adds nothing, since these values are not secrets.
D. `.worktreeinclude` is not a location on its own. It is the add-on that makes option A work in worktrees.
E. (Not in the brief's list) Windows user environment variables (System Properties or setx). The Desktop app inherits user and system environment variables.
   - Pros: reaches everything, including tools outside Claude.
   - Cons: the human must set them; the Desktop app must be restarted to pick them up.

RISKS THAT APPLY TO EVERY OPTION
- Set each variable in only one place. Settings `env` normally overrides the launch environment, but the 2.1.281 changelog mentions settings `env` variables being "ignored because the session's launch environment already sets them". So mixing C or E with A or B can behave in ways the docs don't spell out.
- Exec-form hooks (hooks with `args`) do not expand `$PYTHON_BIN`, because no shell is involved. The Python hook needs shell form: Git Bash, the default on Windows, with `"$PYTHON_BIN" ...`, or `"shell": "powershell"` with `& $env:PYTHON_BIN ...`.
- `CLAUDE_ENV_FILE` or a SessionStart hook is not an alternative, because it only affects Bash commands, not the primary PowerShell tool.

WHAT `doctor` SHOULD CHECK
1. Each variable is set and points to an existing file or folder.
2. `git check-ignore -q .claude/settings.local.json` succeeds.
3. When running in a linked worktree (`git rev-parse --git-dir` differs from `--git-common-dir`), warn if `.claude/settings.local.json` is missing and the variables are unset.

DESIGNER SETUP STEP
Option B: ask Claude to add the four paths to `env` in the user settings and approve that edit.
Option A: create `.claude/settings.local.json` in the main checkout before opening any worktree session.

UNVERIFIED
I did not test a live Desktop worktree session, because D:\prime-game is not yet a git repository. The claims that the worktree session's working directory is the worktree and that subagent and workflow worktrees inherit the parent's process env rather than reloading settings are inferred from the docs.

### facts
- **gap5-01** The project-local file normally lives at the git repository root (in a worktree, the main checkout's root), but it 'stays with .claude/settings.json instead' outside a git repository, when the root is the home directory, 'on Windows', or when the root, .git or .claude isn't owned by the user. Claude Code reads the shared .claude/settings.json from the session's primary working directory.  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **gap5-02** Hooks and other .claude/settings.json keys load from the current working directory's .claude/ folder with no parent-directory fallback. .claude/settings.local.json loads from the git repository root except where Claude Code doesn't use the repository root, 'such as on Windows'. Agent SDK sessions load it from the working directory in all versions.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **gap5-03** 'Yes, and don't ask again' in a worktree saves to the main checkout's .claude/settings.local.json, but 'On Windows and in the other cases where Claude Code doesn't use the repository root, the rule stays with that worktree.' This page also says the read-through for untracked skills, agents and commands (not settings) applies to worktrees created by --worktree, git worktree add, or the desktop app.  
  src: https://code.claude.com/docs/en/worktrees.md (official-docs)
- **gap5-04** From --add-dir directories, only the enabledPlugins and extraKnownMarketplaces keys are loaded from .claude/settings.json and .claude/settings.local.json.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **gap5-05** .worktreeinclude uses .gitignore syntax; 'Only files that match a pattern and are also gitignored are copied'. It applies to --worktree worktrees, subagent worktrees and parallel sessions in the desktop app, and is not processed when a WorktreeCreate hook replaces git worktree creation.  
  src: https://code.claude.com/docs/en/worktrees.md (official-docs)
- **gap5-06** On this machine ~/.config/git/ignore contains '**/.claude\settings.local.json' (with a backslash). In a scratch repo, `git check-ignore -v .claude/settings.local.json` returned exit 1 and `git status` listed the file as untracked. After adding '.claude/settings.local.json' to the repo .gitignore, check-ignore matched it (exit 0). core.excludesFile is unset, so the default XDG file is the one in use.  
  src: local-test: git init in scratchpad; git check-ignore -v .claude/settings.local.json; git status --porcelain; od -c ~/.config/git/ignore; git config --global core.excludesFile (local-test)
- **gap5-07** In gitignore patterns, 'The slash "/" is used as the directory separator' and 'A backslash ("\") can be used to escape any character'. The default core.excludesFile is $XDG_CONFIG_HOME/git/ignore, or $HOME/.config/git/ignore.  
  src: https://git-scm.com/docs/gitignore (official-docs)
- **gap5-08** settings.md says that the first time Claude Code writes settings.local.json in a git repo that doesn't already ignore it, it adds '**/.claude/settings.local.json' to the global git excludes file. If the file was created by hand, the user should add it to .gitignore.  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **gap5-09** KICKOFF.md line 147 already requires the repo to ignore .claude/settings.local.json, and lines 421-425 prescribe machine-specific env in .claude/settings.local.json.  
  src: local-test: Grep D:\prime-game\KICKOFF.md for settings.local (repo)
- **gap5-10** Workspace trust is keyed on the git repository root; 'In a worktree, it uses the main checkout's root'. For settings.local.json, Claude Code runs git to check whether the file is tracked, and runs it once the folder is trusted or in a -p/SDK session, 'which counts as accepted'. An untracked file's rules then apply.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **gap5-11** In the 'What runs before you trust a folder' table, 'the env block' in settings files is 'Used' both when only a parent folder is trusted and under claude -p / SDK when the folder was never trusted.  
  src: https://code.claude.com/docs/en/permissions.md (official-docs)
- **gap5-12** env from user settings, --settings and managed settings applies at startup. env from project and local settings applies 'after you trust the workspace, or at startup in -p mode'. env sets variables 'for every session and for the subprocesses Claude Code starts from it'.  
  src: https://code.claude.com/docs/en/settings-reference.md (official-docs)
- **gap5-13** The running Desktop session's Claude Code process is C:\Users\xperi\AppData\Roaming\Claude\claude-code\2.1.281\claude.exe, launched with --output-format/--input-format (stream-json SDK mode), --setting-sources=user,project,local, --add-dir D:\prime-game, and a --settings JSON whose keys are deniedMcpServers/serverName with no env. The `claude` on PATH is 2.1.195.  
  src: local-test: Get-CimInstance Win32_Process (flag names only); claude --version (local-test)
- **gap5-14** Changelog 2.1.260 describes '-p --resume/--continue (as used by the desktop app)'.  
  src: https://code.claude.com/docs/en/changelog.md (changelog)
- **gap5-15** 'When the same variable is set in both your shell and a settings file env block, the settings file value applies. Claude Code writes each env entry into the process environment.' Saved changes are applied to a running session; removing a variable takes effect only on relaunch. Between settings files, env follows settings precedence (local above project above user).  
  src: https://code.claude.com/docs/en/env-vars.md (official-docs)
- **gap5-16** 'A hook process inherits the parent environment', apart from OTEL_* exporter variables and variables scrubbed when CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1. 'Handlers run in the current directory with Claude Code's environment.'  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
- **gap5-17** Hook exec form (args set) has no shell, and '$' passes through verbatim; only path placeholders are substituted. Shell form runs in Git Bash on Windows, or PowerShell when Git Bash isn't installed or when "shell": "powershell" is set.  
  src: https://code.claude.com/docs/en/hooks.md (official-docs)
- **gap5-18** A subagent with isolation: worktree runs its Bash and PowerShell commands inside its worktree. Workflow agent() calls spawn subagents. Neither page says settings are reloaded for a subagent's worktree.  
  src: https://code.claude.com/docs/en/sub-agents.md (official-docs)
- **gap5-19** Subagents and workflow agents inherit the parent session's process environment, including settings env, because they run inside the parent Claude Code process; the settings file location only matters for the session's own startup directory.  
  src: https://code.claude.com/docs/en/workflows.md (inferred)
- **gap5-20** This workflow agent, in the main checkout (CLAUDE_CODE_ENTRYPOINT=claude-desktop), sees GODOT_BIN, GODOT_GUI_BIN, PYTHON_BIN and GDTOOLKIT_DIR in both PowerShell and Git Bash. Their only source is D:\prime-game\.claude\settings.local.json: ~/.claude/settings.json has no env key, and HKCU\Environment does not define them.  
  src: local-test: $env:GODOT_BIN etc. in PowerShell; echo $GODOT_BIN in Bash; cat D:/prime-game/.claude/settings.local.json and ~/.claude/settings.json; Get-ItemProperty HKCU:\Environment (local-test)
- **gap5-21** Desktop local environment editor: 'Variables you save here are stored encrypted on your machine and apply to every local session and preview server you start. You can also add variables to the env key in your ~/.claude/settings.json file, though these reach Claude sessions only and not dev servers.' On Windows, the app inherits user and system environment variables but does not read PowerShell profiles.  
  src: https://code.claude.com/docs/en/desktop.md (official-docs)
- **gap5-22** Desktop worktrees are stored in <project-root>/.claude/worktrees/ by default (configurable under Settings → Claude Code → Worktree location); the docs point to .worktreeinclude for bringing gitignored files into new worktrees.  
  src: https://code.claude.com/docs/en/desktop.md (official-docs)
- **gap5-23** On Windows, ~/.claude means %USERPROFILE%\.claude. Settings precedence order: managed, command line, project local (.claude/settings.local.json), shared project, user (~/.claude/settings.json).  
  src: https://code.claude.com/docs/en/settings.md (official-docs)
- **gap5-24** Changelog 2.1.281: 'Improved debug logs to name settings env variables ignored because the session's launch environment already sets them'.  
  src: https://code.claude.com/docs/en/changelog.md (changelog)
- **gap5-25** No changelog entry from 2.1.196 to 2.1.283 changes where Windows reads settings.local.json or makes worktrees copy it automatically. Related entries: 2.1.211 (always-allow rules saved at the repo root), 2.1.239 (.worktreeinclude '**/' fix), 2.1.246 (/cd reloads project settings), 2.1.251 (project env can't set TMP/CLAUDE_CONFIG_DIR).  
  src: https://code.claude.com/docs/en/changelog.md (changelog)
- **gap5-26** CLAUDE_ENV_FILE is run 'before each Bash command'. SessionStart, Setup, CwdChanged and FileChanged hooks persist variables for subsequent Bash commands only.  
  src: https://code.claude.com/docs/en/env-vars.md (official-docs)
- **gap5-27** A gh search of anthropics/claude-code issues found no existing report about the backslash global-excludes pattern or about worktree sessions missing settings.local.json env on Windows.  
  src: local-test: gh search issues --repo anthropics/claude-code "settings.local.json worktree" / "excludesFile" / ".worktreeinclude windows" (local-test)
## Does KICKOFF 5.2's single docs/INTERVENTIONS.md with every entry appended at the end survive GitHub PR merges when both humans' branches append entries? Can `merge=union` in .gitattributes fix this for GitHub's mergeability check and merge button, or only for local rebase? The same question applies to CREDITS.md and to rule lists in root CLAUDE.md.
confidence: high

## Short answer

No, it does not survive. When two branches each append a block at the end of the same file, git reports a conflict (gap6-10). `merge=union` only helps local git: merge, rebase, cherry-pick and revert (gap6-02, gap6-11). GitHub's mergeability check, its merge button and its "Update branch" button do not use it (gap6-03, gap6-04, gap6-07).

GitHub's docs never say this outright (gap6-05, gap6-06). The evidence is:
- an open, unanswered feature request, discussion #9288 (open since 2021-12-24, last comment August 2026, no reply from GitHub staff);
- a 2017 GitHub support reply quoted in that thread: "GitHub doesn't consider user-defined .gitattributes files";
- a repo issue opened 2026-09-25, reporting a PR marked conflicting on GitHub even though the same merge was clean locally.

We can only prove this on our own setup with a test on a real GitHub repo, and a human has to approve that test first (gap6-19). Stock git 2.49 does honour union in a server-style merge, so GitHub ignoring it is GitHub's choice, not a limit of git (gap6-15).

## What union does locally

It works, but it can silently damage entries:
- **Lost lines:** if both entries end with the same lines (for example `- Status: rule added` and `---`), those lines are kept only once. One entry loses its lines and git reports no conflict (gap6-12).
- **Lost separator:** the blank line between the two entries disappears.
- **Unstable order:** which entry comes first depends on the direction of the merge (gap6-11).
- **CLAUDE.md rules:** two branches that each add a rule 3 end up with two lines numbered "3.". Two branches that edit the same rule line differently end up with both versions of the rule, contradicting each other, and no conflict is shown (gap6-14).

After a local rebase and force-push, the PR does become mergeable on GitHub. But this lasts only until the other PR merges first. A rebase before opening the PR (which KICKOFF 5.4 already requires) is therefore not enough: the branch must be rebased again right before merging (gap6-18).

## Options for AGENT_WORKFLOW.md (for approval; nothing applied)

**A. One file per entry: `docs/interventions/YYYY-MM-DD-<owner>-<slug>.md`.** This mirrors the ADR naming.
- Each branch adds a new file, so GitHub sees no conflict and no attribute is needed (gap6-16).
- Do not keep a hand-maintained index file listing the entries, because that would bring the conflict back. A generated listing or a plain directory listing is fine.
- Rules can be handled the same way: one file per topic in `.claude/rules/*.md`. Claude Code supports this natively and can load a rule only for certain paths, for example `content/**` (gap6-17). This reduces edits to root CLAUDE.md.
- Recommended: it does not depend on the agents remembering an extra step.

**B. `merge=union` plus a required local rebase in the finish-task skill, both before the PR is opened and immediately before merge.**
- Steps: check the PR with `gh pr view --json mergeable,mergeStateStatus` (gap6-08). If it is conflicting, run `git fetch` and `git rebase origin/main`, re-run the tests, and push with `--force-with-lease`.
- Each entry needs a unique last line, such as `<!-- end <slug> -->`. With that, every line of both entries survived in my test; only the blank separator was lost (gap6-13).
- Add a lint check that counts entries.
- Downsides: it depends on agent discipline, and GitHub still shows a conflict whenever the other PR lands first.
- Never use union on CLAUDE.md or on any file that gets edited in place.

**C. A single writer.**
- Only the engineer's agent edits INTERVENTIONS.md and root CLAUDE.md. CLAUDE.md is already engineer-owned under CODEOWNERS in KICKOFF 5.3 (gap6-01).
- The designer's agent files an issue (for example labelled `intervention`) and the engineer's agent adds the entry.
- No conflicts, but lessons take longer to land and the engineer becomes a bottleneck.

**D. CREDITS.md.**
- Its entries are one-line table rows, so union is safe locally (gap6-14), but GitHub still flags conflicts.
- Choose one:
  - union with a rebase, as in option B;
  - one small metadata file per asset, with CREDITS.md generated from them (my own idea, not taken from any documentation);
  - a single writer.

**Not recommended:** fixing conflicts by hand in GitHub's web "Resolve conflicts" editor. It works for simple conflicts (gap6-06), but it is a human editing files, which breaks the rule that humans write no code.

This choice changes the finish-task skill and the INTERVENTIONS section of AGENT_WORKFLOW.md.

## Local test scripts

In C:\Users\xperi\AppData\Local\Temp\claude\D--prime-game\40c5c58a-0dc5-4821-beca-a406804c7d8a\scratchpad\union-test\: `t1.sh`, `t2.sh`, `t4.sh`, plus `run3` and `run5`, which were inline commands.

### facts
- **gap6-01** KICKOFF 5.2 specifies docs/INTERVENTIONS.md as an append-only log where 'each entry is a single self-contained block appended at the end of the file' to minimize conflicts. KICKOFF 5.4 already requires 'Rebase on main before opening a PR', and 5.3 makes the engineer the CODEOWNER of CLAUDE.md. KICKOFF line 93 requires every third-party asset to be recorded in CREDITS.md.  
  src: D:\prime-game\KICKOFF.md (lines 93, 335-337, 343, 369) (repo)
- **gap6-02** git's built-in union driver: 'Run 3-way file level merge for text files, but take lines from both versions, instead of leaving conflict markers. This tends to leave the added lines in the resulting file in random order and the user should verify the result.' The merge attribute applies 'during git merge, and other commands such as git revert and git cherry-pick'. The doc page is for git 2.55.0.  
  src: https://git-scm.com/docs/gitattributes (official-docs)
- **gap6-03** GitHub community discussion #9288 'Pull request conflicts: Support `merge=union` in .gitattributes file' was opened 2021-12-24. It is still open, has no marked answer and no reply from GitHub staff; the latest comments are from May 2026 and August 2026. The original post says PRs that 'only conflict on a CHANGELOG.md file' marked merge=union must be 'manually rebased'. A 2025 comment quotes a 2017 GitHub support reply: 'GitHub doesn't consider user-defined .gitattributes files'.  
  src: https://github.com/orgs/community/discussions/9288 (issue)
- **gap6-04** felix-run/felix issue #313 'GitHub's mergeability check ignores .gitattributes merge=union on CHANGELOG.md', opened 2026-09-25 and still open, reports that GitHub marked PR #311 as conflicting on CHANGELOG.md and blocked the merge, while a local `git merge origin/main` resolved the file cleanly with all entries kept.  
  src: https://github.com/felix-run/felix/issues/313 (issue)
- **gap6-05** GitHub's 'About merge conflicts' page says conflicts occur when 'people make different changes to the same line of the same file' and that 'Simple line conflicts can often be resolved on GitHub', while more complex ones must be resolved locally. It does not mention .gitattributes, merge drivers or merge strategies.  
  src: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/about-merge-conflicts (official-docs)
- **gap6-06** GitHub's web conflict editor lets you 'resolve simple competing line change conflicts on GitHub'. The page does not mention .gitattributes or merge drivers.  
  src: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/resolving-a-merge-conflict-on-github (official-docs)
- **gap6-07** The Update branch button (merge, or 'Update with rebase') is available 'when there are no merge conflicts and the branch is behind the base branch'. If the base branch causes conflicts, you must 'resolve the conflicts before updating the branch'.  
  src: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/keeping-your-pull-request-in-sync-with-the-base-branch (official-docs)
- **gap6-08** gh 2.88.1 has `gh pr update-branch [--rebase]`, which updates the PR branch on the server. `gh pr view --json` exposes the fields `mergeable` and `mergeStateStatus`.  
  src: local-test: gh pr update-branch --help; gh pr view --help (local-test)
- **gap6-09** GitHub moved merge commits and rebases to git's merge-ort (blog post dated 2023-07-27). The post does not say whether .gitattributes merge drivers are honored.  
  src: https://github.blog/engineering/infrastructure/scaling-merge-ort-across-github/ (blog)
- **gap6-10** Control test with git 2.49.0 and no attribute: main merges branch eng (entry appended at end of file), then des, which also appended an entry, is rebased onto main. Result: CONFLICT in docs/INTERVENTIONS.md.  
  src: local-test: bash scratchpad/union-test/t1.sh (section C) (local-test)
- **gap6-11** With `docs/INTERVENTIONS.md merge=union`, the same scenario rebases cleanly with no conflict markers and both entries kept. Merging main into des is also clean, but the entry order flips: des then eng instead of eng then des. In both cases the blank line between the two new entries is lost because the shared leading blank line is kept once.  
  src: local-test: bash scratchpad/union-test/t1.sh (sections A, B) (local-test)
- **gap6-12** Silent data loss with union: two templated multi-line entries that both end with '- Status: rule added' and '---' rebase with no conflict reported, but the first entry loses its 'Status' and '---' lines, which appear only once, after the second entry.  
  src: local-test: bash scratchpad/union-test/t2.sh (local-test)
- **gap6-13** Mitigation test: when every entry ends with a unique line ('<!-- end <slug> -->'), union keeps every line of both entries: the 'Rule file', 'Status' and end-marker lines each appear twice. Only the blank separator is lost.  
  src: local-test: bash scratchpad/union-test/t4.sh (local-test)
- **gap6-14** In a root CLAUDE.md marked merge=union, two branches each adding rule '3.' produce two lines numbered '3.' with no conflict. Two branches editing the same rule line ('Max 300 lines' changed to 400 on one branch and 250 on the other) produce both lines, contradictory rules, with no conflict. CREDITS.md one-line table rows union-merge correctly.  
  src: local-test: bash scratchpad/union-test/t2.sh and inline test in scratchpad/union-test/run3 (local-test)
- **gap6-15** Stock git 2.49 can honor union server-side. In a bare clone with no worktree, `git merge-tree --write-tree main des` returns a clean tree (exit 0) when the committed .gitattributes has merge=union, and reports CONFLICT (exit 1) when it does not. The mechanism, attributes read from HEAD in bare repos, is my inference: git-config documents attr.tree, but the default for bare repos is not stated in the local 2.49 docs.  
  src: local-test: bash scratchpad/union-test/t1.sh (section D) and inline `git merge-tree` in run1/noattr.git (local-test)
- **gap6-16** One file per entry (docs/interventions/2026-09-28-eng-....md and 2026-09-28-des-....md added on two branches) merges cleanly with `git merge-tree --write-tree` in a bare repo with no .gitattributes, so it does not depend on merge drivers.  
  src: local-test: inline test in scratchpad/union-test/run5 (local-test)
- **gap6-17** Claude Code supports a `.claude/rules/` directory where 'All .md files are discovered recursively'. Rules without `paths` frontmatter 'are loaded at launch with the same priority as .claude/CLAUDE.md'. `paths:` frontmatter scopes a rule so it loads only when Claude works with matching files. CLAUDE.md files in subdirectories load on demand. The docs advise keeping each CLAUDE.md under 200 lines. The installed Claude Code is 2.1.195.  
  src: https://code.claude.com/docs/en/memory (official-docs)
- **gap6-18** After a local rebase and force-push, the PR is mergeable on GitHub because main is then an ancestor of the PR head. It becomes CONFLICTING again as soon as the other human's PR changing the same file merges first. So finish-task must re-check `mergeable` and rebase immediately before merge, not only before opening the PR. This is my inference from git's 3-way merge behaviour and gap6-03, gap6-04 and gap6-07; it has not been tested on GitHub.  
  src: inferred (inferred)
- **gap6-19** Confirming the GitHub behaviour needs a real GitHub repo: push the .gitattributes, open two PRs that each append to the file, merge one, then read the other's `gh pr view --json mergeable`. This creates remote state, so a human must approve it; it was not run.  
  src: inferred (inferred)