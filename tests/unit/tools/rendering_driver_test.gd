extends GdUnitTestSuite
## Windows renders with Vulkan (docs/decisions/2026-10-01-vulkan-on-windows.md, #124).
## `project.godot` has no line for it because Vulkan is the engine default, so this test
## fails if a pinned Godot ever changes that default, or if a `d3d12` override comes back
## (#21: a windowed D3D12 process can freeze 5 s when another one on the same PC starts or
## is killed). The setting reads the same on every platform, so it runs on Linux CI too.


func test_windows_driver_is_vulkan() -> void:
	var key := "rendering/rendering_device/driver.windows"
	assert_str(str(ProjectSettings.get_setting(key))).is_equal("vulkan")
