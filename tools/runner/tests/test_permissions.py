"""The shell permission lists of .claude/settings.json with the guard (docs/AGENT_WORKFLOW.md §8.1): reads of other
repositories pass in every mode, writes there ask (issue #68); and the model of Claude Code's rule matcher."""

import re
import unittest

from runner import guard, permissions
from runner.common import ROOT

MAIN = re.sub(r"[\\/]\.claude[\\/]worktrees[\\/][^\\/]+$", "", str(ROOT))
RULES = permissions.Rules.load(ROOT / ".claude" / "settings.json")
TOOLS = ("Bash", "PowerShell")


class OwnRepo(guard.NoRepo):
    def github_repo(self) -> str | None:
        return "xperiaroco2/prime-game"


def verdict(tool: str, command: str, bypass: bool = True, rules: permissions.Rules = RULES) -> tuple[str, str]:
    return permissions.verdict(rules, guard, tool, command, str(ROOT), MAIN, OwnRepo(), bypass)


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
                for bypass in (True, False):
                    with self.subTest(tool=tool, command=command, bypass=bypass):
                        self.assertEqual(verdict(tool, command, bypass)[0], permissions.PASS)

    def test_writes_to_other_repositories_ask_in_every_mode(self) -> None:
        for tool in TOOLS:
            for command in OTHER_WRITES:
                for bypass in (True, False):
                    with self.subTest(tool=tool, command=command, bypass=bypass):
                        self.assertEqual(verdict(tool, command, bypass)[0], permissions.PROMPT)

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
                for bypass in (True, False):
                    with self.subTest(tool=tool, command=command, bypass=bypass):
                        self.assertEqual(verdict(tool, command, bypass)[0], permissions.PASS)

    def test_releases_of_this_repository_are_read_freely_and_changed_only_with_an_ok(self) -> None:
        for tool in TOOLS:
            with self.subTest(tool=tool):
                self.assertEqual(verdict(tool, "gh release view v0.1.0", bypass=False)[0], permissions.PASS)
                self.assertEqual(verdict(tool, "gh release list", bypass=False)[0], permissions.PASS)
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

    def test_bypass_runs_what_no_rule_names(self) -> None:
        rules = self.rules()
        self.assertEqual(permissions.verdict(rules, guard, "Bash", "npm test", str(ROOT), MAIN, OwnRepo())[0], "pass")
        self.assertEqual(
            permissions.verdict(rules, guard, "Bash", "npm test", str(ROOT), MAIN, OwnRepo(), bypass=False)[0], "prompt"
        )


if __name__ == "__main__":
    unittest.main()
