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


# Issue #51: the session's own worktree and task branch, and the other checkouts and branches of the repository.
OWN = ROOT + "\\.claude\\worktrees\\51"
TASK = "tooling/51-freedom"


class FakeRepo(guard.NoRepo):
    """Branches of the main checkout and two worktrees, and the branches the stash entries were made on."""

    def __init__(
        self, stash: list[str] | None = None, own: str | None = TASK, busy: tuple[str, ...] = ()
    ) -> None:
        self.stash = stash if stash is not None else [TASK]
        self.own = own  # the branch checked out in worktree 51; None is a detached HEAD
        self.busy_worktrees = busy

    def branch(self, checkout: str) -> str | None:
        return {
            "d:/prime-game": "main",
            "d:/prime-game/.claude/worktrees/51": self.own,
            "d:/prime-game/.claude/worktrees/47": "tooling/47-guard",
        }.get(checkout)

    def busy(self, checkout: str) -> bool:
        return checkout.rsplit("/", 1)[-1] in self.busy_worktrees

    def refs(self) -> set[str]:
        return {"main", "origin/main", TASK, "tooling/47-guard", "origin/tooling/47-guard", "feature-x"}

    def stash_branches(self) -> list[str] | None:
        return self.stash


def in_own(shell: str, command: str, cwd: str = OWN, repo: guard.NoRepo | None = None) -> list[guard.Finding]:
    return guard.check(command, shell, cwd, ROOT, "", repo or FakeRepo())


# (shell, command) run by a session in its own worktree 51 on its task branch: work there never asks.
OWN_WORK = [
    (B, "git reset --hard"),
    (B, "git reset --hard origin/main"),
    (B, "git reset HEAD~2"),
    (B, "git rebase origin/main"),
    (B, "git rebase --onto origin/main origin/tooling/47-guard"),
    (B, f"git rebase origin/main {TASK}"),
    (B, "git rebase --continue"),
    (B, "git rebase --abort"),
    (B, "git clean -fdx"),
    (B, "git clean -fd core tests"),
    (B, "git checkout -- core/x.gd"),
    (B, "git checkout ."),
    (B, "git checkout -f"),
    (B, "git checkout origin/main -- core/x.gd"),
    (B, "git checkout main"),  # a plain switch discards nothing
    (B, "git restore core/x.gd"),
    (B, "git restore --source origin/main -- core"),
    (B, f"git switch -f {TASK}"),
    (B, f"git switch --discard-changes {TASK}"),
    (B, f"git switch -c {TASK}-spike && git reset --hard origin/main"),
    (B, "git stash drop"),
    (B, "git stash drop stash@{0}"),
    (B, "git stash clear"),
    (B, f"git branch -D {TASK}-backup"),
    (B, f"git branch -d {TASK}/probe"),
    (B, f"git branch -f {TASK}-backup HEAD~1"),
    (B, "git -c core.editor=true rebase origin/main"),
    # An interactive rebase whose todo editor is a no-op opens no editor (#104).
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash origin/release/m3"),
    (B, "git commit -q --fixup=HEAD && GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=true git rebase --interactive origin/main"),
    (B, "export GIT_SEQUENCE_EDITOR=:; git rebase -i --autosquash origin/main"),
    # With fixup! commits only: a squash! commit would still open GIT_EDITOR for its message, as a plain
    # `rebase --autosquash` does.
    (B, "GIT_SEQUENCE_EDITOR=: GIT_EDITOR=vim git rebase -i --autosquash origin/main"),
    (B, "export GIT_SEQUENCE_EDITOR=vim; GIT_SEQUENCE_EDITOR=:; git rebase -i --autosquash origin/main"),
    (B, "export GIT_SEQUENCE_EDITOR=:; bash -c 'git rebase -i --autosquash origin/main'"),
    (B, "GIT_SEQUENCE_EDITOR=':' git rebase -i --autosquash origin/main"),
    (P, "$env:GIT_SEQUENCE_EDITOR = ':'; git rebase -i --autosquash origin/main"),
    # Options are read as git reads them (#105): bundled short flags, values, unique prefixes, and a prefix that a
    # nested shell inherits.
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -qi --autosquash origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: bash -c 'git rebase -i --autosquash origin/main'"),
    (B, "env GIT_SEQUENCE_EDITOR=: bash -c 'git rebase -i --autosquash origin/main'"),
    (B, 'GIT_SEQUENCE_EDITOR=: powershell -Command "git rebase -i --autosquash origin/main"'),
    (B, "git rebase -Xtheirs origin/main"),
    (B, "git rebase -s ort -Xignore-space-change origin/main"),
    (B, f"git rebase --ont origin/main HEAD~2 {TASK}"),
    (B, f"git rebase -fs ort origin/main {TASK}"),
    (B, "git rebase --cont"),
    (B, "git rebase --no-up origin/main"),
    (B, "git -c rebase.updateRefs=false rebase origin/main"),
    (B, "git -c rebase.updateRefs= rebase origin/main"),
    (B, "git -c rebase.updateRefs=true rebase --no-update-refs origin/main"),
    (B, "git -c user.name=x commit -m y"),
    (B, "git worktree list"),
    (B, "rm -rf core/match"),
    (B, "rm -rf tests/integration/tmp && tools/run.sh test tests/integration"),
    (B, "rm -rf *"),
    (B, 'rm -rf "$(git rev-parse --show-toplevel)/core"'),
    (B, "rm -rf D:/prime-game/.claude/worktrees/51/core"),
    (B, "find core -delete"),
    (B, "cd core && git reset --hard && rm -rf match"),
    (P, "git reset --hard"),
    (P, "git rebase origin/main"),
    (P, "git clean -fdx"),
    (P, "git checkout -- core\\x.gd"),
    (P, "git restore core\\x.gd"),
    (P, "Remove-Item -Recurse -Force core\\match"),
    (P, "rm -r tests\\integration\\tmp"),
    (P, "git stash drop; git branch -D tooling/51-freedom-backup"),
    (B, f"git update-ref -d refs/heads/{TASK}-backup"),
    (B, "git worktree remove --force D:/prime-game/.claude/worktrees/51"),
]

