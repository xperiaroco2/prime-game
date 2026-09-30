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
    # Found by the second fresh review of #47: a PowerShell array names two paths.
    (P, "Remove-Item $env:TEMP\\x,addons"),
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
    (B, "rm -f docs/addons/x.md && echo x > docs/addons/y.md"),
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


NIGHT_PAD = "C:/Users/xperi/AppData/Local/Temp/claude/D--prime-game/17021f90/scratchpad"
NIGHT_PAD_PS = NIGHT_PAD.replace("/", "\\")

# (shell, command): recursive deletes and git resets that lose work in the project (issue #47); each must ask.
DANGEROUS = [
    (B, "rm -rf ."),
    (B, "rm -rf D:/prime-game/core"),
    (P, "Remove-Item -Recurse core"),
    (B, "git reset --hard"),
    (B, "git reset HEAD~1"),
    (P, "rm -r core"),
    (P, "Remove-Item core -r -Force"),
    (P, "Remove-Item -Path D:\\prime-game\\core -Recurse:$true"),
    (P, "cmd /c rmdir /s /q core"),
    (P, "git reset --hard"),
    (P, "git reset HEAD~1"),
    (B, "rm -fr /d/prime-game"),
    (B, "rm -Rf /"),
    (B, "rm -rf /d/"),
    (B, "rm --recursive core/match"),
    (B, "rm -rf *"),
    (B, "rm -rf docs/addons"),
    (B, "cd /d/prime-game/.claude/worktrees/5 && rm -rf ."),
    (B, "rm -rf $(git rev-parse --show-toplevel)/core"),
    (B, 'rm -rf "$PWD"'),
    (B, 'cd "$(git rev-parse --show-toplevel)" && rm -rf build'),
    (B, 'cd "lab$S" && cd sub$X && rm -rf y'),
    (B, "for d in core net; do rm -rf $d; done"),
    (B, "git ls-files -o core | xargs rm -rf"),
    (P, "Get-ChildItem core -Directory | Remove-Item -Recurse"),
    (P, "Get-ChildItem -Directory | ForEach-Object { Remove-Item $_.FullName -Recurse }"),
    (B, 'bash -c "rm -rf net"'),
    (B, "git reset --merge"),
    (B, "git reset --keep HEAD~2"),
    (B, "git reset --soft origin/main"),
    (B, "git reset abc1234"),
    (B, "git reset HEAD~1 --"),
    (B, "git -C /d/prime-game reset --hard"),
    (B, "cd tools && git reset -q --hard"),
    # Found by the fresh review of #47: computed targets, runner output, roots and home, spellings.
    (B, 'rm -rf "$(realpath core)"'),
    (B, 'D=$(cd core && pwd); rm -rf "$D"'),
    (B, "for d in $(ls -d */); do rm -rf $d; done"),
    (P, "$d = Resolve-Path core; Remove-Item $d -Recurse -Force"),
    (P, "Remove-Item -Recurse (Resolve-Path .\\core)"),
    (B, "git -C tools/out/logs reset --hard"),
    (B, "cd tools/out && git reset --hard"),
    (B, "rm -rf /c"),
    (B, "rm -rf /d"),
    (B, "rm -rf /*"),
    (P, "Remove-Item -Recurse C:\\"),
    (B, "rm -rf ~"),
    (B, 'rm -rf "$HOME"'),
    (P, "Remove-Item -Recurse $HOME"),
    (P, "Remove-Item -Recurse -Force $env:USERPROFILE"),
    (B, 'rm -rf "$TEMP"'),
    (P, "Set-Location $env:TEMP; Get-ChildItem -Path D:\\prime-game\\core | Remove-Item -Recurse"),
    (B, "git reset v0.1.0"),
    (B, "git reset origin/release-1.2"),
    (B, "git reset main"),
    (B, "git reset --soft x"),
    (B, "git reset net/40-net-transport"),
    (B, "ls -d core/* | xargs -n 1 rm -rf"),
    (B, "ls -d core/* | xargs -I % rm -rf %"),
    (B, "timeout 60 rm -rf core"),
    (B, "nice -n 5 rm -rf core"),
    (P, "cmd /c rd /s/q core"),
    (P, "cmd /c rd /s /q %CD%\\core"),
    (B, "find core -exec rm -rf {} +"),
    (B, "find . -mindepth 1 -delete"),
    (B, "python -c \"import shutil; shutil.rmtree('core')\""),
    (P, "[IO.Directory]::Delete('core', $true)"),
    (P, "Get-ChildItem core -Recurse | Remove-Item"),
    # The fourth prompt of wf_65292cf4-8b4 (issue #47): a temporary folder inside the project, not the scratch folder.
    (B, "rm -r tests/integration/tmp && tools/run.sh test tests/integration"),
    (B, "rm -rf tests"),
    (B, "rm -rf tests/scratchpad"),
    (B, "rm -rf tests/scratch/../integration"),
    (B, "git -C tests/scratch reset --hard"),
    # Found by the second fresh review of #47: arrays, subshells, variables no call assigned, rare spellings.
    (P, "Remove-Item -Recurse -Force tests\\scratch\\probe,tests\\integration\\tmp"),
    (P, "Remove-Item -Recurse $env:TEMP\\x,core"),
    (P, "foreach ($d in 'tests\\scratch\\a','core') { Remove-Item -Recurse $d }"),
    (P, "Remove-Item -Recurse @('tests\\scratch\\a', 'core')"),
    (B, "(cd /tmp && ls); rm -rf core"),
    (B, "X=$(cd /tmp && pwd); rm -rf core"),
    (B, "(cd tools/out && ls); rm -rf net"),
    (B, 'cd "$S" && rm -rf sandbox'),
    (B, 'rm -rf "$X"/*'),
    (B, "cd /tmp && cd - && rm -rf build"),
    (B, "pushd /tmp && popd && rm -rf build"),
    (B, "rm -rf tests/scratch/{x,../../core}"),
    (B, "git --git-dir .git reset --hard"),
    (B, "git --work-tree=. reset --hard"),
    (B, "rm --rec core"),
    (B, 'cmd //c "rd //s //q core"'),
    (B, "find core -name '*' -delete"),
    (B, "find . -path ./tests/scratch -prune -o -delete"),
    (P, "Get-ChildItem -Recurse -Filter * | Remove-Item"),
]

