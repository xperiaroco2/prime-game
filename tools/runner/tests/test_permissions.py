"""The shell permission lists of .claude/settings.json with the guard (docs/AGENT_WORKFLOW.md §8.1): reads of other
repositories pass in every mode, writes there ask (issue #68); and the model of Claude Code's rule matcher."""

import json
import re
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, guard, permissions
from runner.common import ROOT

MAIN = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT))
MAIN_POSIX = MAIN.replace("\\", "/")
RULES = permissions.Rules.load(ROOT / ".claude" / "settings.json")
TOOLS = ("Bash", "PowerShell")


class OwnRepo(guard.NoRepo):
    def github_repo(self) -> str | None:
        return "xperiaroco2/prime-game"


def verdict(
    tool: str, command: str, mode: str = permissions.BYPASS, rules: permissions.Rules = RULES
) -> tuple[str, str]:
    return permissions.verdict(rules, guard, tool, command, str(ROOT), MAIN, OwnRepo(), mode)


# Reads of other repositories, from the research of earlier tasks: each runs without a prompt in every mode.
OTHER_READS = [
    "gh issue view 107 -R goatchurchprime/two-voip-godot-4 --comments",
    "gh issue view 98500 --repo godotengine/godot --json title,state,body --jq .title",
    "gh issue list --repo obra/superpowers --label windows --state open --limit 100",
    "gh issue view https://github.com/godotengine/godot/issues/98500",
    "gh pr view 101673 --repo godotengine/godot --json labels",
    "gh pr list -R godotengine/godot --search unique_id --state merged",
    "gh pr diff 101673 -R godotengine/godot",
    "gh pr checks 101673 --repo=godotengine/godot",
    "gh release view 4.7.2-stable -R godotengine/godot --json assets --jq .assets[].name",
    "gh release list --repo godotengine/godot --limit 6",
    "gh release list -R godot-gdunit-labs/gdUnit4",
    "gh repo view godotengine/godot --json description",
    'gh search issues --repo godotengine/godot "import exit code headless" --limit 10',
    "gh search prs -R godotengine/godot unique_id --merged",
    "gh search code get_current_chunk --repo goatchurchprime/two-voip-godot-4",
    "gh api repos/godotengine/godot/commits?per_page=1 --jq .[0].sha",
    "gh api -X GET repos/godotengine/godot/issues -f state=open",
    "gh api https://api.github.com/repos/godotengine/godot/releases/latest",
    "gh api -H Accept:application/vnd.github.raw repos/chickensoft-games/setup-godot/readme",
    "gh issue view 5865 -R cli/cli && gh release view v6.2.1 -R godot-gdunit-labs/gdUnit4",
]

# Writes to other repositories: each asks in every mode (a deny rule is stronger still).
OTHER_WRITES = [
    "gh issue comment 107 -R goatchurchprime/two-voip-godot-4 --body thanks",
    "gh issue create --repo godotengine/godot --title x --body-file f.md",
    "gh issue edit 5 -R o/r --add-label bug",
    "gh issue close 5 --repo=o/r",
    "gh issue reopen 5 -Ro/r",
    "gh issue comment https://github.com/o/r/issues/1 --body x",
    "gh issue transfer 5 o/r",
    "gh pr create -R o/r --fill",
    "gh pr create -d -R o/r --title t",
    "gh pr comment 5 -R o/r -b hi",
    "gh pr edit 5 -R o/r --add-reviewer x",
    "gh pr close 5 -R o/r",
    "gh pr ready 5 -R o/r",
    "gh release create v1 -R o/r",
    "gh release upload v1 a.zip -R o/r",
    "gh label create bug -R o/r",
    "gh workflow run ci.yml -R o/r",
    "gh run rerun 12 -R o/r",
    "gh repo fork o/r",
    "gh api -X POST repos/o/r/issues -f title=x",
    "gh api repos/o/r/issues/1/comments -f body=x",
    "gh api repos/o/r/issues/1/comments --input body.json",
    "gh api --method PATCH repos/o/r/issues/1 -f state=closed",
    "gh api -XPOST repos/o/r/forks",
    "gh api -X=POST repos/o/r/forks",
    "gh api repos/o/r/issues/1/comments -fbody=hi",
    "gh api repos/o/r/issues/1/comments -Fbody=@b.md",
    "gh issue view 1 -R o/r && gh issue comment 1 -R o/r --body x",
]

# Writes to this project's repository stay as they were: allowed (issue #68 leaves them out of scope).
OWN_WRITES = [
    "gh issue comment 68 --body x",
    "gh issue comment 68 -R xperiaroco2/prime-game --body x",
    'gh issue comment 68 --body "as in https://github.com/godotengine/godot/issues/1 -R o/r"',
    "gh pr create --title x --body-file f.md",
    "gh api repos/{owner}/{repo}/issues/68/comments -f body=x",
    "gh api repos/xperiaroco2/prime-game/issues/68/comments -f body=x",
    "gh api graphql -f query=x",
]


