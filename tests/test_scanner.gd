## Scene Dependency Map — test suite. Run:
##   godot --headless --path . --script res://tests/test_scanner.gd
## Scans this repo's own demo project (the fixture in demo/) and checks
## every flag the tool promises. Exit 0 = all pass, 1 = a check failed.
extends SceneTree

const Scanner := preload("res://addons/scene_dependency_map/core/sdm_scanner.gd")
const Report := preload("res://addons/scene_dependency_map/core/sdm_report.gd")

var _failures: Array[String] = []
var _passes: int = 0


func _check(label: String, ok: bool, evidence: String = "") -> void:
	if ok:
		_passes += 1
		print("PASS  ", label)
	else:
		_failures.append(label)
		print("FAIL  ", label, "  ", evidence)


func _paths(items: Array) -> Array:
	var out: Array = []
	for i in items:
		out.append(i["path"] if i is Dictionary and i.has("path") else str(i))
	return out


func _init() -> void:
	var scanner = Scanner.new()
	var r: Dictionary = scanner.scan()

	_check("finds files", int(r["summary"]["files"]) >= 30, str(r["summary"]))
	_check("main scene detected", r["main_scene"] == "res://demo/main/main.tscn", str(r["main_scene"]))
	_check("3 autoloads detected", (r["autoloads"] as Dictionary).size() == 3, str(r["autoloads"]))
	_check("GameState autoload path", r["autoloads"].get("GameState") == "res://demo/autoloads/game_state.gd")

	var unused := _paths(r["unused"])
	_check("unused: old_enemy.tscn flagged", unused.has("res://demo/unused/old_enemy.tscn"), str(unused))
	_check("unused: old_enemy.gd flagged", unused.has("res://demo/unused/old_enemy.gd"))
	_check("unused: lost.svg asset flagged", unused.has("res://demo/unused/lost.svg"))
	_check("unused: dead cluster flagged (dead_a)", unused.has("res://demo/dead_cycle/dead_a.tscn"))
	_check("unused: dead cluster flagged (dead_b)", unused.has("res://demo/dead_cycle/dead_b.tscn"))
	_check("not unused: main.gd is used", not unused.has("res://demo/main/main.gd"))
	_check("not unused: autoload is an entry point", not unused.has("res://demo/autoloads/game_state.gd"))
	_check("not unused: plugin files never flagged (addons/ excluded)",
		not unused.has("res://addons/scene_dependency_map/core/sdm_scanner.gd"))

	var missing_tos: Array = []
	for m in r["missing"]:
		missing_tos.append(m["to"])
	_check("missing: ghost.svg flagged", missing_tos.has("res://demo/broken/ghost.svg"), str(missing_tos))
	_check("missing: missing_script.gd flagged", missing_tos.has("res://demo/broken/missing_script.gd"))

	var cycle_flat: Array = []
	for c in r["cycles"]:
		for p in c:
			cycle_flat.append(p)
	_check("cycle: live cycle_left/right detected",
		cycle_flat.has("res://demo/cycle/cycle_left.tscn") and cycle_flat.has("res://demo/cycle/cycle_right.tscn"), str(r["cycles"]))
	_check("cycle: dead cycle also detected",
		cycle_flat.has("res://demo/dead_cycle/dead_a.tscn") and cycle_flat.has("res://demo/dead_cycle/dead_b.tscn"))

	_check("deep chain found (>=8 steps from an entry)", not (r["deep_chains"] as Array).is_empty(), str(r["deep_chains"]))
	if not (r["deep_chains"] as Array).is_empty():
		_check("deepest chain runs through chain_10 and chain_end.gd",
			(r["deep_chains"][0]["chain"] as Array).has("res://demo/chain/chain_10.tscn")
			and (r["deep_chains"][0]["chain"] as Array).has("res://demo/chain/chain_end.gd")
			and int(r["deep_chains"][0]["length"]) >= 12,
			str(r["deep_chains"][0]))

	var hub_paths := _paths(r["hubs"])
	_check("hub: GameState is a high fan-in hub", hub_paths.has("res://demo/autoloads/game_state.gd"), str(r["hubs"]))

	var risk_text := ""
	for risk in r["autoload_risks"]:
		risk_text += str(risk["path"]) + "|" + str(risk["kind"]) + " "
	_check("autoload risk: hud.gd heavy coupling flagged",
		risk_text.contains("hud.gd") and risk_text.contains("heavy_autoload_coupling"), risk_text)
	_check("autoload risk: AudioBus loads a scene flagged",
		risk_text.contains("audio_bus.gd") and risk_text.contains("autoload_loads_scene"), risk_text)

	_check("hud reachable", bool(r["nodes"]["res://demo/ui/hud.tscn"]["reachable"]))
	_check("chain_end reachable through the chain", bool(r["nodes"]["res://demo/chain/chain_end.gd"]["reachable"]))
	_check("old_enemy NOT reachable", not bool(r["nodes"]["res://demo/unused/old_enemy.tscn"]["reachable"]))
	_check("player.svg asset reachable via player.tscn", bool(r["nodes"]["res://demo/shared/player.svg"]["reachable"]))
	_check("game_config.gd reached via its .tres (script_class/extends path)",
		bool(r["nodes"]["res://demo/shared/game_config.gd"]["reachable"]))

	# Report exporters produce real content.
	var md: String = Report.to_markdown(r)
	_check("markdown report names the unused file", md.contains("old_enemy.tscn"))
	_check("markdown report names the missing file", md.contains("ghost.svg"))
	var js: String = Report.to_json(r)
	_check("JSON parses back", JSON.parse_string(js) != null)
	_check("JSON carries summary", js.contains("\"unused\""))
	var html: String = Report.to_html(r)
	_check("HTML embeds the scan data", html.contains("old_enemy.tscn") and html.contains("__SDM_DATA__") == false)

	print("----")
	print("SDM TESTS: %d passed, %d failed" % [_passes, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)