# (shell, command): deletes outside the project and git resets that only unstage; none may ask.
HARMLESS = [
    # The three prompts of the overnight run wf_65292cf4-8b4 (issue #47), and their PowerShell twins.
    (B, f'SP="{NIGHT_PAD}"; rm -rf "$SP/sandbox" 2>/dev/null; mkdir -p "$SP/sandbox"'),
    (B, f"S={NIGHT_PAD}/old && rm -rf $S && mkdir -p $S && cd D:/prime-game/.claude/worktrees/45"),
    (B, f"cd D:/prime-game/.claude/worktrees/33 && S={NIGHT_PAD} && git reset -q && git add -A"),
    (P, f'$SP = "{NIGHT_PAD_PS}"; Remove-Item "$SP\\sandbox" -Recurse -Force -ErrorAction SilentlyContinue'),
    (P, f'$S = "{NIGHT_PAD_PS}\\old"; Remove-Item -Recurse -Force $S; New-Item -ItemType Directory $S'),
    (P, "Set-Location D:\\prime-game\\.claude\\worktrees\\33; git reset -q"),
    # Other scratch deletes.
    (B, "rm -rf /tmp/lab ~/scratch"),
    (B, 'rm -rf "$TEMP/x" "$TMPDIR/y"'),
    (B, f"rm -rf {NIGHT_PAD}/sandbox"),
    (P, "Remove-Item -Recurse -Force $env:TEMP\\claude\\old"),
    (P, "rm -r $env:TEMP\\x"),
    (P, "cmd /c rmdir /s /q %TEMP%\\x"),
    (B, "find /tmp/x -type d | xargs rm -rf"),
    (P, "Get-ChildItem $env:TEMP\\x | Remove-Item -Recurse"),
    (B, "cd /tmp && rm -rf lab"),
    (B, 'cd /tmp && cd "lab$S" && rm -rf sandbox && cd sub$X && rm -rf y'),
    (B, "rm -rf tools/out/hookprobe"),
    (B, "rm -rf .claude/worktrees/5/tools/out/gdunit"),
    (B, "rm -r -- -x"),
    (B, "rm -f core/x.gd.orig"),
    (P, "Remove-Item core\\x.tmp"),
    # Unstaging only changes the index.
    (B, "git reset"),
    (B, "git reset -q"),
    (B, "git reset -- core/x.gd docs/"),
    (B, "git reset HEAD -- core/x.gd"),
    (B, "git reset HEAD core/x.gd"),
    (B, "git reset core/x.gd"),
    (B, "git reset --mixed"),
    (P, "git reset -- core\\x.gd"),
    (P, "git reset HEAD -- core\\x.gd"),
    # Resets of a scratch repository.
    (B, "cd /tmp/lab && git reset --hard HEAD~1"),
    (B, "git -C $TEMP/lab reset --hard"),
    (B, 'git commit -m "docs: never run rm -rf . or git reset --hard"'),
    # Found by the fresh review of #47.
    (B, 'rm -rf "$(mktemp -d)"'),
    (B, 'D=$(mktemp -d); rm -rf "$D"'),
    (B, 'rm -rf "/tmp/x-$(date +%s)"'),
    (P, "$SP = Join-Path $env:TEMP claude; Remove-Item -Recurse $SP"),
    (P, "Get-ChildItem -Path $env:TEMP\\x | Remove-Item -Recurse"),
    (P, "Get-ChildItem $env:TEMP\\x | ForEach-Object { Remove-Item $_.FullName -Recurse }"),
    (P, "Get-ChildItem $env:TEMP\\x | Where-Object { $_.Name -like 'old*' } | Remove-Item -Recurse"),
    (P, "foreach ($d in Get-ChildItem $env:TEMP\\x) { Remove-Item $d -Recurse }"),
    (P, "rm -Force core\\x.tmp"),
    (P, "rm -ErrorAction SilentlyContinue x"),
    (P, "rm -LiteralPath x"),
    (P, "rm x -Verbose"),
    (B, "rm -rf ~/scratch"),
    (B, "rm -rf .godot/imported"),
    (B, "git reset core"),
    (B, "git reset tools/runner"),
    (B, "git reset LICENSE"),
    (B, "find . -name '*.orig' -delete"),
    (B, "find /tmp/x -exec rm -rf {} +"),
    (P, "cmd /c rd /s/q %TEMP%\\x"),
    (B, "rm -rf /tmp/x/*"),
    (P, "$out = & $g --headless --path . --import 2>&1 | Out-String"),
    (P, "$t = New-TemporaryFile; Remove-Item -Recurse $t"),
    (P, "Get-ChildItem -Recurse -Filter *.tmp | Remove-Item"),
    (B, "find . -name '*.orig' | xargs rm"),
    (B, "git reset feature-x"),
    # The gitignored scratch folder (issue #47), in the main checkout and in a worktree.
    (B, "rm -r tests/scratch/x"),
    (B, "rm -rf tests/scratch"),
    (B, "rm -rf .claude/worktrees/46/tests/scratch/probe"),
    (B, "cd /d/prime-game/.claude/worktrees/46 && rm -r tests/scratch/probe && tools/run.sh test tests/scratch"),
    (P, "Remove-Item -Recurse -Force tests\\scratch\\probe"),
    (P, "Get-ChildItem tests\\scratch | Remove-Item -Recurse"),
    # Found by the second fresh review of #47.
    (B, 'rm -rf "$(git rev-parse --show-toplevel)/tests/scratch"'),
    (B, "rm -rf tools/runner/__pycache__"),
    (B, "(cd /tmp && rm -rf lab); rm -rf tests/scratch/x"),
    (B, "find . -path ./tests/scratch -prune -o -name '*.orig' -delete"),
    (B, "cd /tmp && pushd lab && popd && rm -rf x"),
    (B, "rm -rf tests/scratch/{a,b}"),
    (P, "Remove-Item -Recurse $env:TEMP\\a,$env:TEMP\\b"),
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

    def test_asks_before_losing_work_in_the_project(self) -> None:
        for shell, command in DANGEROUS:
            with self.subTest(shell=shell, command=command):
                self.assertTrue(check(shell, command), "expected the guard to ask")

    def test_scratch_deletes_and_unstaging_pass(self) -> None:
        for shell, command in HARMLESS:
            with self.subTest(shell=shell, command=command):
                self.assertEqual(check(shell, command), [])

    def test_a_worktree_session_still_protects_the_main_checkout(self) -> None:
        worktree = ROOT + "\\.claude\\worktrees\\47"
        self.assertTrue(guard.check("rm -rf D:/prime-game/core", B, worktree, worktree))
        self.assertTrue(guard.check("rm -rf core", B, worktree, worktree))
        self.assertEqual(guard.check("rm -rf /tmp/x", B, worktree, worktree), [])
        self.assertEqual(guard.check("rm -r tests/scratch/x", B, worktree, worktree), [])
        self.assertTrue(guard.check("rm -r tests/integration/tmp", B, worktree, worktree))
        top = '"$(git rev-parse --show-toplevel)'
        self.assertEqual(guard.check(f'rm -rf {top}/tests/scratch/x"', B, worktree, worktree), [])
        self.assertTrue(guard.check(f'rm -rf {top}/core"', B, worktree, worktree))
        self.assertTrue(guard.check(f'rm -rf {top}/core"', B, "/tmp", worktree))

    def test_a_folder_named_addons_elsewhere_is_no_protected_area(self) -> None:
        # rm -rf docs/addons asks as a recursive delete in the project, never as a change to addons/.
        self.assertEqual({f.area for f in check(B, "rm -rf docs/addons")}, {guard.DELETE})

    def test_pipeline_targets_are_the_paths_the_pipeline_starts_from(self) -> None:
        cases = {
            "Get-ChildItem -Directory | ForEach-Object { Remove-Item $_.FullName -Recurse }": ".",
            "Get-ChildItem core -Directory | Remove-Item -Recurse": "core",
            "Get-ChildItem -Path net | Where-Object { $_.Name -like 'x*' } | Remove-Item -Recurse": "net",
        }
        for command, path in cases.items():
            with self.subTest(command=command):
                self.assertEqual([f.path for f in check(P, command)], [path])
        self.assertEqual([f.path for f in check(B, "git ls-files -o core | xargs rm -rf")], ["core"])

    def test_the_project_name_comes_from_its_folder(self) -> None:
        root = "C:\\dev\\game"
        self.assertTrue(guard.check('cd "lab$S" && rm -rf y', B, root, root))
        self.assertTrue(guard.check('rm -rf "$X/game"', B, "/tmp", root))
        self.assertEqual(guard.check('rm -rf "$X/prime-game"', B, "/tmp", root), [])
        self.assertEqual(guard.check('cd /tmp && cd "lab$S" && rm -rf y', B, root, root), [])

    def test_a_project_under_home_stays_protected(self) -> None:
        root, home = "C:\\Users\\me\\game", "C:\\Users\\me"
        self.assertTrue(guard.check("rm -rf ~/game/core", B, "/tmp", root, home))
        self.assertTrue(guard.check('rm -rf "$HOME/game"', B, "/tmp", root, home))
        self.assertTrue(guard.check("Remove-Item -Recurse $env:USERPROFILE\\game", P, "/tmp", root, home))
        self.assertTrue(guard.check("rm -rf ~", B, "/tmp", root, home))
        self.assertEqual(guard.check("rm -rf ~/scratch", B, "/tmp", root, home), [])

    def test_reason_names_the_delete_and_the_reset(self) -> None:
        text = guard.reason(check(B, "rm -rf core; git reset --hard"))
        self.assertIn("Recursive delete in the project: rm -> core", text)
        self.assertIn("git reset --hard", text)
        self.assertIn("§8.2", text)

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
