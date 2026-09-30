class_name PhysicsLayers
extends RefCounted
## The 3D physics layers as bit values: one place, named the same in `project.godot`
## (`[layer_names]`). Level geometry keeps Godot's default layer 1, so a level piece built in the
## editor is `WORLD` without anyone setting it.

## Level geometry: floors, walls, steps, props.
const WORLD := 1 << 0
## Living players' capsules: the local player and the kinematic capsules of the others.
const LIVING := 1 << 1
## Ghosts' capsules. Nothing living collides with them; they collide with the level only.
const GHOSTS := 1 << 2
