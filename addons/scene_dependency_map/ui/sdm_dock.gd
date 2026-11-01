## Scene Dependency Map — editor dock.
## Built in code (no .tscn to break). Every control has a tooltip.
## The scan itself is the shared core operation (sdm_scanner.gd);
## this file is only presentation.
@tool
extends Control

signal open_file_requested(path: String)

const Scanner := preload("res://addons/scene_dependency_map/core/sdm_scanner.gd")
const Report := preload("res://addons/scene_dependency_map/core/sdm_report.gd")

const TYPE_COLORS := {
	"scene": Color(0.88, 0.32, 0.32), "script": Color(0.32, 0.56, 0.88),
	"resource": Color(0.88, 0.66, 0.32), "asset": Color(0.38, 0.76, 0.44),
	"project": Color(0.9, 0.9, 0.9), "other": Color(0.55, 0.55, 0.55),
}

var _result: Dictionary = {}
var _graph: GraphEdit
var _issues: ItemList
var _search: LineEdit
var _risk_only: CheckBox
var _type_filter: OptionButton
var _details: Label
var _summary: Label
var _node_paths: Dictionary = {} # GraphNode name -> res:// path
var _issue_paths: Array[String] = []


func _ready() -> void:
	name = "Dependency Map"
	custom_minimum_size = Vector2(420, 300)
	_build_ui()
	# Useful in the first minute: scan as soon as the dock appears.
	call_deferred("rescan")


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	var scan_btn := Button.new()
	scan_btn.text = "↻ Scan project"
	scan_btn.tooltip_text = "Scan every scene, script, resource and autoload in this project and rebuild the map"
	scan_btn.pressed.connect(rescan)
	bar.add_child(scan_btn)

	var html_btn := Button.new()
	html_btn.text = "Export HTML"
	html_btn.tooltip_text = "Save an interactive map you can open in any browser (works offline)"
	html_btn.pressed.connect(func() -> void: _export("html"))
	bar.add_child(html_btn)
	var json_btn := Button.new()
	json_btn.text = "JSON"
	json_btn.tooltip_text = "Save the raw scan data as JSON (for CI checks and other tools)"
	json_btn.pressed.connect(func() -> void: _export("json"))
	bar.add_child(json_btn)
	var md_btn := Button.new()
	md_btn.text = "Report"
	md_btn.tooltip_text = "Save a plain-words Markdown report of unused files and risks"
	md_btn.pressed.connect(func() -> void: _export("md"))
	bar.add_child(md_btn)
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.tooltip_text = "What this panel means, in plain words (works offline)"
	help_btn.pressed.connect(_show_help)
	bar.add_child(help_btn)

	_summary = Label.new()
	_summary.tooltip_text = "Totals from the latest scan"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_summary)

	var filter_bar := HBoxContainer.new()
	root.add_child(filter_bar)
	_search = LineEdit.new()
	_search.placeholder_text = "Search files…"
	_search.tooltip_text = "Type part of a file name or folder to filter the map and the list"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _refresh_views())
	filter_bar.add_child(_search)
	_type_filter = OptionButton.new()
	_type_filter.tooltip_text = "Show only one kind of file in the map"
	for label in ["All types", "Scenes", "Scripts", "Resources", "Assets"]:
		_type_filter.add_item(label)
	_type_filter.item_selected.connect(func(_i: int) -> void: _refresh_views())
	filter_bar.add_child(_type_filter)
	_risk_only = CheckBox.new()
	_risk_only.text = "Risks only"
	_risk_only.tooltip_text = "Show only unused files, cycles, hubs, and files other files are missing"
	_risk_only.toggled.connect(func(_on: bool) -> void: _refresh_views())
	filter_bar.add_child(_risk_only)

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_graph = GraphEdit.new()
	_graph.tooltip_text = "The dependency map. Boxes are files, lines mean 'depends on'. Drag boxes to arrange them; click a box for details; double-click to open the file."
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(0, 260)
	_graph.node_selected.connect(_on_graph_node_selected)
	split.add_child(_graph)

	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(bottom)
	_issues = ItemList.new()
	_issues.tooltip_text = "Problems found: unused files, missing files, cycles, deep chains and hub risks. Click one to find it in the map; double-click to open the file."
	_issues.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_issues.item_selected.connect(_on_issue_selected)
	_issues.item_activated.connect(func(idx: int) -> void:
		if idx >= 0 and idx < _issue_paths.size():
			open_file_requested.emit(_issue_paths[idx]))
	bottom.add_child(_issues)
	_details = Label.new()
	_details.tooltip_text = "Details of the file you clicked: what it depends on and what depends on it"
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_details.text = "Click a box or a problem in the list."
	bottom.add_child(_details)