# The same work reached the way a manager's task session does it: its shell starts in the main checkout, and each
# command first moves into its worktree.
MANAGED_WORK = [
    (B, "cd D:/prime-game/.claude/worktrees/51 && git reset --hard"),
    (B, "cd /d/prime-game/.claude/worktrees/51 && git rebase origin/main"),
    (
        B,
        "cd /d/prime-game/.claude/worktrees/51 && git add -A && git commit -q --fixup=HEAD && "
        "GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash origin/release/m3",
    ),
    (B, "cd D:/prime-game/.claude/worktrees/51 && git clean -fdx"),
    (B, "cd D:/prime-game/.claude/worktrees/51 && git checkout -- core/x.gd"),
    (B, "cd D:/prime-game/.claude/worktrees/51 && rm -rf tests/integration/tmp"),
    (B, "git -C D:/prime-game/.claude/worktrees/51 reset --hard origin/main"),
    (P, "Set-Location D:\\prime-game\\.claude\\worktrees\\51; git reset --hard"),
    (P, "cd D:\\prime-game\\.claude\\worktrees\\51; git rebase origin/main"),
    (P, "Set-Location D:\\prime-game\\.claude\\worktrees\\51; Remove-Item -Recurse -Force core\\match"),
]

# (shell, command) from the own worktree that reach the main checkout, another worktree or another branch: each asks.
BEYOND_OWN = [
    (B, "git -C D:/prime-game reset --hard"),
    (B, "cd D:/prime-game && git reset --hard"),
    (B, "cd ../47 && git reset --hard"),
    (B, "git -C ../47 rebase origin/main"),
    (B, "git -C D:/prime-game/.claude/worktrees/47 clean -fdx"),
    (B, "cd D:/prime-game && git clean -fdx"),
    (B, "git --work-tree=D:/prime-game checkout -- core"),
    (B, "git --git-dir=D:/prime-game/.git reset --hard"),
    (B, "git --git-dir D:/prime-game/.git/worktrees/47 reset --hard"),
    (B, "git -C D:/prime-game restore core"),
    (B, "git checkout -- ../47/core"),
    (B, "git restore D:/prime-game/core/x.gd"),
    (B, "rm -rf D:/prime-game/core"),
    (B, "rm -rf ../47/core"),
    (B, "rm -rf D:/prime-game/.claude/worktrees/47"),
    (B, "rm -rf ."),
    (B, "rm -rf ../51"),
    (B, "git rebase origin/main tooling/47-guard"),
    (B, "git rebase --root main"),
    (B, "git branch -D tooling/47-guard"),
    (B, "git branch -d main"),
    (B, "git branch -f main HEAD"),
    (B, "git branch -M main"),
    (B, "git switch -f main"),
    (B, "git switch --discard-changes main"),
    (B, "git checkout -f main"),
    (B, "git checkout -B main origin/main"),
    (B, "git switch -C tooling/47-guard"),
    (B, "git checkout main && git reset --hard origin/main"),
    (B, "git switch main; git clean -fdx"),
    (B, "git rebase -i HEAD~3"),
    (B, "git rebase --interactive origin/main"),
    # An interactive rebase that opens an editor, whichever setting names it, and the other rewrites still ask
    # with a no-op todo editor (#104).
    (B, "GIT_SEQUENCE_EDITOR=vim git rebase -i origin/main"),
    (B, "GIT_SEQUENCE_EDITOR= git rebase -i origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=code GIT_EDITOR=: git rebase -i origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=$E git rebase -i origin/main"),
    # Only GIT_SEQUENCE_EDITOR outranks every other setting (an inherited one, the git config files), so the lower
    # tiers still ask.
    (B, "GIT_EDITOR=: git rebase -i origin/main"),
    (B, "git -c core.editor=true rebase -i origin/main"),
    (B, "git -c sequence.editor=: rebase -i --autosquash origin/main"),
    # A shell variable that is not exported never reaches git; a prefix is the next command's only.
    (B, "GIT_SEQUENCE_EDITOR=:; git rebase -i --autosquash origin/main"),
    (P, "$GIT_SEQUENCE_EDITOR = ':'; git rebase -i --autosquash origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: git log -1; git rebase -i origin/main"),
    (B, "(export GIT_SEQUENCE_EDITOR=:); git rebase -i origin/main"),
    # A later value or `unset` of the exported variable is what git sees; each shell's own syntax only.
    (B, "export GIT_SEQUENCE_EDITOR=:; GIT_SEQUENCE_EDITOR=vim; git rebase -i origin/main"),
    (B, "export GIT_SEQUENCE_EDITOR=:; unset GIT_SEQUENCE_EDITOR; git rebase -i origin/main"),
    (P, "$env:GIT_SEQUENCE_EDITOR = ':'; Remove-Item Env:GIT_SEQUENCE_EDITOR; git rebase -i origin/main"),
    (B, "$env:GIT_SEQUENCE_EDITOR = ':'; git rebase -i origin/main"),
    (P, "export GIT_SEQUENCE_EDITOR=:; git rebase -i origin/main"),
    (B, "export GIT_SEQUENCE_EDITOR=$E; git rebase -i origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -i --update-refs origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -i -x 'tools/run.sh test' origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main main"),
    (B, "git rebase --update-refs origin/main"),
    # Every spelling git accepts (#105): bundled short flags, an attached value, unique prefixes of long options,
    # `rebase.updateRefs` from `-c`, and a prefix a nested shell inherits.
    (B, "git rebase -qi origin/main"),
    (B, "git rebase -ir origin/main"),
    (B, "git rebase -rx 'tools/run.sh test' origin/main"),
    (B, "git rebase -qx 'tools/run.sh test' origin/main"),
    (B, "git rebase -x'tools/run.sh test' origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -i -x'tools/run.sh test' --autosquash origin/main"),
    (B, "git rebase --interac origin/main"),
    (B, "git rebase --in origin/main"),
    (B, "git rebase --edit-t"),
    (B, "git rebase --exe=true origin/main"),
    (B, "git rebase --ex true origin/main"),
    (B, "git rebase --update-ref origin/main"),
    (B, "git rebase --up origin/main"),
    (B, "git rebase --ro main"),
    (B, "git rebase --ont origin/main HEAD~2 main"),
    (B, "git -c rebase.updateRefs=true rebase origin/main"),
    (B, "git -c rebase.updateRefs=yes rebase origin/main"),
    (B, "git -c rebase.updateRefs rebase origin/main"),
    (B, "git -c REBASE.UPDATEREFS=on rebase origin/main"),
    (B, "git --config-env=rebase.updateRefs=V rebase origin/main"),
    (B, "git -c rebase.updateRefs=false rebase --update-refs origin/main"),
    (P, "git -c rebase.updateRefs=true rebase origin/main"),
    (B, "export GIT_SEQUENCE_EDITOR=:; GIT_SEQUENCE_EDITOR=vim bash -c 'git rebase -i origin/main'"),
    (B, "GIT_SEQUENCE_EDITOR=$E bash -c 'git rebase -i origin/main'"),
    # Found by the review of #105: a prefix the guard cannot compute still names the project inside the nested shell.
    (B, "D=$(realpath core) bash -c 'rm -rf \"$D\"'"),
    (B, "D=$X bash -c 'rm -rf \"$D\"'"),
    (B, f"git -c core.hooksPath=/dev/null push origin {TASK}"),
    (B, "git worktree remove D:/prime-game/.claude/worktrees/47"),
    (B, "git worktree remove --force ../47"),
    (P, "git -C D:\\prime-game reset --hard"),
    (P, "Set-Location D:\\prime-game; git clean -fdx"),
    (P, "Remove-Item -Recurse -Force D:\\prime-game\\core"),
    (P, "Set-Location ..\\47; git checkout -- core"),
    (P, "git rebase origin/main tooling/47-guard"),
    (P, "git branch -D tooling/47-guard"),
    (P, "git checkout -f main"),
    # A manager's task session that moved into its worktree, then reaches another checkout.
    (B, "cd D:/prime-game/.claude/worktrees/51 && git -C ../47 reset --hard"),
    (B, "cd D:/prime-game/.claude/worktrees/51 && cd D:/prime-game && git clean -fdx"),
    # Found by the review of #51: git names a worktree by the last parts of its path.
    (B, "git worktree remove 47"),
    (B, "git worktree remove --force worktrees/47"),
    (B, "git worktree move 47 /tmp/x"),
    (B, "cd D:/prime-game/.claude/worktrees/51 && git worktree remove --force 47"),
    # The repository and the working tree are judged apart; GIT_DIR and GIT_WORK_TREE count like the options.
    (B, "git --git-dir=D:/prime-game/.git --work-tree=. reset --hard HEAD~3"),
    (B, "GIT_DIR=D:/prime-game/.git git reset --hard HEAD~3"),
    (B, "export GIT_DIR=D:/prime-game/.git; git reset --hard HEAD~3"),
    (B, "GIT_WORK_TREE=D:/prime-game git checkout -- core"),
    (B, 'GIT_DIR="$(cat f)" git reset --hard'),
    (P, "$env:GIT_DIR = 'D:\\prime-game\\.git'; git reset --hard HEAD~3"),
    # A checkout in a nested shell leaves the task branch for the rest of the command too.
    (B, "bash -c 'git checkout main'; git reset --hard origin/main"),
    (B, "git rebase -x 'rm -rf ../../core' origin/main"),
    (B, "git rebase --exec=true origin/main"),
    (B, "git update-ref -d refs/heads/tooling/47-guard"),
    (B, "git update-ref refs/heads/main HEAD"),
    (B, "git update-ref --stdin"),
]

