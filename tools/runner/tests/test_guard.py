"""The thin guard: it asks before shell writes to .claude/settings*.json and addons/, and is silent otherwise."""

import unittest

from runner import guard

B, P = guard.BASH, guard.POWERSHELL
ROOT = "D:\\prime-game"
SCRATCH = "/c/Users/me/AppData/Local/Temp/claude/scratchpad"


def check(shell: str, command: str, cwd: str = ROOT) -> list[guard.Finding]:
    return guard.check(command, shell, cwd, ROOT)


# (shell, command): each one writes to an ask-protected path.
ASKS = [
    (B, "cp /tmp/settings.json .claude/settings.json"),
    (B, "cp -r ~/Downloads/gdUnit4 addons/"),
    (B, "cp x.json .claude/"),
    (B, "cp -t addons/gdUnit4 a.gd b.gd"),
    (B, "mv addons/gdUnit4 /tmp/old"),
    (B, "mv .claude/settings.json.bak .claude/settings.json"),
    (B, "echo '{}' > .claude/settings.local.json"),
    (B, "echo x >> addons/gdUnit4/plugin.cfg"),
    (B, "tools/run.sh pins 2>&1 >addons/pins.json"),
    (B, "cat x | tee .claude/settings.json"),
    (B, "rm -rf addons/gdUnit4"),
    (B, "rm .claude/settings*.json"),
    (B, "touch .claude/settings.json"),
    (B, "sed -i 's/a/b/' addons/gdUnit4/plugin.cfg"),
    (B, "cd addons && rm plugin.cfg"),
    (B, "git ls-files addons | xargs rm"),
    (B, "find addons -name '*.tmp' -delete"),
    (B, "bash -c \"cp x .claude/settings.json\""),
    (B, "python -c \"open('.claude/settings.json','w').write('{}')\""),
    (B, '"$PYTHON_BIN" -c "from pathlib import Path; Path(\'addons/x.gd\').write_text(\'\')"'),
    (B, "unzip gdUnit4.zip -d addons/"),
    (B, "tar -xzf gdUnit4.tgz -C addons"),
    (B, "curl -L -o addons/x.zip https://example.com/x.zip"),
    (B, "git checkout -- addons/gdUnit4"),
    (B, "git -C addons checkout ."),
    (B, "git rm -r addons/gdUnit4"),
    (B, "cp x /d/prime-game/.claude/settings.json"),
    (B, "cat > .claude/settings.json <<'EOF'\n{}\nEOF"),
    (B, "git status; cp x .claude/worktrees/5/addons/y"),
    (P, "Copy-Item $env:TEMP\\s.json .claude\\settings.json"),
    (P, "Copy-Item -Path x -Destination D:\\prime-game\\addons\\gdUnit4\\"),
    (P, "Copy-Item x -Destination:addons\\y"),
    (P, "Move-Item addons\\gdUnit4 $env:TEMP\\old"),
    (P, "Set-Content -Path .claude\\settings.local.json -Value '{}'"),
    (P, "'{}' | Out-File .claude\\settings.json -Encoding utf8"),
    (P, "Get-Content x | Set-Content addons\\gdUnit4\\plugin.cfg"),
    (P, "Remove-Item addons\\gdUnit4 -Recurse -Force"),
    (P, "Get-ChildItem addons -Recurse | Remove-Item"),
    (P, "Get-ChildItem addons -Filter *.tmp | ForEach-Object { Remove-Item $_.FullName }"),
    (P, '[IO.File]::WriteAllText("D:\\prime-game\\.claude\\settings.json", "{}")'),
    (P, "Set-Location addons; Remove-Item plugin.cfg"),
    (P, "Expand-Archive gdUnit4.zip -DestinationPath addons"),
    (P, "Invoke-WebRequest https://example.com/y.zip -OutFile addons\\y.zip"),
    (P, "New-Item -ItemType File .claude\\settings.local.json -Force"),
    (P, 'powershell -NoProfile -Command "Copy-Item x .claude\\settings.json"'),
    (P, '& "C:\\Program Files\\Git\\bin\\bash.exe" -c "cp x addons/"'),
    (P, "git restore addons"),
    (P, "cmd /c copy x addons\\y"),
    (P, '"{}" > .claude\\settings.json'),
    (P, "$j = '{}'\nSet-Content .claude/settings.json $j"),
    (P, 'Set-Location D:\\prime-game; $p = Join-Path $root addons; Remove-Item "$p\\x"'),
    (B, "cd /d/prime-game/tools && cp x ../addons/y"),
    (B, 'cp x "$CLAUDE_PROJECT_DIR/.claude/settings.json"'),
    (B, 'S=/d/prime-game/addons; rm -f "$S/x.gd"'),
    # Found by the stage 4 reviewers.
    (B, "find . -name '*.gd' -exec cp {} addons/ \\;"),
    (B, "xargs -I{} cp {} .claude/settings.json < list.txt"),
    (P, "$null = New-Item -ItemType Directory addons\\x"),
    (P, "$r = Copy-Item a addons -PassThru"),
    (B, "bash -lc 'cp x addons/'"),
    (B, 'sh -ec "rm -rf addons/gdUnit4"'),
    (P, 'powershell -NoProfile -Com "Remove-Item addons\\x"'),
    (B, "cp x $(git rev-parse --show-toplevel)/addons/x"),
    (B, "n=${#a[@]}; cp x addons/"),
    (B, "echo $(cp x addons/y)"),
    (P, 'Remove-Item (Join-Path $PWD "addons") -Recurse'),
    (P, 'Remove-Item -LiteralPath (Join-Path $PWD ".claude\\settings.json")'),
    (P, "Remove-Item -Path (Resolve-Path addons) -Recurse"),
    (B, "rm -rf $(pwd)/.claude/settings.json"),
    (B, 'for f in addons/*; do rm -rf "$f"; done'),
    (P, "foreach ($f in Get-ChildItem addons) { Remove-Item $f }"),
    (B, "grep -rl foo addons | xargs sed -i 's/a/b/'"),
    (B, "node -e \"require('fs').writeFileSync('addons/x.js', '')\""),
    (P, "@'\nopen('.claude/settings.json', 'w').write('{}')\n'@ | python -"),
    (B, "\"$PYTHON_BIN\" - <<'EOF'\nimport shutil\nshutil.rmtree('addons/gdUnit4')\nEOF"),
    (B, "7z x gdUnit4.7z -oaddons"),
]