class OtherRepositoriesTest(unittest.TestCase):
    def test_reads_of_other_repositories_pass_in_every_mode(self) -> None:
        for tool in TOOLS:
            for command in OTHER_READS:
                for mode in permissions.MODES:
                    with self.subTest(tool=tool, command=command, mode=mode):
                        self.assertEqual(verdict(tool, command, mode)[0], permissions.PASS)

    def test_writes_to_other_repositories_ask_in_every_mode(self) -> None:
        for tool in TOOLS:
            for command in OTHER_WRITES:
                for mode in permissions.MODES:
                    with self.subTest(tool=tool, command=command, mode=mode):
                        self.assertEqual(verdict(tool, command, mode)[0], permissions.PROMPT)

    def test_a_merge_in_another_repository_stays_denied(self) -> None:
        for tool in TOOLS:
            with self.subTest(tool=tool):
                self.assertEqual(verdict(tool, "gh pr merge 5 -R o/r")[0], permissions.DENIED)

    def test_gh_repo_names_the_repository_in_both_shells(self) -> None:
        self.assertEqual(verdict("Bash", "GH_REPO=o/r gh issue close 5")[0], permissions.PROMPT)
        self.assertEqual(verdict("Bash", "env GH_REPO=o/r gh issue close 5")[0], permissions.PROMPT)
        self.assertEqual(verdict("Bash", "export GH_REPO=o/r; gh pr comment 5 -b x")[0], permissions.PROMPT)
        self.assertEqual(verdict("PowerShell", "$env:GH_REPO = 'o/r'; gh issue close 5")[0], permissions.PROMPT)
        self.assertEqual(verdict("Bash", "GH_REPO=o/r gh issue view 5")[0], permissions.PASS)

    def test_writes_to_this_repository_stay_allowed(self) -> None:
        for tool in TOOLS:
            for command in OWN_WRITES:
                for mode in permissions.MODES:
                    with self.subTest(tool=tool, command=command, mode=mode):
                        self.assertEqual(verdict(tool, command, mode)[0], permissions.PASS)

    def test_releases_of_this_repository_are_read_freely_and_changed_only_with_an_ok(self) -> None:
        for tool in TOOLS:
            with self.subTest(tool=tool):
                self.assertEqual(verdict(tool, "gh release view v0.1.0", permissions.DEFAULT)[0], permissions.PASS)
                self.assertEqual(verdict(tool, "gh release list", permissions.DEFAULT)[0], permissions.PASS)
                for command in ("gh release create v1", "gh release delete v1 -y", "gh release delete-asset v1 a",
                                "gh release edit v1 --draft", "gh release upload v1 a.zip",
                                "gh release download v1"):  # fmt: skip
                    self.assertEqual(verdict(tool, command)[0], permissions.PROMPT, command)

    def test_the_old_text_rules_asked_for_every_read(self) -> None:
        old = permissions.Rules(
            {"permissions": {"allow": ["Bash(gh issue view *)"], "ask": ["Bash(gh * -R *)", "Bash(gh * --repo*)"]}}
        )
        self.assertEqual(verdict("Bash", OTHER_READS[0], rules=old)[0], permissions.PROMPT)
        self.assertEqual(verdict("Bash", OTHER_READS[1], rules=old)[0], permissions.PROMPT)


class AccountRepo(OwnRepo):
    """The engineer's machine: gh's active account is the owner of this project's repository (issue #464)."""

    def gh_user(self) -> str | None:
        return "xperiaroco2"


ART = "xperiaroco2/prime-game-art"


class OwnAccountAndTempTest(unittest.TestCase):
    """Issue #464 through the rules and the guard together: writes to gh's own account's repositories and filtered
    deletes in the temp folder pass; merges, deletion, auth, secrets, other owners and scratchpad roots do not."""

    def judge(self, tool: str, command: str, mode: str = permissions.BYPASS) -> str:
        return permissions.verdict(RULES, guard, tool, command, str(ROOT), MAIN, AccountRepo(), mode)[0]

    def test_writes_to_the_accounts_repositories_pass_like_writes_here(self) -> None:
        for tool in TOOLS:
            for command in (
                f"gh issue create -R {ART} --title x --body-file f.md",
                f"gh issue comment 5 -R {ART} --body-file b.md",
                f"gh pr create -R {ART} --base main --head x --title t --body b",
                f"gh pr edit 9 -R {ART} --base main",
                "gh issue create -R xperiaroco2/prime-game-ui --title x --label docs --body-file f.md",
                f"gh api repos/{ART}/issues -f title=x",
            ):
                for mode in permissions.MODES:
                    with self.subTest(tool=tool, command=command, mode=mode):
                        self.assertEqual(self.judge(tool, command, mode), permissions.PASS)

    def test_merges_deletion_auth_secrets_and_other_owners_stay_as_they_were(self) -> None:
        for tool in TOOLS:
            for command, expected in (
                (f"gh pr merge 5 -R {ART}", permissions.DENIED),
                (f"gh repo delete {ART} --yes", permissions.DENIED),
                ("gh auth token", permissions.DENIED),
                (f"gh pr -R {ART} merge 5", permissions.PROMPT),
                (f"gh secret set X -R {ART}", permissions.PROMPT),
                (f"gh secret -R {ART} set X", permissions.PROMPT),
                (f"gh api -X PUT repos/{ART}/pulls/5/merge", permissions.PROMPT),
                (f"gh api -XDELETE repos/{ART}", permissions.PROMPT),
                ("gh issue comment 1 -R godotengine/godot --body x", permissions.PROMPT),
            ):
                with self.subTest(tool=tool, command=command):
                    self.assertEqual(self.judge(tool, command), expected)
                    self.assertEqual(verdict(tool, command)[0], expected)  # the same without the account

    def test_a_filtered_delete_in_temp_is_judged_by_what_it_matches(self) -> None:
        incident = "Get-ChildItem $env:TEMP -Filter 'rmtree-*' -Directory | Remove-Item -Recurse -Force"
        self.assertEqual(self.judge("PowerShell", incident), permissions.PASS)
        self.assertEqual(self.judge("Bash", 'rm -rf "$TEMP"/rmtree-*'), permissions.PASS)
        for tool, command in (
            ("PowerShell", "Get-ChildItem $env:TEMP -Filter 'cl*' -Directory | Remove-Item -Recurse -Force"),
            ("PowerShell", "Get-ChildItem $env:TEMP -Directory | Remove-Item -Recurse -Force"),
            ("Bash", 'rm -rf "$TEMP"/cl*'),
            ("Bash", 'rm -rf "$TEMP"/../x*'),
        ):
            with self.subTest(tool=tool, command=command):
                self.assertEqual(self.judge(tool, command), permissions.PROMPT)