# (shell, command) in the main checkout (the designer, the engineer's `--here`, a manager): each asks.
MAIN_CHECKOUT = [
    (B, "git rebase origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/main"),
    (B, "git clean -fdx"),
    (B, "git checkout -- core/x.gd"),
    (B, "git checkout ."),
    (B, "git restore core"),
    (B, "git stash drop"),
    (B, "git stash clear"),
    (B, "git branch -d core/42-vote-tally"),
    (B, "git branch -D core/42-vote-tally"),
    (B, "git switch -f main"),
    (B, "git worktree remove .claude/worktrees/47"),
    (B, "rm -rf core/match"),
    (P, "git rebase origin/main"),
    (P, "git clean -fdx"),
    (P, "git restore core"),
    (P, "Remove-Item -Recurse core\\match"),
]

# (shell, command) that discard nothing, or act outside the project: silent in every checkout.
ANYWHERE = [
    (B, "git worktree list"),
    (B, "git worktree add ../x -b x"),
    (B, "git clean -n"),
    (B, "git clean -ndx"),
    (B, "git restore --staged core/x.gd"),
    (B, "git switch main"),
    (B, "git checkout main"),
    (B, "git branch -a"),
    (B, "git branch --list 'tooling/*'"),
    (B, "git stash list"),
    (B, "git stash push -m wip"),
    (B, "cd /tmp/lab && git rebase main && git reset --hard HEAD~1 && git clean -fdx"),
    (B, "git -C /tmp/lab checkout -f other"),
    # Found by the replay of #51: a scratch clone's own branches and stash.
    (B, 'C="$TEMP/clone"; cd "$C" && git switch -q tooling/6-skills && git branch -q -D scratch-base'),
    (B, "cd /tmp/lab && git stash clear && git rebase origin/main other && git switch -C x"),
    (P, "git -C $env:TEMP\\lab clean -fdx"),
    (B, "git worktree remove --force /tmp/wt"),
]


