class_name PhysicsLayers
extends RefCounted
## The 3D physics layers as bit values: one place, named the same in `project.godot`
## (`[layer_names]`). Level geometry keeps Godot's default layer 1, so a level piece built in the
## editor is `WORLD` without anyone setting it.

## Level geometry: floors, walls, steps, props.
const WORLD := 1 << 0
## Living players' capsules: the local player and the kinematic capsules of the others. No body
## collides with this layer; a living player's push search looks for the others on it.
const LIVING := 1 << 1
## Downed players: the controllers and the ragdolls (RagdollView, ARCHITECTURE §4.7.9); a dead
## body's ragdoll is on no layer. Nothing collides with them and no push search looks at them; they
## collide with the level only. The crosshair's search for a downed player to raise reads this
## layer.
const DOWNED := 1 << 2
## Movers (the car repair ADR's RE8 (a)): the car, an AnimatableBody3D only the clients' worlds
## hold. A living player's controller walks out of one it is placed inside (KD15 (b2)); R7 puts the
## layer on the living's collision mask.
const MOVERS := 1 << 3
