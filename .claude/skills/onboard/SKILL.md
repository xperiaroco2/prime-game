---
name: onboard
description: Set up a human's machine and Claude Code for prime-game - doctor, user settings after approval, git hooks and Git LFS, the save-first and guard-prompt rules, the human-only checklist and a one-page summary. Use when a human says "налаштуй мене", "set me up" or "onboard me", or opens the project on a new machine.
allowed-tools:
  - Bash(tools/run.sh *)
  - PowerShell(tools\run.cmd *)
  - Bash(git lfs install --skip-repo)
  - PowerShell(git lfs install --skip-repo)
  - Bash(gh auth status --active --json *)
  - PowerShell(gh auth status --active --json *)
---

# Onboard a human (docs/AGENT_WORKFLOW.md §2 and §12)

Talk in the human's language, in plain words, one step at a time. Nothing is written to their machine without their
approval of the exact content. Commands use `tools\run.cmd`; in Git Bash use `tools/run.sh`.

1. **Explain** in three lines what will happen: a check of the machine, one settings file you will show before
   writing, a few rules for working with Godot and Claude, then a checklist of clicks only they can make.
2. **Doctor.** `tools\run.cmd doctor` (the full one; it also points git at the committed hooks, `core.hooksPath`).
   If it cannot start at all, Python is missing: that is the first checklist item (step 8). For each FAIL, say what
   it means; fix what the agent may fix (steps 3 to 5), and put the rest in the checklist.
3. **Who is this?** `gh auth status --active --json hosts` gives the GitHub login. The repo owner is the engineer;
   anyone else is the designer. Ask if unsure. The designer's paths and rules are in root `CLAUDE.md` (Ownership).
4. **User settings** `~/.claude/settings.json` ([ADR](../../../docs/decisions/2026-09-28-machine-env-in-user-settings.md)):
   - Read the current file, if any, and keep every key it has.
   - `env`: `GODOT_BIN` (the Godot 4.7.2 `*_console.exe`), `GODOT_GUI_BIN` (the Godot 4.7.2 window exe), `PYTHON_BIN`
     (a real Python 3.11+, never the Microsoft Store stub; `py -3 -c "import sys; print(sys.executable)"`),
     `GDTOOLKIT_DIR` (the folder holding `gdformat.exe`). Ask where they unpacked Godot; confirm each exe with
     `--version`.
   - `"language"`: the language they want Claude to answer in (ask). `"permissions": {"defaultMode": "acceptEdits"}`.
   - Show the whole resulting file and ask for approval. Write it only after a clear yes (Claude Code asks again for
     settings files: that prompt is expected). `env` takes effect in the next session; `tools\run.cmd` reads it
     in their own PowerShell too, so they set no Windows environment variables.
5. **Tools.** gdtoolkit missing or wrong: with their OK, `"<PYTHON_BIN>" -m pip install gdtoolkit==<version>`, the
   version from `tools\run.cmd pins --get gdtoolkit`. Node.js missing or another major (`verify`'s `signal` step
   needs it, #368): with their OK, `winget install OpenJS.NodeJS.LTS --version <version>`, the version from
   `tools\run.cmd pins --get node`, then a new terminal. Git LFS: `git lfs install --skip-repo` only. With
   `core.hooksPath` set, a plain `git lfs install` or `git lfs update` stops with "Hook already exists" (exit 2) and
   changes nothing; never run `git lfs update --force`, which overwrites the project's pre-push hook.
6. **Doctor again.** `tools\run.cmd doctor`. What is still red goes into the checklist.
7. **Two rules to show and explain,** with the reason for each:
   - **Godot: save first, reload from disk.** Before asking the agent for anything, Scene → Save All Scenes
     (Ctrl+Shift+Alt+S, «Зберегти всі сцени»). When Godot says files changed on disk («Файли були змінені за межами
     Godot»), choose «Джерело отримання» (Reload from disk), never «Ігнорувати зовнішні зміни»: the editor would later
     save its old copy over the agent's work. No hand edits while the agent works.
   - **Permission prompts from the guard** (a shell command that writes to `addons/` or `.claude/settings*.json`,
     discards work beyond the agent's own worktree and task branch, or may write to another GitHub repository):
     answer with a one-time Yes or No, never "don't ask again", which silences the guard for the rest of the session.
8. **The human-only checklist.** Show only what is not done yet, as clicks:
   - Git for Windows (required: Claude Code hooks run in Git Bash; without it they do nothing);
   - Python 3.11+ from python.org (tick "Add to PATH"); Godot 4.7.2 (both exes);
   - GitHub: accept the repo invitation and the project invitation (project "prime-game"); `gh auth login`, then
     `gh auth refresh -s project`; gh 2.97 or newer (`winget upgrade --id GitHub.cli`);
   - Claude desktop app 2.1.281 or newer; trust the project folder when asked; check the Claude plan; usage credits
     off or a spend cap (the only hard stop on money); a `claude` on PATH updated or removed;
   - designer only: tell the engineer your GitHub handle for `.github/CODEOWNERS`.
9. **One-page summary** for their sign-off:
   - what was set up (settings keys, hooks, LFS) and what is left on the checklist;
   - how to talk to the agent: "start task 42", "нова механіка: …" (designer), "заверши задачу", "запам'ятай",
     "стоп", "поясни"; dictation is fine, the agent reads file names back;
   - the rules that bind them: their paths (Ownership in root `CLAUDE.md`), `engine-request` issues for missing engine
     parts (designer), the engineer's manager merges into `main` through a gate after green CI and humans merge its
     exceptions and the designer's PRs (a stage's manager merges task PRs into `release/m<k>`), the other owner approves
     a cross-area PR (or, in the designer's area, the engineer relays the designer's agreement and the designer may have
     it reverted, `docs/AGENT_WORKFLOW.md` §9), the designer reviews through `shot` screenshots and playtests,
     save-first, one-time guard answers; the designer never uses worktrees and works at medium effort;
   - they may reopen any decision that binds them: say so, and the agent opens an issue for both humans.