class OwnWorktreeTest(unittest.TestCase):
    def test_work_in_the_own_worktree_passes(self) -> None:
        for shell, command in OWN_WORK:
            with self.subTest(shell=shell, command=command):
                self.assertEqual(in_own(shell, command), [])

    def test_a_task_session_started_in_the_main_checkout_owns_the_worktree_it_enters(self) -> None:
        for shell, command in MANAGED_WORK:
            with self.subTest(shell=shell, command=command):
                self.assertEqual(in_own(shell, command, cwd=ROOT), [])

    def test_reaching_beyond_the_own_worktree_or_branch_asks(self) -> None:
        for shell, command in BEYOND_OWN:
            with self.subTest(shell=shell, command=command):
                self.assertTrue(in_own(shell, command), "expected the guard to ask")

    def test_the_main_checkout_is_never_owned(self) -> None:
        for shell, command in MAIN_CHECKOUT:
            with self.subTest(shell=shell, command=command):
                self.assertTrue(in_own(shell, command, cwd=ROOT), "expected the guard to ask")

    def test_what_discards_nothing_passes_everywhere(self) -> None:
        for shell, command in ANYWHERE:
            for cwd in (ROOT, OWN):
                with self.subTest(shell=shell, command=command, cwd=cwd):
                    self.assertEqual(in_own(shell, command, cwd=cwd), [])

    def test_stash_entries_of_other_branches_ask(self) -> None:
        # A human's `start --stash` entry is made on main; the stash is shared by every checkout.
        repo = FakeRepo(stash=[TASK, "main"])
        self.assertEqual(in_own(B, "git stash drop", repo=repo), [])
        self.assertTrue(in_own(B, "git stash drop stash@{1}", repo=repo))
        self.assertTrue(in_own(B, "git stash drop 1", repo=repo))
        self.assertTrue(in_own(B, "git stash clear", repo=repo))
        self.assertTrue(in_own(B, "git stash drop", repo=guard.NoRepo()))  # unknown entries are not its own

    def test_another_branch_checked_out_in_the_own_worktree_is_not_the_task_branch(self) -> None:
        # Found by the review of #51: `git checkout core/42-vote` in one call, then work that discards in the next.
        repo = FakeRepo(own="core/42-vote")
        for command in ("git reset --hard HEAD~1", "git rebase origin/main", "git branch -D core/42-vote-x"):
            with self.subTest(command=command):
                self.assertTrue(in_own(B, command, repo=repo), "expected the guard to ask")
        self.assertTrue(in_own(B, "git clean -fdx", cwd=ROOT, repo=repo))
        self.assertEqual(in_own(B, "git reset --hard", repo=FakeRepo(own=None)), [])  # a detached HEAD
        spike = FakeRepo(own=f"{TASK}-spike")  # a helper checked out: back to the task branch passes
        self.assertEqual(in_own(B, f"git switch -f {TASK} && git reset --hard origin/main", repo=spike), [])
        self.assertTrue(in_own(B, "git branch -D tooling/51", repo=spike))

    def test_the_stash_changed_earlier_in_the_command_asks(self) -> None:
        repo = FakeRepo(stash=["main", TASK])
        self.assertTrue(in_own(B, "git stash; git stash drop stash@{1}", repo=repo))
        self.assertTrue(in_own(B, "git stash push -m x && git stash clear", repo=repo))
        self.assertEqual(in_own(B, "git stash drop stash@{1}; git stash list", repo=repo), [])

    def test_a_worktree_another_session_works_in_is_not_claimed(self) -> None:
        repo = FakeRepo(busy=("12",))
        self.assertTrue(in_own(B, "cd D:/prime-game/.claude/worktrees/12 && git reset --hard", cwd=ROOT, repo=repo))
        self.assertTrue(in_own(B, "cd D:/prime-game/.claude/worktrees/12 && rm -rf core", cwd=ROOT, repo=repo))
        own = "cd D:/prime-game/.claude/worktrees/51 && git reset --hard"
        self.assertEqual(in_own(B, own, cwd=ROOT, repo=repo), [])

    def test_without_the_repository_no_branch_is_the_sessions_own(self) -> None:
        self.assertTrue(in_own(B, f"git branch -D {TASK}-backup", repo=guard.NoRepo()))
        self.assertEqual(in_own(B, "git reset --hard", repo=guard.NoRepo()), [])

    def test_only_the_first_worktree_a_command_enters_is_owned(self) -> None:
        command = "cd D:/prime-game/.claude/worktrees/51 && cd ../47 && git reset --hard"
        self.assertTrue(in_own(B, command, cwd=ROOT))

    def test_protected_paths_still_ask_in_the_own_worktree(self) -> None:
        self.assertTrue(in_own(B, "rm -rf addons/gdUnit4"))
        self.assertTrue(in_own(B, "git checkout -- addons"))
        self.assertTrue(in_own(P, "Remove-Item -Recurse .claude"))

    def test_reason_says_why_git_asks(self) -> None:
        text = guard.reason(in_own(B, "git rebase origin/main tooling/47-guard; git -C D:/prime-game clean -fdx"))
        self.assertIn("rewrites another branch (tooling/47-guard)", text)
        self.assertIn("outside this session's own worktree", text)
        self.assertIn("§8.2", text)


