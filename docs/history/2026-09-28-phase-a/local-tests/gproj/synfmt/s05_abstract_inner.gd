extends RefCounted

@abstract class Base:
	@abstract func run() -> int


class Impl:
	extends Base

	func run() -> int:
		return 1
