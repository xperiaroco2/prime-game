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
human does **Save All**. If Godot asks about files changed on disk, always choose **Reload from disk**. The agent
reminds the human; nothing blocks.

## Alternatives
- The runner and guard refuse while a GUI editor has the checkout open (close-first): recommended first, then dropped
  once the engineer explained that the humans never edit while the agent works.
- The designer's agent works in a worktree: confusing for a non-coder, and the editor does not see the changes.

## Consequences
No editor-process detection in the guard or runner. Running headless Godot next to an open editor is still tested in
M0.