# Issue #381: a cloud session works in the main checkout, on its task branch, with no worktree.
CLOUD_TASK = "tooling/381-guard-cloud-checkout"


class CloudRepo(FakeRepo):
    """The main checkout of a cloud session, on main_branch; worktree 47 belongs to another session."""

    def __init__(self, main_branch: str | None = CLOUD_TASK, stash: list[str] | None = None) -> None:
        super().__init__(stash=stash if stash is not None else [CLOUD_TASK])
        self.main_branch = main_branch

    def branch(self, checkout: str) -> str | None:
        return self.main_branch if checkout == "d:/prime-game" else super().branch(checkout)

    def refs(self) -> set[str]:
        return super().refs() | {CLOUD_TASK, "release/m6", "origin/release/m6"}


def in_cloud(
    shell: str, command: str, cwd: str = ROOT, repo: guard.NoRepo | None = None, cloud: bool = True
) -> list[guard.Finding]:
    return guard.check(command, shell, cwd, ROOT, "", repo or CloudRepo(), cloud=cloud)


# (shell, command) run by a cloud session in the main checkout on its task branch: its own work never asks.
CLOUD_WORK = [
    (B, "git reset -q --soft HEAD~2"),
    (B, "git reset --hard origin/main"),
    (B, "git rebase origin/main"),
    (B, "GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash origin/tooling/381-guard-cloud-checkout"),
    (B, "git checkout -- tools/runner/guard.py"),
    (B, "git restore core/x.gd"),
    (B, "git clean -fd"),
    (B, "git checkout -f"),
    (B, f"git branch -D {CLOUD_TASK}-backup"),
    (B, "git stash drop"),
    (B, "rm -rf core/tmp"),
    (B, "cd core && git reset --hard HEAD~1 && rm -rf tmp"),
    (B, "cd /tmp && git -C D:/prime-game reset --soft HEAD~1"),
    (P, "git reset --soft HEAD~2; Remove-Item -Recurse tests\\integration\\tmp"),
    # Found by the review of #381: a nested shell keeps the cloud session's task branch.
    (B, "bash -c 'git reset --soft HEAD~1'"),
    (B, "GIT_SEQUENCE_EDITOR=: bash -c 'git rebase -i --autosquash origin/main'"),
    (B, "git clean -fd core"),
]