# (shell, command): normal work, including reads of the protected paths; none may ask.
SILENT = [
    (B, "git status"),
    (B, "git log --oneline -3"),
    (B, "cat .claude/settings.json"),
    (B, "git add .claude/settings.json addons/"),
    (B, 'git commit -m "chore: rm addons/x from the list > .claude/settings.json"'),
    (B, "git diff -- addons"),
    (B, "cp addons/gdUnit4/plugin.cfg /tmp/plugin.cfg"),
    (B, "cp .claude/settings.json /tmp/backup.json"),
    (B, 'grep -rn "func" addons/gdUnit4 > /tmp/out.txt'),
    (B, "ls addons | wc -l"),
    (B, "sed -n '1,20p' addons/gdUnit4/plugin.cfg"),
    (B, "tar -czf /tmp/addons.tgz addons"),
    (B, "find addons -name '*.gd' | head"),
    (B, "diff .claude/settings.json /tmp/x.json"),
    (B, "cd addons && ls"),
    (B, "cd /d/prime-game && git status --short"),
    (B, 'echo "cp x addons/" > /tmp/note.txt'),
    (B, "python -c \"import json; print(json.load(open('.claude/settings.json')))\""),
    (B, "\"$PYTHON_BIN\" - <<'EOF'\nfrom pathlib import Path\nfor p in Path('addons').rglob('*.gd'):\n"
        "    print(p)\nPath('/tmp/out.txt').write_text('x')\nEOF"),  # fmt: skip
    (B, "cat > docs/x.md <<'EOF'\nRun: cp x .claude/settings.json > addons/y\nEOF"),
    (B, "tools/run.sh verify 2>&1 | tail -5"),
    (B, "mkdir -p tools/out/hookprobe && rm -rf tools/out/hookprobe"),
    (B, "chmod +x .claude/hooks/run-hook.sh .claude/githooks/pre-push"),
    (B, "git push -u origin tooling/4-hooks"),
    (B, "gh pr create --title x --body-file /tmp/body.md"),
    (B, "cd addons; cd ..; rm -f tools/out/x.log"),
    (P, "Get-Content .claude\\settings.json | ConvertFrom-Json"),
    (P, "Copy-Item .claude\\settings.json $env:TEMP\\settings.backup.json"),
    (P, "Get-ChildItem addons -Recurse | Measure-Object"),
    (P, "Get-Content addons\\gdUnit4\\plugin.cfg | Out-File $env:TEMP\\plugin.txt"),
    (P, "tools\\run.cmd doctor; git status; git log --oneline -3"),
    (P, '$d = "$env:TEMP\\x"; New-Item -ItemType Directory -Force $d | Out-Null'),
    (P, 'Remove-Item "$env:TEMP\\claude\\x\\" -Recurse; git status'),
    (P, "git log -- addons/gdUnit4 | Select-Object -First 5"),
    (P, 'Select-String -Path addons\\gdUnit4\\*.gd -Pattern "func"'),
    (P, "Compress-Archive -Path addons -DestinationPath $env:TEMP\\a.zip"),
    (P, "git stash push -m wip; git checkout main"),
    (P, "git commit -F $env:TEMP\\msg.txt"),
    (P, "$t = Measure-Command { & $g --path . --headless --import *> $null }; \"import: $($t.TotalSeconds)\""),
    (P, "gh pr view 9 --json body --jq .body | Out-File -Encoding utf8 $env:TEMP\\body.md"),
    # Found by the stage 4 reviewers: content that names a path, folders that only share the name, text that is data.
    (P, 'Add-Content .gitignore "addons/"'),
    (P, 'Set-Content x.txt -Value "addons\\foo"'),
    (P, 'Out-File -FilePath notes.txt -InputObject "addons/"'),
    (B, "rm -rf docs/addons && echo x > docs/addons/y.md"),
    (B, 'rg "json.dump(" addons'),
    (B, "git commit -F - <<'EOF'\nUse [IO.File]::WriteAllText and open(p, 'w') on addons/x\nEOF"),
    (B, "7z a /tmp/out.7z addons"),
    (B, "git ls-files addons | xargs -I{} cp {} /tmp/"),
    (P, "$null = Get-Content addons\\gdUnit4\\plugin.cfg 2>$null"),
    (B, "cp addons/gdUnit4/plugin.cfg $(mktemp)"),
    (B, "git rm --cached -q .claude/settings.local.json"),
    (B, "git restore --staged addons/gdUnit4/plugin.cfg"),
    # Scratch copies outside the project are neither its dependencies nor its settings.
    (B, f'S="{SCRATCH}"; mkdir -p "$S/lab/addons/fake" && cp x.gd "$S/lab/addons/fake/"'),
    (B, f"cd {SCRATCH} && mkdir -p gitig/.claude && cd gitig && echo '{{}}' > .claude/settings.local.json"),
    (B, f"S={SCRATCH}\ncd $S/fcgdu && cp -r /d/prime-game/addons/gdUnit4 addons/"),
    (B, "cp -r addons/gdUnit4 /tmp/lab/addons/ && cp x ~/.claude/settings.json"),
    (P, 'Copy-Item x "$env:TEMP\\lab\\addons\\y"; New-Item -ItemType Directory "$HOME\\lab\\.claude"'),
]