class ProtectionsTest(unittest.TestCase):
    """The protections #312 must not weaken (its AC4), in both shells and both modes, for the patterns that met them
    in the week's transcripts and their neighbours."""

    DENIED = [
        "git push origin main", "git push --force origin x", "git push -f origin x", "git push", "git push origin",
        "git push origin HEAD", "git push origin HEAD:main", "git push --no-verify origin x", "gh pr merge 5",
        "gh pr merge --help", "gh pr merge 5 -R o/r", "git config core.hooksPath x", "git config --get core.hooksPath",
        "git config --unset core.x", "git diff --output=f", "git show --output=f HEAD", "gh auth token",
        "gh repo delete o/r --yes",
    ]  # fmt: skip

    def test_the_deny_list_holds(self) -> None:
        for tool in TOOLS:
            for command in self.DENIED:
                for mode in permissions.MODES:
                    with self.subTest(tool=tool, command=command, mode=mode):
                        self.assertEqual(verdict(tool, command, mode)[0], permissions.DENIED)

    def test_the_guard_still_asks_beyond_the_own_worktree(self) -> None:
        for tool, command in (
            ("Bash", f"git -C {MAIN_POSIX} reset --hard"),
            ("Bash", f"rm -rf {MAIN_POSIX}/core"),
            ("Bash", f"git -C {MAIN_POSIX} branch -D tooling/189-x"),
            ("Bash", "gh issue create -R godotengine/godot --title x"),
            ("Bash", "gh pr create -R xperiaroco2/prime-game-art --title x"),
            ("Bash", "mv addons/twovoip /tmp/x"),
            ("PowerShell", "Copy-Item x .claude/settings.json"),
            # #457 lets an interactive rebase pass in the own worktree on its task branch, not in the main checkout.
            ("Bash", f"git -C {MAIN_POSIX} rebase -i --autosquash origin/main"),
        ):  # fmt: skip
            for mode in permissions.MODES:
                with self.subTest(tool=tool, command=command, mode=mode):
                    self.assertEqual(verdict(tool, command, mode)[0], permissions.PROMPT)

    def test_the_engineers_interactive_rebase_passes_in_the_own_worktree(self) -> None:
        # #457: #445's fix agent waited from 21:56 to 07:19 UTC on this prompt in its own worktree, on its task branch.
        worktree = f"{MAIN_POSIX}/.claude/worktrees/51"

        class TaskRepo(OwnRepo):
            def __init__(self, branch: str) -> None:
                self.checked_out = branch

            def branch(self, checkout: str) -> str | None:
                return self.checked_out if checkout == guard.normalize(worktree) else "main"

        command = (
            f"cd {worktree} && SP=/c/x/r445 && GIT_SEQUENCE_EDITOR=\"sed -i '/^pick 2c3e0d21/a exec git commit -q "
            "--amend --cleanup=verbatim -F $SP/m.txt'\" git rebase -q -i origin/main"
        )
        for cwd in (MAIN, worktree):
            with self.subTest(cwd=cwd):
                judged = permissions.verdict(RULES, guard, "Bash", command, cwd, MAIN, TaskRepo("tooling/51-x"))
                self.assertEqual(judged[0], permissions.PASS)
        # Another branch checked out in the worktree, or the main checkout, still asks.
        other = permissions.verdict(RULES, guard, "Bash", command, MAIN, MAIN, TaskRepo("core/42-vote"))
        self.assertEqual(other[0], permissions.PROMPT)
        main = command.replace(f"cd {worktree}", f"cd {MAIN_POSIX}")
        self.assertEqual(permissions.verdict(RULES, guard, "Bash", main, MAIN, MAIN, TaskRepo("tooling/51-x"))[0],
                         permissions.PROMPT)


class SettingsTest(unittest.TestCase):
    def test_every_bash_rule_has_a_powershell_twin(self) -> None:
        for kind, rules in RULES.lists.items():
            written = [rule for _, _, rule in rules]
            bash = {r[len("Bash(") :] for r in written if r.startswith("Bash(")}
            powershell = {r[len("PowerShell(") :] for r in written if r.startswith("PowerShell(")}
            with self.subTest(kind=kind):
                # PowerShell alone runs tools\run.cmd, so only that side may have rules of its own.
                self.assertEqual(bash - powershell, set())
                self.assertEqual({r for r in powershell - bash if "run.cmd" not in r}, set())

    def test_no_text_rule_asks_for_every_gh_call_with_a_repository(self) -> None:
        for tool in TOOLS:
            for command in ("gh issue view 1 -R o/r", "gh pr list --repo o/r", "gh search issues x --repo o/r"):
                with self.subTest(tool=tool, command=command):
                    self.assertEqual(RULES.judge(tool, command)[0], permissions.ALLOW)


WORKTREE = str(ROOT).replace("\\", "/")
BRANCH = "tooling/342-push-twins"
# The spellings of git that name a checkout or a config value before `push` (issue #342); plain `git` too.
GIT_PREFIXES = [
    "git",
    f"git -C {WORKTREE}",
    "git -C ..",
    "git -c http.postBuffer=524288000",
    f"git -c k=v -C {WORKTREE}",
    f"git -C {WORKTREE} -c k=v",
]
# One push per deny rule on `git push`: to main, by HEAD, forced, without the hook, deleting, pruning, mirroring.
FORBIDDEN_PUSHES = [
    "push",
    "push origin",
    "push -u origin",
    "push origin main",
    "push -u origin main",
    "push origin main --dry-run",
    "push origin HEAD",
    "push -u origin HEAD:main",
    f"push origin {BRANCH}:refs/heads/main",
    f"push origin {BRANCH}:main",
    f"push --force origin {BRANCH}",
    f"push --force-with-lease origin {BRANCH}",
    f"push -f origin {BRANCH}",
    f"push origin {BRANCH} --force",
    f"push origin {BRANCH} -f",
    f"push origin -f {BRANCH}",
    f"push origin +{BRANCH}",
    f"push --no-verify origin {BRANCH}",
    f"push origin --delete {BRANCH}",
    f"push origin -d {BRANCH}",
    "push --prune origin",
    "push --mirror origin",
    "push --all origin",
]
TASK_PUSHES = [f"push -u origin {BRANCH}", f"push origin {BRANCH}"]
# The documented trade-off (AGENT_WORKFLOW 8.1): `*` spans words, so a `-m` message that reads like a push is denied.
MESSAGES_LIKE_PUSHES = ['"x push HEAD"', '"fix: deny git -C and git -c pushes like git push"', '"x push origin main"']