# (shell, command) that still asks in a cloud session on its task branch: other checkouts, other branches, the
# repository itself, the checkout's folder, and the protected paths.
CLOUD_BEYOND = [
    (B, "git -C D:/prime-game/.claude/worktrees/47 reset --hard"),
    (B, "cd .claude/worktrees/47 && git rebase origin/main"),
    (B, "git --git-dir=.git/worktrees/47 --work-tree=.claude/worktrees/47 clean -fdx"),
    (B, "git checkout -- .claude/worktrees/47/core"),
    (B, "rm -rf .claude/worktrees/47"),
    (B, "rm -rf .claude/worktrees"),
    (B, "rm -rf .claude"),
    (B, "rm -rf .git"),
    (B, "rm -rf .g*"),
    (B, "rm -rf .git/refs"),
    (B, "rm -rf D:/prime-game"),
    (B, "cd .. && rm -rf prime-game"),
    (B, "rm -rf addons/gdUnit4"),
    (B, "git checkout -- addons"),
    (B, "git branch -D main"),
    (B, "git branch -f release/m6 HEAD"),
    (B, "git rebase origin/main release/m6"),
    (B, "git switch main && git reset --hard origin/main"),
    (B, "git checkout -f main"),
    (B, "git branch -D tooling/365-other"),
    (B, "git worktree remove D:/prime-game"),
    (B, "git -c core.hooksPath=/dev/null push"),
    # Found by the review of #381: ignored files (`-x`, `-X`) include .claude/settings.local.json and the other
    # worktrees, which a second -f removes as nested repositories; a magic pathspec can name them.
    (B, "git clean -fdx"),
    (B, "git clean -fdX"),
    (B, "git clean -ffd"),
    (B, "git clean -f --force -d"),
    (B, "git clean -fd ':(top).claude/worktrees'"),
    # Bash globs Python's fnmatch reads otherwise (`[^...]`, `[[:class:]]`): any glob in the first parts may match.
    (B, "rm -rf .[^.]*"),
    (B, "rm -rf .gi[[:lower:]]"),
    (B, "rm -rf .claude/worktree[[:alpha:]]"),
    (B, "rm -rf *"),  # bash's `*` skips dotfiles, but the guard does not judge by the shell's options
]