func rescan() -> void:
	var scanner = Scanner.new()
	_result = scanner.scan()
	var s: Dictionary = _result["summary"]
	_summary.text = "%d files · %d links · %d unused · %d missing · %d cycles · %d deep chains · %d hubs" % [
		s["files"], s["edges"], s["unused"], s["missing"], s["cycles"], s["deep_chains"], s["hubs"]]
	_refresh_views()


func _risky_paths() -> Dictionary:
	var risky: Dictionary = {}
	for u in _result.get("unused", []):
		risky[u["path"]] = true
	for m in _result.get("missing", []):
		risky[m["to"]] = true
	for c in _result.get("cycles", []):
		for p in c:
			risky[p] = true
	for h in _result.get("hubs", []):
		risky[h["path"]] = true
	return risky


func _type_matches(node_type: String) -> bool:
	match _type_filter.selected:
		1: return node_type == "scene"
		2: return node_type == "script"
		3: return node_type == "resource"
		4: return node_type == "asset"
	return true


func _refresh_views() -> void:
	if _result.is_empty():
		return
	_refresh_issues()
	_refresh_graph()


func _refresh_issues() -> void:
	_issues.clear()
	_issue_paths.clear()
	for m in _result["missing"]:
		_add_issue("❌ Missing: %s needs %s" % [m["from"].get_file(), m["to"]], m["to"])
	for u in _result["unused"]:
		_add_issue("🧹 Unused: %s" % u["path"].trim_prefix("res://"), u["path"])
	for c in _result["cycles"]:
		_add_issue("🔁 Cycle (%d files): %s" % [(c as Array).size(), " → ".join(c)], c[0])
	for d in _result["deep_chains"]:
		_add_issue("⛓ Deep chain: %d steps from %s" % [int(d["length"]), (d["chain"] as Array)[0]], (d["chain"] as Array)[0])
	for h in _result["hubs"]:
		_add_issue("🎯 Hub: %s — %s" % [h["path"].get_file(), h["detail"]], h["path"])
	for r in _result["autoload_risks"]:
		_add_issue("★ Autoload risk: %s — %s" % [r["path"].get_file(), r["detail"]], r["path"])
	for e in _result["errors"]:
		_add_issue("⚠ Could not parse: %s" % e["path"], e["path"])
	if _issues.item_count == 0:
		_issues.add_item("✓ No problems found")
		_issue_paths.append("")


func _add_issue(text: String, path: String) -> void:
	_issues.add_item(text)
	_issue_paths.append(path)


func _refresh_graph() -> void:
	for child in _graph.get_children():
		if child is GraphNode:
			_graph.remove_child(child)
			child.queue_free()
	_node_paths.clear()
	if _result.is_empty():
		return
	var risky := _risky_paths()
	var query := _search.text.strip_edges().to_lower()
	var nodes: Dictionary = _result["nodes"]
	var keep: Dictionary = {}
	for path in nodes:
		var node: Dictionary = nodes[path]
		if query != "" and not path.to_lower().contains(query):
			continue
		if not _type_matches(node["type"]):
			continue
		if _risk_only.button_pressed and not risky.has(path):
			continue
		keep[path] = node
	# Layered layout: x by SHORTEST distance from an entry point (BFS, so
	# dependency cycles cannot make the layout loop forever), y per layer.
	var depth: Dictionary = {}
	var bfs: Array = []
	for entry in _result["entry_points"]:
		depth[entry] = 0
		bfs.append(entry)
	while not bfs.is_empty():
		var cur: String = bfs.pop_front()
		for target in _result["outgoing"].get(cur, []):
			if not depth.has(target):
				depth[target] = int(depth[cur]) + 1
				bfs.append(target)
	var layer_counts: Dictionary = {}
	var graph_nodes: Dictionary = {}
	for path in keep:
		var node: Dictionary = keep[path]
		var gn := GraphNode.new()
		var safe := "n" + str(abs(path.hash()))
		gn.name = safe
		gn.title = ("★ " if node["is_autoload"] else "") + node["name"]
		gn.tooltip_text = "%s\nType: %s\nDepends on %d · depended on by %d%s" % [
			path, node["type"], node["fan_out"], node["fan_in"],
			"\n⚠ Flagged — see the problem list" if risky.has(path) else ""]
		var d: int = depth.get(path, 20)
		var row: int = layer_counts.get(d, 0)
		layer_counts[d] = row + 1
		gn.position_offset = Vector2(20 + d * 300, 20 + row * 90)
		var label := Label.new()
		label.text = node["type"] + (" · unreachable" if not node["reachable"] else "")
		label.add_theme_color_override("font_color", TYPE_COLORS.get(node["type"], Color.WHITE))
		if risky.has(path):
			label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		gn.add_child(label)
		gn.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
		_graph.add_child(gn)
		graph_nodes[path] = gn
		_node_paths[safe] = path
	for e in _result["edges"]:
		if graph_nodes.has(e["from"]) and graph_nodes.has(e["to"]) and e["from"] != e["to"]:
			_graph.connect_node(graph_nodes[e["from"]].name, 0, graph_nodes[e["to"]].name, 0)