class PushTwinsTest(unittest.TestCase):
    """`git -C <path> push` and `git -c k=v push` meet the same deny rules as `git push` (issue #342)."""

    def test_each_push_deny_rule_has_its_dash_C_and_dash_c_twins_in_both_shells(self) -> None:
        deny = {written for _, _, written in RULES.lists[permissions.DENY]}
        pushes = [rule[len("Bash(git push") :] for rule in deny if rule.startswith("Bash(git push")]
        self.assertGreater(len(pushes), 10)
        for rest in pushes:
            for tool in TOOLS:
                for option in ("-C", "-c"):
                    with self.subTest(tool=tool, option=option, rule=rest):
                        self.assertIn(f"{tool}(git {option} * push{rest}", deny)

    def test_forbidden_pushes_are_denied_after_dash_C_and_dash_c(self) -> None:
        for tool in TOOLS:
            for prefix in GIT_PREFIXES:
                for push in FORBIDDEN_PUSHES:
                    for mode in permissions.MODES:
                        command = f"{prefix} {push}"
                        with self.subTest(tool=tool, command=command, mode=mode):
                            self.assertEqual(verdict(tool, command, mode)[0], permissions.DENIED)

    def test_task_branch_pushes_and_the_runner_still_pass(self) -> None:
        for tool in TOOLS:
            run = "tools\\run.cmd" if tool == "PowerShell" else "tools/run.sh"
            commands = [f"{prefix} {push}" for prefix in GIT_PREFIXES for push in TASK_PUSHES]
            commands += [f"{run} publish", f"{run} publish --base main", f"{run} merge 5 --base release/m7"]
            for command in commands:
                with self.subTest(tool=tool, command=command):
                    self.assertEqual(verdict(tool, command)[0], permissions.PASS)

    def test_a_commit_message_that_reads_like_a_forbidden_push_is_denied(self) -> None:
        for tool in TOOLS:
            for message in MESSAGES_LIKE_PUSHES:
                for prefix in (f"git -C {WORKTREE}", "git -c k=v"):
                    command = f"{prefix} commit -m {message}"
                    with self.subTest(tool=tool, command=command):
                        self.assertEqual(verdict(tool, command)[0], permissions.DENIED)


class MatcherTest(unittest.TestCase):
    def rules(self, **lists: list[str]) -> permissions.Rules:
        return permissions.Rules({"permissions": lists})

    def test_a_trailing_wildcard_after_a_space_also_matches_the_bare_command(self) -> None:
        rules = self.rules(allow=["Bash(ls *)", "Bash(git log*)", "Bash(npm run build)"])
        self.assertEqual(rules.judge("Bash", "ls")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "ls -la")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "lsof")[0], permissions.NONE)
        self.assertEqual(rules.judge("Bash", "git logx")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "npm run build --watch")[0], permissions.NONE)

    def test_a_middle_wildcard_spans_words(self) -> None:
        rules = self.rules(ask=["Bash(gh api * -X PUT*)"])
        self.assertEqual(rules.judge("Bash", "gh api repos/a/b -H x -X PUT")[0], permissions.ASK)
        self.assertEqual(rules.judge("Bash", "gh api -X PUT repos/a/b")[0], permissions.NONE)

    def test_deny_beats_ask_beats_allow_over_every_subcommand(self) -> None:
        rules = self.rules(allow=["Bash(git *)"], ask=["Bash(git clean *)"], deny=["Bash(git push --force*)"])
        self.assertEqual(rules.judge("Bash", "git status && git clean -fd")[0], permissions.ASK)
        self.assertEqual(rules.judge("Bash", "git clean -n; git push --force")[0], permissions.DENY)
        self.assertEqual(rules.judge("Bash", "echo $(git clean -f)")[0], permissions.ASK)
        self.assertEqual(rules.judge("Bash", "git status | head")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "git status && npm test")[0], permissions.NONE)

    def test_wrappers_and_assignments(self) -> None:
        rules = self.rules(allow=["Bash(npm test *)"], ask=["Bash(rm *)"])
        self.assertEqual(rules.judge("Bash", "timeout 30 npm test")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "FOO=bar rm -rf tmp")[0], permissions.ASK)
        self.assertEqual(rules.judge("Bash", "FOO=bar npm test")[0], permissions.NONE)

    def test_powershell_rules_ignore_case(self) -> None:
        rules = self.rules(allow=["PowerShell(Get-ChildItem *)"], ask=["Bash(get-childitem *)"])
        self.assertEqual(rules.judge("PowerShell", "get-childitem -Recurse")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "Get-ChildItem x")[0], permissions.NONE)

    def test_read_only_set_follows_the_docs(self) -> None:
        rules = self.rules()
        for command in ("which git", "du -sh x", "stat f", "diff a b", "find . -name x", "sed -n 1,5p f",
                        "sort -u f", "timeout 9 grep x f", "git status --short", "git diff origin/main --stat",
                        "git show HEAD:x", "git rev-parse --git-path hooks", "git worktree list",
                        "git config --get core.longpaths", "git log --oneline | head -5"):  # fmt: skip
            with self.subTest(command=command):
                self.assertEqual(rules.judge("Bash", command)[0], permissions.ALLOW)
        for command in ("find . -delete", "find . -exec rm {} ;", "find . -fprint f", "sed -i s/a/b/ f",
                        "sed -i.bak s/a/b/ f", "sed -ni p f", "sed --in-place=x s/a/b/ f", "sed -n 1,5w out f",
                        "sed s/a/b/w out f", "sort -o f g", "sort --output=f g", "git -C x status", "git -c a=b log",
                        "git diff --output=f", "git config core.x y", "git worktree remove x", "git stash drop",
                        "X=1 ls", "npm test"):  # fmt: skip
            with self.subTest(command=command):
                self.assertEqual(rules.judge("Bash", command)[0], permissions.NONE)

    def test_a_bare_assignment_runs_nothing(self) -> None:
        rules = self.rules(deny=["Bash(git push)", "PowerShell(git push)"])
        self.assertEqual(rules.judge("Bash", 'S="C:/a b" && ls "$S"')[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "f=$(grep -rl x core/); sed -n 1,5p $f")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("Bash", "f=$(npm test)")[0], permissions.NONE)
        self.assertEqual(rules.judge("Bash", "PATH=/x")[0], permissions.NONE)
        self.assertEqual(rules.judge("Bash", "X=1 git push")[0], permissions.DENY)
        self.assertEqual(rules.judge("PowerShell", "$s = 'C:\\x'; Get-Content f")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("PowerShell", "$s = git status")[0], permissions.ALLOW)
        self.assertEqual(rules.judge("PowerShell", "$s = Remove-Item x")[0], permissions.NONE)
        self.assertEqual(rules.judge("PowerShell", "$s = git push")[0], permissions.DENY)
        self.assertEqual(rules.judge("PowerShell", "$o = npm test")[0], permissions.NONE)
        self.assertEqual(rules.judge("PowerShell", "$o = & tools\\run.cmd verify")[0], permissions.NONE)
        self.assertEqual(rules.judge("PowerShell", "$o = & git push")[0], permissions.DENY)
        for literal in ("$n = 5", "$a = @()", "$h = @{a = 1}", "$t = [int]'5'", "$b = $true", "$p = (Get-Content f)"):
            with self.subTest(literal=literal):
                self.assertEqual(rules.judge("PowerShell", literal)[0], permissions.ALLOW)

    def test_a_cd_elsewhere_takes_git_out_of_the_read_only_set(self) -> None:
        rules = self.rules()
        here = "D:\\prime-game\\.claude\\worktrees\\5"
        self.assertEqual(rules.judge("Bash", "cd /d/prime-game/.claude/worktrees/5 && git status", here)[0], "allow")
        self.assertEqual(rules.judge("Bash", "cd /d/prime-game/.claude/worktrees/6 && git status", here)[0], "none")
        self.assertEqual(rules.judge("Bash", "cd /d/prime-game/.claude/worktrees/6 && ls", here)[0], "allow")
        self.assertEqual(rules.unallowed("Bash", "cd /d/x && git status", here), "git status")

    def test_bypass_runs_what_no_rule_names(self) -> None:
        rules = self.rules()
        self.assertEqual(permissions.verdict(rules, guard, "Bash", "npm test", str(ROOT), MAIN, OwnRepo())[0], "pass")
        self.assertEqual(
            permissions.verdict(rules, guard, "Bash", "npm test", str(ROOT), MAIN, OwnRepo(), permissions.DEFAULT)[0], "prompt"
        )


