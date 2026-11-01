extends RefCounted
## Whether the ship station packages' art is here (#1550), for the suites of their looks. CI checks
## out no Git LFS content and imports a stand-in for each GLB (the LFS ADR's amendment, #515), which
## has none of the nodes the looks drive (shells, cores, lamps, claws, carrier, hologram): a test of
## the art's nodes then prints that it skips and checks the pointer, as estate_ship_test does.

const Check := preload("res://tools/assets/asset_check.gd")
const GLBS: Array[String] = [
	"res://assets/environment/start_console/start_console.glb",
	"res://assets/environment/crystal_socket/crystal_socket.glb",
	"res://assets/environment/breaker_board/breaker_board.glb",
	"res://assets/environment/crystal_charger/crystal_charger.glb",
]


## True (after printing the skip and checking the pointer in `suite`) when a package's GLB is a
## Git LFS pointer here.
static func missing(suite: GdUnitTestSuite) -> bool:
	for glb: String in GLBS:
		if Check.is_lfs_pointer(glb):
			var why := "the station looks on the art are unchecked"
			print("skip: %s is a Git LFS pointer (no LFS content here): %s" % [glb, why])
			suite.assert_bool(FileAccess.get_file_as_string(glb).contains("oid sha256:")).is_true()
			return true
	return false