class GuardTest(unittest.TestCase):
    def test_asks_before_writes_to_protected_paths(self) -> None:
        for shell, command in ASKS:
            with self.subTest(shell=shell, command=command):
                self.assertTrue(check(shell, command), "expected the guard to ask")

    def test_normal_work_passes_silently(self) -> None:
        for shell, command in SILENT:
            with self.subTest(shell=shell, command=command):
                self.assertEqual(check(shell, command), [])

    def test_relative_writes_from_inside_addons_ask(self) -> None:
        self.assertTrue(check(P, "Remove-Item plugin.cfg", "D:\\prime-game\\addons\\gdUnit4"))
        self.assertTrue(check(B, "rm plugin.cfg", "/d/prime-game/addons/gdUnit4"))
        self.assertEqual(check(P, "Remove-Item plugin.cfg", "D:\\prime-game\\tools"), [])
        self.assertEqual(check(P, "Get-Content plugin.cfg", "D:\\prime-game\\addons\\gdUnit4"), [])
        self.assertEqual(check(B, "rm plugin.cfg", "C:\\Users\\me\\scratch\\addons"), [])

    def test_protected_paths(self) -> None:
        cases = {
            "addons": "addons/",
            "D:\\prime-game\\addons\\gdUnit4\\plugin.cfg": "addons/",
            "res://addons/gdUnit4/bin/GdUnitCmdTool.gd": "addons/",
            ".claude": ".claude/settings*.json",
            ".claude/settings.json": ".claude/settings*.json",
            ".claude\\settings.local.json": ".claude/settings*.json",
            ".claude/*": ".claude/settings*.json",
            "~/.claude/settings.json": ".claude/settings*.json",
            "my_addons/x": None,
            ".claude/settings.json.bak": None,
            ".claude/skills/start-task/SKILL.md": None,
            ".claude/githooks/pre-push": None,
        }
        for path, area in cases.items():
            with self.subTest(path=path):
                self.assertEqual(guard.protected(path), area)

    def test_reason_names_the_path_and_the_rule(self) -> None:
        text = guard.reason(check(B, "cp x addons/y"))
        self.assertIn("addons/y", text)
        self.assertIn("§8.2", text)


if __name__ == "__main__":
    unittest.main()
