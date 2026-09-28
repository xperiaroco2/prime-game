---
paths:
  - "**/*.gd"
---

# GDScript (Godot 4.7.2)

## Typing: untyped code fails `check`
- `project.godot` sets `untyped_declaration`, `unsafe_method_access`, `unsafe_property_access` and
  `unsafe_call_argument` to Error. Other warnings are reported but do not fail.
- Type every variable, constant, parameter and return: `var speed: float = 4.0`, `func kill(target: int) -> void:`.
  `:=` is fine when the type is obvious (`inferred_declaration` is off).
- Typed containers: `Array[int]`, `Dictionary[String, int]`. Typed signal arguments: `signal voted(voter: int)`.
- A `Variant` (from `get_node`, a `Dictionary` or a `Callable`) must be cast before a method or property access:
  `var label: Label = get_node("Hud/Label") as Label`.
- `class_name` for classes other code refers to; none for one-off scripts.

## Godot 3 idioms are bugs
| Godot 3 | Godot 4.7 |
|---|---|
| `onready var`, `export var`, `tool` | `@onready var`, `@export var`, `@tool` |
| `yield(obj, "signal")` | `await obj.signal` |
| `connect("sig", obj, "method")` | `sig.connect(method)` |
| `setget` | `var x: int: set = _set_x, get = _get_x` or inline `set(value):` |
| `instance()`, `.empty()` | `instantiate()`, `.is_empty()` |
| `OS.get_ticks_msec()`, `rand_range()` | `Time.get_ticks_msec()`, `randf_range()` |
| `KinematicBody`, `PoolStringArray` | `CharacterBody3D`, `PackedStringArray` |

Do not trust memory for any other API: grep `tools/out/godot-api/4.7.2/extension_api.json` (it has the docs) or
read `docs.godotengine.org/en/4.7/`. Agent `godot-api-checker` reviews `.gd` changes.

## Style (gdformat and gdlint check most of it)
- gdformat: tabs, lines up to 100 characters. Fix with `tools\run.cmd lint --fix`.
- gdlint names: `snake_case` functions, variables and signals; `PascalCase` classes; `CONSTANT_CASE` constants.
  File names are `snake_case.gd`.
- Order inside a class: `@tool`, `class_name`, `extends`, `##` docs, signals, enums, constants, static vars,
  `@export`s, public vars, private vars (`_name`), `@onready` vars, then methods.
- Doc comments use `##`. Comment the why, not the what.

## Verify after editing
- `tools\run.cmd lint <file>` and `tools\run.cmd check res://<path>`, then `test` for the code it touches.
- Autoloads must have no side effects when loaded by `check` (no network, no files, no scene changes in `_init`).
- Never pass a bare `-d` to Godot: it hangs on a script error. The runner uses `-d --ignore-error-breaks`.
