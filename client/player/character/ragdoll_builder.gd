extends RefCounted
## The art's reference ragdoll builder (#522, ARCHITECTURE §4.7.53), copied from prime-game-art
## 45f73ac `godot/ragdoll/builder.gd` (art #115, its docs/contract.md "Ragdoll"; the art says the
## game may copy it as it is). Changed here only for the project's typed-GDScript warnings (every
## JSON value cast before use, `bone_name` set and read as the dynamic property it is) and a freed
## simulator checked after the start's wait; the logic, the names and the HINGE_SIGN are the
## art's. It turns a character's ragdoll data (the `<id>.ragdoll.json` beside its GLB,
## CharacterSet.ragdoll) into PhysicalBone3D nodes under a PhysicalBoneSimulator3D on the
## character's Skeleton3D, and starts the fall. Loaded with preload(), not a class_name, as the
## art's file is.
##
##   var sim := Builder.build(skeleton, data)        # once, at spawn; nothing simulates yet
##   Builder.start(sim, data, avatar_velocity)       # the knockdown: from the current pose
##   Builder.stop(sim)                               # the revive: the animation poses them again
##
## The joints are Joint3D nodes made at the start, not the PhysicalBone3D's own joint: the rig's
## feet hang from Root (an IK-style rig), so a PhysicalBone3D joint, which links a bone to its
## nearest simulated skeleton ancestor, would leave them free; the data names each body's physical
## parent instead.

## The joints' frames from the data's (positive flexion about the axis); measured on Jolt Physics
## 4.7.2 by the art.
const HINGE_SIGN: float = -1.0


static func _layer_bits(layers: Array) -> int:
	var bits: int = 0
	for layer: Variant in layers:
		bits |= 1 << (int(layer as float) - 1)
	return bits


static func _v3(value: Variant) -> Vector3:
	var a := value as Array
	return Vector3(a[0] as float, a[1] as float, a[2] as float)


static func _quat(value: Variant) -> Quaternion:
	var a := value as Array
	return Quaternion(a[0] as float, a[1] as float, a[2] as float, a[3] as float).normalized()


static func _num(value: Variant, fallback: float = 0.0) -> float:
	return float(value as float) if value is float or value is int else fallback


## The body's transform in its bone's frame: the shape's offset and rotation.
static func body_offset(bone: Dictionary) -> Transform3D:
	return Transform3D(Basis(_quat(bone.get("rotation", [0, 0, 0, 1]))), _v3(bone["offset"]))


static func shape_of(bone: Dictionary) -> Shape3D:
	if bone["shape"] == "box":
		var box: BoxShape3D = BoxShape3D.new()
		box.size = _v3(bone["size"])
		return box
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = _num(bone["radius"])
	capsule.height = _num(bone["height"])
	return capsule


## Builds the simulator and one PhysicalBone3D per listed bone (named after the bone); returns the
## simulator, a child of skeleton. Bones the data does not list follow their parent as the skeleton
## poses them.
static func build(skeleton: Skeleton3D, data: Dictionary) -> PhysicalBoneSimulator3D:
	var sim: PhysicalBoneSimulator3D = PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	skeleton.add_child(sim)
	var collision := data["collision"] as Dictionary
	var layer: int = _layer_bits([collision["layer"]])
	var mask: int = _layer_bits(collision["mask"] as Array)
	var material: Dictionary = data.get("material", {}) as Dictionary
	var total: float = _num(data["total_mass_kg"])
	for entry: Variant in data["bones"] as Array:
		var bone := entry as Dictionary
		var bone_name := str(bone["bone"])
		if skeleton.find_bone(bone_name) < 0:
			push_error("ragdoll: no bone %s in %s" % [bone_name, skeleton.name])
			continue
		var pb: PhysicalBone3D = PhysicalBone3D.new()
		pb.name = bone_name.validate_node_name()  # "UpperArm.L" becomes "UpperArm_L"
		pb.set(&"bone_name", bone_name)  # a dynamic property: not in the typed API
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		pb.body_offset = body_offset(bone)
		pb.mass = maxf(0.05, _num(bone["mass_share"]) * total)
		pb.friction = _num(material.get("friction"), 0.8)
		pb.bounce = _num(material.get("bounce"), 0.0)
		pb.linear_damp = _num(material.get("linear_damp"), 0.1)
		pb.angular_damp = _num(material.get("angular_damp"), 3.0)
		pb.collision_layer = layer
		pb.collision_mask = mask
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = shape_of(bone)
		pb.add_child(shape)
		sim.add_child(pb)
	return sim


