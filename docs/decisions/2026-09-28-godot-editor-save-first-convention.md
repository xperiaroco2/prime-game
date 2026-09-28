# Godot editor: save first, reload from disk

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** the engineer (Phase A decision session)

## Context
The Godot editor never merges external changes into an open scene. "Reload from disk" discards unsaved edits;
"Ignore" re-saves the editor's copy over the agent's file. Each human's agent works in the same folder the human has
open in Godot.

## Decision
A convention, not enforcement. Nobody edits by hand while an agent works. Before asking the agent for anything, the
human does **Save All Scenes** (Scene menu, Ctrl+Shift+Alt+S; Ukrainian UI «Зберегти всі сцени»). If Godot asks about files changed on disk, always choose **Reload from disk**. In the
Ukrainian editor UI the dialog is titled «Файли були змінені за межами Godot» and that button reads
**«Джерело отримання»** (a poor translation); never click «Ігнорувати зовнішні зміни», which overwrites the agent's
file. The agent reminds the human; nothing blocks.

## Alternatives
- The runner and guard refuse while a GUI editor has the checkout open (close-first): recommended first, then dropped
  once the engineer explained that the humans never edit while the agent works.
- The designer's agent works in a worktree: confusing for a non-coder, and the editor does not see the changes.

## Consequences
No editor-process detection in the guard or runner.

**Verified 2026-09-28 (M0 stage 1)** with the GUI editor (4.7.2, Ukrainian UI, GdUnit4 plugin on) open on
`D:\prime-game`:
- Opening and closing the editor changed no tracked file.
- `tools\run.cmd verify` (headless import, check, GdUnit4) passed next to the open editor, in about the same time as
  without it (14.9 s vs 14.7 s). The editor stayed responsive and showed no dialog.
- A new script and a new scene written by the agent caused no dialog and no rewrite, even after the editor got focus.
- A scene **open in the editor** and changed on disk: nothing happens until the editor window gets focus. Until then
  the editor shows the stale scene, and a save would overwrite the agent's change. On focus it shows the dialog above;
  «Джерело отримання» reloaded the scene with the agent's node, and the file on disk stayed intact.

**Labels checked 2026-09-29** against the 4.7.2-stable sources: the shortcut in `editor/editor_node.cpp`
(`editor/save_all_scenes`) and the Ukrainian strings in `editor/translations/editor/uk.po`. Ctrl+Shift+S is
"Save Scene As…", not Save All.