class CloudCheckoutTest(unittest.TestCase):
    def test_a_cloud_session_on_its_task_branch_owns_the_main_checkout(self) -> None:
        for shell, command in CLOUD_WORK:
            for cwd in (ROOT, ROOT + "\\tools"):
                with self.subTest(shell=shell, command=command, cwd=cwd):
                    self.assertEqual(in_cloud(shell, command, cwd), [])

    def test_beyond_its_checkout_and_branch_a_cloud_session_still_asks(self) -> None:
        for shell, command in CLOUD_BEYOND:
            with self.subTest(shell=shell, command=command):
                self.assertTrue(in_cloud(shell, command), "expected the guard to ask")

    def test_a_cloud_session_on_main_or_a_release_branch_still_asks(self) -> None:
        for branch in ("main", "release/m6", "feature-x", "Tooling/381-guard", None):
            for command in ("git reset -q --soft HEAD~2", "git rebase origin/main", "git clean -fd", "rm -rf core"):
                with self.subTest(branch=branch, command=command):
                    self.assertTrue(in_cloud(B, command, repo=CloudRepo(branch)), "expected the guard to ask")

    def test_a_desktop_session_in_the_main_checkout_still_asks(self) -> None:
        for shell, command in CLOUD_WORK:
            with self.subTest(shell=shell, command=command):
                self.assertTrue(in_cloud(shell, command, cloud=False), "expected the guard to ask")

    def test_any_task_branch_checked_out_in_the_cloud_checkout_is_the_task(self) -> None:
        # Accepted in #381: a cloud checkout has no worktree folder to pin the task number, so the branch checked out
        # decides (a parent's `core/365-x` after a switch too); its own number's other branches stay free.
        repo = CloudRepo("core/365-parent")
        self.assertEqual(in_cloud(B, "git reset --hard origin/core/365-parent", repo=repo), [])
        self.assertEqual(in_cloud(B, "git branch -D core/365-parent-backup", repo=repo), [])
        self.assertTrue(in_cloud(B, f"git branch -D {CLOUD_TASK}", repo=repo))

    def test_a_worktree_in_the_cloud_keeps_its_own_rules(self) -> None:
        own = ROOT + "\\.claude\\worktrees\\51"
        self.assertEqual(in_cloud(B, "git reset --hard HEAD~1", cwd=own), [])
        self.assertTrue(in_cloud(B, "git -C D:/prime-game reset --hard", cwd=own))

    def test_the_task_branch_form_matches_publish(self) -> None:
        from runner import publish

        self.assertEqual(guard.TASK_BRANCH_RE.pattern, publish.TASK_BRANCH_RE.pattern)


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
        self.assertEqual(guard.check("rm -rf /tmp/x", B, worktree, worktree), [])
        self.assertEqual(guard.check("rm -r tests/scratch/x", B, worktree, worktree), [])
        # Issue #51: inside its own worktree the agent deletes freely (until then these asked). The flipped asserts
        # await the engineer's approval in the PR.
        self.assertEqual(guard.check("rm -rf core", B, worktree, worktree), [])
        self.assertEqual(guard.check("rm -r tests/integration/tmp", B, worktree, worktree), [])
        top = '"$(git rev-parse --show-toplevel)'
        self.assertEqual(guard.check(f'rm -rf {top}/tests/scratch/x"', B, worktree, worktree), [])
        self.assertEqual(guard.check(f'rm -rf {top}/core"', B, worktree, worktree), [])
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


class GhRepo(guard.NoRepo):
    def github_repo(self) -> str | None:
        return "xperiaroco2/prime-game"


def gh(shell: str, command: str, repo: guard.NoRepo | None = None) -> list[str]:
    """The repositories the guard asks about for one gh command."""
    findings = guard.check(command, shell, ROOT, ROOT, "", repo or GhRepo())
    return [f.verb for f in findings if f.area == guard.GH]