## The joint's frame in world space from the child's current body: at the anchor, for a cone its
## X (Godot's twist axis) along the bone, for a hinge its Z (Godot's hinge axis) along the data's
## axis.
static func joint_transform(pb: PhysicalBone3D, bone: Dictionary) -> Transform3D:
	var bone_global: Transform3D = pb.global_transform * pb.body_offset.affine_inverse()
	var joint: Dictionary = bone["joint"] as Dictionary
	var origin: Vector3 = bone_global * _v3(joint.get("anchor", [0, 0, 0]))
	var along: Vector3 = (bone_global.basis * Vector3.UP).normalized()
	var basis: Basis
	if joint["type"] == "hinge":
		var axis: Vector3 = (bone_global.basis * _v3(joint["axis"])).normalized()
		var x: Vector3 = (along - axis * along.dot(axis)).normalized()
		basis = Basis(x, axis.cross(x), axis)
	else:
		var side: Vector3 = (bone_global.basis * Vector3.RIGHT).normalized()
		var y: Vector3 = (side - along * side.dot(along)).normalized()
		basis = Basis(along, y, along.cross(y))
	return Transform3D(basis, origin)


## The simulator's bodies by bone name.
static func bodies(sim: PhysicalBoneSimulator3D) -> Dictionary:
	var out: Dictionary = {}
	for node: Node in sim.get_children():
		if node is PhysicalBone3D:
			out[str(node.get(&"bone_name"))] = node
	return out


## Starts the simulation from the skeleton's current pose, links every body to its physical parent
## and gives them velocity (the avatar's). Call it on the frame of the knockdown. The joints are
## made on the next physics frame, once the physics server holds the bodies at the start pose (made
## at once, their frames came from node transforms the server had not taken yet, and the knees
## popped by 25 degrees).
static func start(
	sim: PhysicalBoneSimulator3D, data: Dictionary, velocity: Vector3 = Vector3.ZERO
) -> void:
	sim.physical_bones_start_simulation()
	var by_bone: Dictionary = bodies(sim)
	for entry: Variant in data["bones"] as Array:
		var pb: PhysicalBone3D = by_bone.get(str((entry as Dictionary)["bone"])) as PhysicalBone3D
		if pb == null:
			continue
		pb.linear_velocity = velocity
	await sim.get_tree().physics_frame
	if not is_instance_valid(sim) or not sim.is_simulating_physics():
		return
	for entry: Variant in data["bones"] as Array:
		var bone := entry as Dictionary
		if bone.get("parent") == null:
			continue
		var child: PhysicalBone3D = by_bone.get(str(bone["bone"])) as PhysicalBone3D
		var parent: PhysicalBone3D = by_bone.get(str(bone["parent"])) as PhysicalBone3D
		if child == null or parent == null:
			continue
		var j: Dictionary = bone["joint"] as Dictionary
		var joint: Joint3D
		if j["type"] == "hinge":
			var hinge: HingeJoint3D = HingeJoint3D.new()
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			var a: float = deg_to_rad(_num(j["min_deg"])) * HINGE_SIGN
			var b: float = deg_to_rad(_num(j["max_deg"])) * HINGE_SIGN
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, minf(a, b))
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, maxf(a, b))
			joint = hinge
		elif j["type"] == "cone":
			var cone: ConeTwistJoint3D = ConeTwistJoint3D.new()
			cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(_num(j["swing_deg"])))
			cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(_num(j["twist_deg"])))
			joint = cone
		else:
			joint = PinJoint3D.new()
		joint.name = ("Joint_" + str(bone["bone"])).validate_node_name()
		sim.add_child(joint)
		joint.global_transform = joint_transform(child, bone)
		joint.exclude_nodes_from_collision = true
		joint.node_a = joint.get_path_to(parent)
		joint.node_b = joint.get_path_to(child)


## Ends the simulation (a revive): removes the joints; the animation poses the bones again.
static func stop(sim: PhysicalBoneSimulator3D) -> void:
	for node: Node in sim.get_children():
		if node is Joint3D:
			node.queue_free()
	sim.physical_bones_stop_simulation()