class CloudReplayTest(unittest.TestCase):
    """Issue #381: a replay in a cloud container judges its main checkout on a task branch as the session's own."""

    def test_the_guard_judges_the_cloud_checkout_and_an_older_guard_still_runs(self) -> None:
        class TaskRepo(OwnRepo):
            def branch(self, checkout: str) -> str | None:
                return "tooling/381-guard-cloud-checkout"

        def replay(module: object, cloud: bool) -> str:
            command = "git reset --hard HEAD~1"
            return permissions.verdict(RULES, module, "Bash", command, MAIN, MAIN, TaskRepo(), cloud=cloud)[0]

        self.assertEqual(replay(guard, cloud=True), permissions.PASS)
        self.assertEqual(replay(guard, cloud=False), permissions.PROMPT)
        older = mock.Mock(spec=["check"])
        older.check = lambda command, shell, cwd, root, home="", repo=None: []  # before #381: no cloud
        self.assertEqual(replay(older, cloud=True), permissions.PASS)


class ReplayFoldersTest(unittest.TestCase):
    def test_only_this_projects_folders(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            for name in ("D--x", "D--x--claude-worktrees-5", "D--x-art", "D--x-ui", "D--y"):
                (base / name).mkdir()
            names = [p.name for p in permissions.project_folders(base, "D:/x")]
            self.assertEqual(names, ["D--x", "D--x--claude-worktrees-5"])
            names = [p.name for p in permissions.project_folders(base, "D:/x", "D--x*")]
            self.assertEqual(names, ["D--x", "D--x--claude-worktrees-5", "D--x-art", "D--x-ui"])

    def test_since_and_roles(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            session = Path(tmp) / "D--x" / "s1"
            for path, when in (
                (session.with_suffix(".jsonl"), "2026-09-28T23:59:00Z"),
                (session.with_suffix(".jsonl"), "2026-09-29T00:01:00Z"),
                (session / "subagents" / "agent-a.jsonl", "2026-09-30T10:00:00Z"),
                (session / "subagents" / "workflows" / "wf_1" / "agent-b.jsonl", "2026-10-01T10:00:00Z"),
            ):
                write_transcript(path, [tool_use("u" + when, "git status", when)])
            found = permissions.calls([Path(tmp) / "D--x"], since="2026-09-29")
        self.assertEqual(
            sorted((c.when[:10], c.role, c.command) for c in found),
            [("2026-09-29", "session", "git status"), ("2026-09-30", "subagent", "git status"),
             ("2026-10-01", "workflow", "git status")],
        )  # fmt: skip


SCRATCHPAD = "C:/Users/me/AppData/Local/Temp/claude/D--prime-game/s1/scratchpad"
OWN = f"{MAIN_POSIX}/.claude/worktrees/312"


# The guard as it was before #312: its hook never allows, so the verdicts are Claude Code's own.
SILENT_GUARD = types.SimpleNamespace(check=guard.check)


class AcceptEditsTest(unittest.TestCase):
    """#312: the acceptEdits model (code.claude.com/docs/en/permission-modes, checked 2026-10-07), the mode a route-C
    successor manager and its workflows always run in (#484), with a guard whose hook never allows (SILENT_GUARD).
    The session's working directory is the main checkout."""

    def judge(self, tool: str, command: str, mode: str = permissions.ACCEPT_EDITS) -> tuple[str, str]:
        return permissions.verdict(RULES, SILENT_GUARD, tool, command, MAIN, MAIN, OwnRepo(), mode)

    def assert_modes(self, tool: str, command: str, bypass: str, accept: str, default: str) -> None:
        for mode, expected in zip(permissions.MODES, (bypass, accept, default)):
            with self.subTest(tool=tool, command=command, mode=mode):
                self.assertEqual(self.judge(tool, command, mode)[0], expected)

    def test_file_tools_write_in_scope_and_never_on_protected_paths(self) -> None:
        P, Q = permissions.PASS, permissions.PROMPT
        for path in (f"{OWN}/tools/runner/x.py", f"{MAIN_POSIX}/docs/x.md", f"{SCRATCHPAD}/a312/msg.txt", "core/x.gd"):
            self.assert_modes("Write", path, P, P, Q)
        for path in (
            f"{OWN}/.claude/skills/x/SKILL.md", f"{MAIN_POSIX}/.claude/agents/x.md", f"{OWN}/.git",
            f"{OWN}/.gitmodules",
            f"{MAIN_POSIX}/.vscode/settings.json", "C:/Users/me/.claude/CLAUDE.md", "D:/prime-game-art/x.md",
        ):  # fmt: skip
            self.assert_modes("Edit", path, P, Q, Q)
        self.assertEqual(self.judge("Edit", f"{OWN}/.claude/x.md")[1], "no allow rule: edit (protected path .claude)")
        for path in (f"{OWN}/.claude/settings.json", f"{MAIN_POSIX}/addons/gdUnit4/x.gd"):
            self.assert_modes("Edit", path, Q, Q, Q)  # the ask rules, in every mode

    def test_filesystem_commands_run_in_scope(self) -> None:
        P, Q = permissions.PASS, permissions.PROMPT
        for command in (
            f"mkdir -p {OWN}/tests/scratch/x", f"touch {OWN}/tests/scratch/x.gd", f"rm -rf {OWN}/tests/scratch/x",
            f"cp {OWN}/a.txt {SCRATCHPAD}/a312/a.txt", f"mv {SCRATCHPAD}/a {SCRATCHPAD}/b",
            f"rmdir {OWN}/tests/scratch/x",
            f"sed -i 's/a/b/' {OWN}/docs/x.md", f"timeout 5 mkdir {OWN}/x", f"LANG=C touch {OWN}/x",
            f"cd {OWN} && mkdir -p tests/scratch/y && touch tests/scratch/y/z",
        ):  # fmt: skip
            self.assert_modes("Bash", command, P, P, Q)
        for command in (
            f"cp {OWN}/a.txt D:/prime-game-art/a.txt", "touch ~/x", 'rm -f "$X/y"', f"touch {OWN}/.claude/x.md",
            f"mkdir {OWN}/.git/x", "sed -n '1w /d/x' a.txt", f"FOO=1 touch {OWN}/x",
        ):  # fmt: skip
            self.assert_modes("Bash", command, P, Q, Q)
        outside = "no allow rule: cp (outside the working directory)"
        self.assertEqual(self.judge("Bash", "cp a.txt D:/prime-game-art/a.txt")[1], outside)

    def test_powershell_content_cmdlets_and_their_quote_rule(self) -> None:
        P, Q, D = permissions.PASS, permissions.PROMPT, permissions.DENIED
        for command in (
            f"Set-Content -Path {OWN}/x.txt -Value 'a b'", f"Add-Content {OWN}\\x.txt -Value x",
            f"Clear-Content -LiteralPath {SCRATCHPAD}/x", f"Remove-Item {OWN}/tests/scratch/x.gd",
        ):  # fmt: skip
            self.assert_modes("PowerShell", command, P, P, Q)
        self.assert_modes("PowerShell", "Set-Content x.txt \"It's done\"", P, Q, Q)
        self.assert_modes("PowerShell", "Set-Content C:/Users/me/x.txt -Value a", P, Q, Q)
        # Claude Code's own Remove-Item checks hold in every mode.
        for command in (f"Remove-Item -Recurse -Force {OWN}\\tests\\scratch\\*", "Remove-Item *", "Remove-Item C:\\"):
            self.assert_modes("PowerShell", command, D, D, D)
        # D:/prime-game is a drive's top-level folder: a system path. A session's own working directory asks.
        self.assert_modes("PowerShell", f"Remove-Item -Recurse -Force {MAIN_POSIX}", D, D, D)
        here = f"{OWN}/tests/scratch/w"
        for mode in permissions.MODES:
            command = f"Remove-Item -Recurse {here}"
            judged = permissions.verdict(RULES, SILENT_GUARD, "PowerShell", command, here, MAIN, None, mode)
            expected = "Claude Code: Remove-Item -Recurse of the working directory"
            self.assertEqual(judged, (P, "no rule") if mode == permissions.BYPASS else (Q, expected))

    def test_redirects_and_cd(self) -> None:
        P, Q = permissions.PASS, permissions.PROMPT
        log = f"{SCRATCHPAD}/a312/verify-1.log"
        self.assert_modes("Bash", f'cd {OWN} && tools/run.sh verify > {log} 2>&1; echo "exit=$?" >> {log}', P, P, Q)
        self.assert_modes("Bash", "git status --short 2>/dev/null | head", P, P, P)
        self.assert_modes("PowerShell", "git status 2>$null", P, P, P)
        self.assert_modes("Bash", "ls > D:/other/out.txt", P, Q, Q)
        self.assert_modes("Bash", f"ls > {OWN}/.claude/x.txt", P, Q, Q)
        # A cd out of the working directory is not read-only; one into the own worktree is.
        self.assert_modes("Bash", "cd D:/prime-game-art && ls", P, Q, Q)
        self.assert_modes("Bash", f"cd {OWN} && ls", P, P, P)
        outside = "no allow rule: cd (outside the working directory)"
        self.assertEqual(self.judge("Bash", "cd D:/other && ls")[1], outside)

    def test_rm_of_a_critical_path_asks_even_in_bypass(self) -> None:
        Q = permissions.PROMPT
        for command in ("rm -rf /", f"rm -rf {MAIN_POSIX}", "rm -rf /d/", "rm -rf C:/Users", 'rm -rf "$DIR"/*'):
            self.assert_modes("Bash", command, Q, Q, Q)
        self.assertEqual(self.judge("Bash", "rm -rf /")[1], "Claude Code: rm of a critical path")

    def test_a_loop_is_judged_by_its_commands(self) -> None:
        rules = permissions.Rules({"permissions": {"allow": ["Bash(gh pr view *)"]}})
        loop = "for n in 1 2; do echo $n; gh pr view $n; done"
        allowed = (permissions.ALLOW, "Bash(gh pr view *)")
        self.assertEqual(rules.judge("Bash", loop, MAIN, permissions.ACCEPT_EDITS), allowed)
        self.assertEqual(rules.unallowed("Bash", "for n in 1 2; do npm test; done", MAIN, permissions.DEFAULT), "npm")
        self.assertEqual(rules.judge("Bash", "if true; then ls; else pwd; fi")[0], permissions.NONE)  # `true`: no rule

    def test_the_command_takes_acceptedits(self) -> None:
        with mock.patch.object(permissions, "main", return_value=0) as replay:
            self.assertEqual(cli.main(["permissions", "--mode", "acceptEdits", "--list"]), 0)
        replay.assert_called_once_with(
            ["--before", "origin/main", "--projects", "", "--since", "", "--mode", "acceptEdits", "--list"]
        )


SP = "/c/Users/xperi/AppData/Local/Temp/claude/D--prime-game/117bb1c4/scratchpad"
# The routine patterns that prompted most in the replay of 2026-10-04..07 in acceptEdits (#312), one per cause.
ROUTINE = [
    ("Bash", f'cd {OWN} && "$PYTHON_BIN" - <<\'EOF\'\nprint(1)\nEOF'),
    ("Bash", f"cd {OWN} && git log --oneline origin/main..HEAD && git diff --stat origin/main...HEAD"),
    ("Bash", f'cd "{SP}/manager/prs"; grep -c x *.md'),
    ("Bash", f"cd {OWN} && git status && git rev-parse HEAD && git fetch --prune origin"),
    ("Bash", "gh api repos/xperiaroco2/prime-game/issues/comments/1 --jq .body | cut -c1-700"),
    ("Bash", "for n in 384 392; do gh pr view $n --json body --jq .body | tr -d '\r' | head -3; done"),
    ("Bash", f"cd {OWN} && tools/run.sh section docs/AGENT_WORKFLOW.md 2>&1 | awk '{{print}}' | head -40"),
    ("Bash", f"cd {OWN} && git show origin/main:docs/x.md | head; git merge-base HEAD origin/main"),
    ("Bash", f"cd {OWN} && printf '%s\\n' 'feat: x' > {SP}/a312/m.txt && git commit -q -F {SP}/a312/m.txt"),
    ("Bash", f"cd {OWN} && GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main"),
    ("Bash", f"cd {OWN} && git reset --soft HEAD~1 && git checkout HEAD -- docs/x.md"),
    ("Bash", f"S={SP}/a312; timeout 200 bash -c \"until grep -q exit= $S/v.log; do sleep 5; done\""),
    ("Bash", "date -u +%H:%M:%S; tools/run.sh slots --status | tail -6"),
    ("PowerShell", f"Set-Location {OWN}; tools\\run.cmd test 2>&1 | Select-Object -Last 20"),
    ("PowerShell", "gh issue view 313 --json title,body,comments | Out-String -Width 400"),
    ("PowerShell", "Get-Process godot*, python* -ErrorAction SilentlyContinue | Select-Object Name, Id"),
]


class GuardAllowsTest(unittest.TestCase):
    """#312: in acceptEdits the guard's hook allows what it finds nothing in (hooks.pre_tool_use), so a route-C
    successor and its workflows run routine shell work without a prompt; every protection still holds."""

    @staticmethod
    def judge(module: object, tool: str, command: str, mode: str = permissions.ACCEPT_EDITS) -> tuple[str, str]:
        return permissions.verdict(RULES, module, tool, command, MAIN, MAIN, TaskRepo(), mode)

    def test_the_old_prompts_are_gone(self) -> None:
        for tool, command in ROUTINE:
            with self.subTest(command=command):
                self.assertEqual(self.judge(SILENT_GUARD, tool, command)[0], permissions.PROMPT)
                self.assertEqual(self.judge(guard, tool, command)[0], permissions.PASS)
                # Default mode does not change: the hook allows only in acceptEdits.
                self.assertEqual(self.judge(guard, tool, command, permissions.DEFAULT)[0], permissions.PROMPT)

    def test_every_protection_still_holds_in_accept_edits(self) -> None:
        for command in ProtectionsTest.DENIED:
            for tool in TOOLS:
                with self.subTest(tool=tool, command=command):
                    self.assertEqual(self.judge(guard, tool, command)[0], permissions.DENIED)
        for tool, command, expected in (
            ("Bash", f"git -C {MAIN_POSIX} reset --hard", "guard: git"),
            ("Bash", f"rm -rf {MAIN_POSIX}/core", "guard: recursive delete"),
            ("Bash", f"rm -rf {OWN}/../313", "guard: recursive delete"),
            ("PowerShell", f"Remove-Item -Recurse -Force {MAIN_POSIX}\\.claude\\worktrees\\313", "guard: recursive delete"),
            ("Bash", "gh pr create -R xperiaroco2/prime-game-art --title x", "guard: gh"),
            ("Bash", "gh workflow run ci.yml", "ask rule Bash(gh workflow run*)"),
            ("Bash", "rm -rf /", "Claude Code: rm of a critical path"),
            ("Bash", f"cp x {OWN}/.claude/skills/x/SKILL.md", "no allow rule: cp (protected path .claude)"),
            ("Bash", f"echo x > {MAIN_POSIX}/.git/info/exclude", "no allow rule: echo (> protected path .git)"),
            ("Edit", f"{OWN}/.claude/agents/x.md", "no allow rule: edit (protected path .claude)"),
            ("Write", f"{OWN}/.claude/settings.json", "ask rule Edit(**/.claude/settings.json)"),
        ):  # fmt: skip
            with self.subTest(command=command):
                verdict_, why = self.judge(guard, tool, command)
                self.assertEqual(verdict_, permissions.PROMPT)
                self.assertEqual(why.split(":")[0], expected.split(":")[0])
                self.assertEqual(why, expected)


class TaskRepo(OwnRepo):
    """The own worktree 312 is on its task branch."""

    def branch(self, checkout: str) -> str | None:
        return "tooling/312-x" if checkout == guard.normalize(OWN) else "main"


class ReplayModeTest(unittest.TestCase):
    def test_default_mode_counts_calls_without_an_allow_rule(self) -> None:
        both = (RULES, guard)
        with tempfile.TemporaryDirectory() as tmp:
            write_transcript(Path(tmp) / "s.jsonl", [tool_use("1", "npm test", "2026-10-01T10:00:00Z")])
            bypass = permissions.replay(both, both, [Path(tmp)])
            default = permissions.replay(both, both, [Path(tmp)], mode=permissions.DEFAULT, listing=True)
        self.assertIn("after: 0 prompts", bypass)
        self.assertIn("after: 1 prompts (0 ask rules, 0 guard, 1 no allow rule, 0 built-in), 0 denied", default)
        self.assertIn("prompt [no allow rule: npm] x1 (session 1)", default)
        self.assertIn("'npm test'", default)


class ObservedTest(unittest.TestCase):
    def test_the_transcripts_record_asks_denials_and_blocks(self) -> None:
        ask = {"hookSpecificOutput": {"permissionDecision": "ask", "permissionDecisionReason": "git that discards: x"}}
        entries = [
            tool_use("a", "git -C D:/x reset --hard", "2026-10-02T10:00:00Z"),
            {"attachment": {"type": "hook_success", "hookEvent": "PreToolUse", "toolUseID": "a",
                            "stdout": json.dumps(ask)}, "timestamp": "2026-10-02T10:00:00Z"},
            tool_result("a", "fatal: ambiguous argument", "2026-10-02T10:01:01Z", error=True),
            tool_use("b", "git config --get core.hooksPath", "2026-10-02T11:00:00Z"),
            tool_result("b", "Permission to use Bash with command git config --get core.hooksPath has been denied.",
                        "2026-10-02T11:00:00Z", error=True),
            tool_use("c", "sleep 60; cat log", "2026-10-03T12:00:00Z"),
            tool_result("c", "<tool_use_error>Blocked: sleep 60 followed by: cat log. To wait", "2026-10-03T12:00:00Z",
                        error=True),
            tool_use("d", "git status", "2026-10-03T12:00:00Z"),
            tool_result("d", "grep found: Permission to use Bash with command x has been denied.",
                        "2026-10-03T12:00:01Z"),
        ]  # fmt: skip
        with tempfile.TemporaryDirectory() as tmp:
            write_transcript(Path(tmp) / "s" / "subagents" / "workflows" / "w" / "agent-x.jsonl", entries)
            events, skipped = permissions.observed_events([Path(tmp)], RULES, since="2026-10-01")
            report = permissions.observed([Path(tmp)], RULES)
        self.assertEqual(skipped, 0)
        self.assertEqual(
            sorted((e.kind, e.cause, e.wait, e.ran, e.role, e.when[:10]) for e in events),
            [("blocked", "Blocked: sleep N", 0.0, False, "workflow", "2026-10-03"),
             ("deny rule", "Bash(git config *hooksPath*)", 0.0, False, "workflow", "2026-10-02"),
             ("guard ask", "git that discards", 61.0, True, "workflow", "2026-10-02")],
        )  # fmt: skip
        self.assertIn("guard ask [git that discards] x1 (workflow 1) 2026-10-02..2026-10-02; wait 61 s", report)
        self.assertIn("not here: an ask rule's prompt the human approved", report)


def tool_use(key: str, command: str, when: str, tool: str = "Bash") -> dict[str, object]:
    content = [{"type": "tool_use", "id": key, "name": tool, "input": {"command": command}}]
    return {"type": "assistant", "timestamp": when, "cwd": str(ROOT), "message": {"content": content}}


def tool_result(key: str, text: str, when: str, error: bool = False) -> dict[str, object]:
    content = [{"type": "tool_result", "tool_use_id": key, "content": text, "is_error": error}]
    return {"type": "user", "timestamp": when, "message": {"content": content}}


def write_transcript(path: Path, entries: list[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="") as handle:
        handle.writelines(json.dumps(entry) + "\n" for entry in entries)


class ReplayCommandTest(unittest.TestCase):
    def test_the_runner_starts_the_replay(self) -> None:
        with mock.patch.object(permissions, "main", return_value=0) as replay:
            self.assertEqual(cli.main(["permissions", "--before", "abc123"]), 0)
        replay.assert_called_once_with(
            ["--before", "abc123", "--projects", "", "--since", "", "--mode", "bypass"]
        )
        with mock.patch.object(permissions, "main", return_value=0) as replay:
            cli.main(["permissions", "--since", "2026-09-29", "--mode", "default", "--list", "--observed"])
        replay.assert_called_once_with(
            ["--before", "origin/main", "--projects", "", "--since", "2026-09-29", "--mode", "default", "--list",
             "--observed"]
        )  # fmt: skip

    def test_since_must_be_a_day(self) -> None:
        for since in ("2026-9-29", "29.09.2026", "2026-09-29T10:00"):
            with self.subTest(since=since), mock.patch("sys.stderr"), self.assertRaises(SystemExit):
                permissions.main(["--since", since, "--observed"])


if __name__ == "__main__":
    unittest.main()