class GhOtherRepositoryTest(unittest.TestCase):
    """gh reads of other repositories pass; anything else aimed at another repository asks (issue #68). The lists in
    test_permissions check the same commands through the settings rules as well."""

    def test_reads_pass_whatever_repository_they_name(self) -> None:
        for command in (
            "gh issue view 1 -R godotengine/godot",
            "gh issue -R o/r view 1",
            "gh pr --repo o/r list",
            "gh issue ls --repo=o/r",
            "gh pr checks 5 -Ro/r",
            "gh release verify v1 -R o/r",
            "gh run view 12 -R o/r --log",
            "gh search issues x --repo o/r",
            "gh api repos/o/r/pulls/5/files --paginate",
            "gh api -X HEAD repos/o/r",
            "gh api -X=GET repos/o/r/issues -fstate=open",
            "gh repo clone o/r /tmp/r",
        ):
            with self.subTest(command=command):
                self.assertEqual(gh(B, command), [])
                self.assertEqual(gh(P, command), [])

    def test_the_repository_comes_from_every_place_gh_takes_it(self) -> None:
        cases = {
            "gh issue comment 1 -R o/r -b x": ["o/r"],
            "gh issue comment 1 --repo=o/r -b x": ["o/r"],
            "gh issue comment 1 -Ro/r -b x": ["o/r"],
            "gh issue -R o/r comment 1 -b x": ["o/r"],
            "gh issue --repo=o/r close 1": ["o/r"],
            "gh issue comment https://github.com/o/r/issues/1 -b x": ["https://github.com/o/r/issues/1"],
            "gh issue transfer 1 o/r": ["o/r"],
            "gh repo sync o/fork": ["o/fork"],
            "gh api repos/o/r/issues -f title=x": ["o/r"],
            "gh api /repos/o/r/issues -F title=x": ["o/r"],
            "gh api -X=POST repos/o/r/forks": ["o/r"],
            "gh api repos/o/r/issues/1/comments -fbody=hi": ["o/r"],
            "gh api https://api.github.com/repos/o/r/issues --input b.json": [
                "https://api.github.com/repos/o/r/issues"
            ],
            "GH_REPO=o/r gh issue close 1": ["o/r"],
            "env GH_REPO=o/r gh issue close 1": ["o/r"],
            "sudo GH_REPO=o/r gh issue close 1": ["o/r"],
            "export GH_REPO=o/r && gh issue close 1": ["o/r"],
            "gh issue comment 1 -R ghe.example.com/xperiaroco2/prime-game -b x": [
                "ghe.example.com/xperiaroco2/prime-game"
            ],
        }
        for command, expected in cases.items():
            with self.subTest(command=command):
                self.assertEqual(gh(B, command), expected)

    def test_text_is_no_repository(self) -> None:
        for command in (
            'gh issue comment 1 --body "see https://github.com/o/r/issues/2 and -R o/r"',
            "gh issue comment 1 -b https://github.com/o/r/issues/2",
            "gh api repos/{owner}/{repo}/issues/1/comments -f body=https://github.com/o/r",
            "gh pr create --title x --head core/79-shared-tasks",
            "gh issue create --title o/r --label area/x",
        ):
            with self.subTest(command=command):
                self.assertEqual(gh(B, command), [])

    def test_an_option_is_never_the_value_of_a_text_option(self) -> None:
        self.assertEqual(gh(B, "gh pr create -d -R o/r --title t"), ["o/r"])

    def test_this_repository_in_any_spelling_passes(self) -> None:
        for spec in ("xperiaroco2/prime-game", "XperiaRoco2/Prime-Game", "github.com/xperiaroco2/prime-game",
                     "https://github.com/xperiaroco2/prime-game.git"):  # fmt: skip
            with self.subTest(spec=spec):
                self.assertEqual(gh(B, f"gh issue comment 1 -R {spec} -b x"), [])

    def test_without_the_origin_remote_every_named_repository_is_another(self) -> None:
        own = "gh issue comment 1 -R xperiaroco2/prime-game -b x"
        self.assertEqual(gh(B, own, guard.NoRepo()), ["xperiaroco2/prime-game"])
        self.assertEqual(gh(B, "gh issue comment 1 -b x", guard.NoRepo()), [])

    def test_a_computed_repository_counts_as_another(self) -> None:
        self.assertEqual(gh(P, "$env:GH_REPO = (Get-Content repo.txt); gh issue close 1"), ["(computed)"])
        self.assertEqual(gh(B, 'gh issue close 1 -R "$R"'), ["$R"])

    def test_nested_shells_and_substitutions_are_judged(self) -> None:
        self.assertEqual(gh(B, "bash -c 'gh issue close 1 -R o/r'"), ["o/r"])
        self.assertEqual(gh(B, "echo $(gh api -X POST repos/o/r/forks)"), ["o/r"])

    def test_reason_says_reads_pass(self) -> None:
        text = guard.reason(guard.check("gh issue comment 1 -R o/r -b x", B, ROOT, ROOT, "", GhRepo()))
        self.assertIn("another repository", text)
        self.assertIn("o/r", text)
        self.assertIn("Reads of other repositories pass", text)


if __name__ == "__main__":
    unittest.main()
