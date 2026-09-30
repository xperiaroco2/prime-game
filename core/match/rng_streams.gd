class_name RngStreams
extends RefCounted
## One RandomNumberGenerator per purpose (`roles`, `spawns`, ...), seeded by a fixed mixing
## function of the match seed and the purpose's name (ARCHITECTURE §3.3), so a new purpose never
## shifts the draws of the existing ones.
##
## - Match k's seed is the k-th output of SplitMix64 started at the session seed.
## - A purpose's seed is SplitMix64 of (match seed XOR FNV-1a-64 of the purpose's UTF-8 name).
##   Not String.hash(): its algorithm is no documented contract.
## GDScript ints are signed 64-bit and wrap on overflow; `>>` is arithmetic, so every shift is
## masked to make it logical. The docs promise neither the wrap nor the arithmetic shift (and a
## negative constant operand of `>>` is a parse error): it is engine behaviour verified on 4.7.2
## at runtime and pinned by tests/unit/match/rng_streams_test.gd, which must pass after every
## Godot pin bump. Never call mix64 or _shift_right with constant operands. The unit test pins
## outputs computed by an independent implementation. Seeds and RNG state never leave the host
## (§5).

const _GAMMA := -7046029254386353131  # 0x9E3779B97F4A7C15
const _MIX_1 := -4658895280553007687  # 0xBF58476D1CE4E5B9
const _MIX_2 := -7723592293110705685  # 0x94D049BB133111EB
const _FNV_OFFSET := -3750763034362895579  # 0xCBF29CE484222325
const _FNV_PRIME := 1099511628211  # 0x100000001B3

var session_seed: int
## The index of the current match in this session: 0 for the first.
var match_index := 0
var _streams: Dictionary[StringName, RandomNumberGenerator] = {}


func _init(seed_of_session: int) -> void:
	session_seed = seed_of_session


## Moves to the next match of the session: every purpose starts again from the new match seed.
func next_match() -> void:
	match_index += 1
	_streams.clear()


func match_seed() -> int:
	return match_seed_of(session_seed, match_index)


## The generator for one purpose of the current match, created on first use.
func stream(purpose: StringName) -> RandomNumberGenerator:
	if not _streams.has(purpose):
		var rng := RandomNumberGenerator.new()
		rng.seed = purpose_seed_of(match_seed(), purpose)
		_streams[purpose] = rng
	return _streams[purpose]


## SplitMix64's output mix (the finaliser, without the increment).
static func mix64(value: int) -> int:
	var z := value
	z = (z ^ _shift_right(z, 30)) * _MIX_1
	z = (z ^ _shift_right(z, 27)) * _MIX_2
	return z ^ _shift_right(z, 31)


## One SplitMix64 step from state `value`: the output after adding the golden gamma.
static func splitmix64(value: int) -> int:
	return mix64(value + _GAMMA)


## FNV-1a, 64-bit, over the UTF-8 bytes of `text`.
static func fnv1a64(text: String) -> int:
	var h := _FNV_OFFSET
	for byte: int in text.to_utf8_buffer():
		h = (h ^ byte) * _FNV_PRIME
	return h


## Match k's seed: the (k+1)-th output of SplitMix64 started at the session seed.
static func match_seed_of(seed_of_session: int, index: int) -> int:
	return mix64(seed_of_session + (index + 1) * _GAMMA)


static func purpose_seed_of(seed_of_match: int, purpose: StringName) -> int:
	return splitmix64(seed_of_match ^ fnv1a64(String(purpose)))


## A Fisher-Yates permutation of 0..count-1 drawn from `rng` (never Array.shuffle(), which uses
## the global generator).
static func shuffled_indices(count: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var order := PackedInt32Array()
	order.resize(count)
	for i in count:
		order[i] = i
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap
	return order


## A logical right shift: GDScript's `>>` on int keeps the sign.
static func _shift_right(value: int, bits: int) -> int:
	return (value >> bits) & ((1 << (64 - bits)) - 1)