func _describe(path: String) -> String:
	if not _result["nodes"].has(path):
		return path
	var node: Dictionary = _result["nodes"][path]
	var lines: Array[String] = [path, "Type: %s%s%s" % [node["type"],
		" · autoload " + node["autoload_name"] if node["is_autoload"] else "",
		" · entry point" if node["is_entry"] else ""]]
	lines.append("Reachable: %s" % ("yes" if node["reachable"] else "NO — possible unused file"))
	var outs: Array[String] = []
	var ins: Array[String] = []
	for e in _result["edges"]:
		if e["from"] == path: outs.append("→ %s [%s]" % [e["to"], e["kind"]])
		if e["to"] == path: ins.append("← %s [%s]" % [e["from"], e["kind"]])
	lines.append("Depends on (%d):" % outs.size())
	lines.append_array(outs if not outs.is_empty() else ["(nothing)"])
	lines.append("Depended on by (%d):" % ins.size())
	lines.append_array(ins if not ins.is_empty() else ["(nothing)"])
	lines.append("Double-click the map box or list item to open this file.")
	return "\n".join(lines)


func _on_graph_node_selected(node: Node) -> void:
	if _node_paths.has(node.name):
		_details.text = _describe(_node_paths[node.name])


func _on_issue_selected(idx: int) -> void:
	if idx >= 0 and idx < _issue_paths.size() and _issue_paths[idx] != "":
		_details.text = _describe(_issue_paths[idx])


func _export(format: String) -> void:
	if _result.is_empty():
		rescan()
	var dir := "res://dependency_reports"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := ""
	var content := ""
	match format:
		"html": path = dir.path_join("dependency_map.html"); content = Report.to_html(_result)
		"json": path = dir.path_join("dependency_map.json"); content = Report.to_json(_result)
		"md": path = dir.path_join("dependency_report.md"); content = Report.to_markdown(_result)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()
		_details.text = "Saved: " + path
	else:
		_details.text = "Could not save " + path


func _show_help() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Scene Dependency Map — help"
	dialog.dialog_text = """In plain words:

• Every box is a file. A line from A to B means "A needs B".
• 🧹 Unused = nothing needs it and your game never reaches it, starting from the main scene and autoloads. Check before deleting: a file loaded from a string built while the game runs can look unused.
• ❌ Missing = a file points at another file that is not there. This breaks the game.
• 🔁 Cycle = files need each other in a loop. Godot can load them in the wrong order or not at all.
• ⛓ Deep chain = a long line of files each needing the next. A break near the top breaks everything below.
• 🎯 Hub = a file lots of other files need (changing it is risky), or a file that needs lots of others (lots can break it).
• ★ Autoload = a singleton loaded at startup. Scripts using many autoloads are hard to test and reuse.

Everything runs on your machine, offline. Nothing is uploaded anywhere."""
	dialog.ok_button_text = "Close"
	add_child(dialog)
	dialog.popup_centered(Vector2(560, 420))
