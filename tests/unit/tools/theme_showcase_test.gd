extends GdUnitTestSuite
## The Godot showcase (#289, tools/theme/showcase.gd): its pages together show every live pack
## variation (the abstract ToyButton aside) and no deprecated one, built in the default and the
## large-text theme; the interactive scene's switches work. How it looks is the shots' job.

const Builder := preload("res://tools/theme/theme_builder.gd")
const Showcase := preload("res://tools/theme/showcase.gd")
const PAGES: Array[String] = [
	"res://tools/theme/showcase.tscn",
	"res://tools/theme/showcase_1.tscn",
	"res://tools/theme/showcase_2.tscn",
	"res://tools/theme/showcase_3.tscn",
]


func after_test() -> void:
	UiPrefs.reset()


func test_the_pages_show_every_live_variation() -> void:
	assert_int(PAGES.size()).is_equal(Showcase.PAGES.size())
	var pack := Builder.load_pack(Builder.load_mapping())
	var shown: Dictionary[String, bool] = {}
	for large: bool in [false, true]:
		for path in PAGES:
			var page := (load(path) as PackedScene).instantiate() as Showcase
			page.large_text = large
			add_child(page)
			await get_tree().process_frame
			assert_object(page.theme).is_same(GameUi.THEME_LARGE if large else GameUi.THEME)
			shown.merge(Showcase.variations_under(page))
			page.free()
	var missing := PackedStringArray()
	for name in Builder.generated_names(pack):
		var abstract: Variant = ((pack["variations"] as Dictionary)[name] as Dictionary).get(
			"abstract"
		)
		if abstract != true and not shown.has(name):
			missing.append(name)
	assert_array(missing).is_empty()
	for name in Builder.deprecated_names(pack):
		assert_bool(shown.has(name)).override_failure_message(name).is_false()


func test_the_interactive_scene_switches() -> void:
	var scene := load("res://tools/theme/showcase_interactive.tscn") as PackedScene
	var page := scene.instantiate() as Showcase
	add_child(page)
	await get_tree().process_frame
	assert_bool(page.interactive).is_true()
	page.show_health(0.22)
	assert_str(page._health_label.text).is_equal("hp 0.22: stop 04")
	assert_that(page._health_bar.fill.self_modulate).is_equal(
		GameUi.THEME.get_color(&"ramp_stop_04", ToyBar.HEALTH)
	)
	page._switch_large()
	await get_tree().process_frame
	assert_object(page.theme).is_same(GameUi.THEME_LARGE)
	page._show_page(2)
	await get_tree().process_frame
	assert_int(page.page).is_equal(2)
	page.free()
