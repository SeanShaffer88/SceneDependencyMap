## Scene Dependency Map — core scanner.
## Pure operation: scans the current Godot project (res://), builds a
## dependency graph of scenes, scripts, resources, imported assets and
## autoloads, and analyses it for unused files, missing files, cycles,
## deep chains, hub risks and autoload coupling.
## No editor-only APIs are used, so the editor dock and the headless CLI
## run exactly the same scan.
extends RefCounted

const SKIP_DIRS: Array[String] = [".godot", ".git", ".svn", "dependency_reports"]
const ASSET_EXTS: Array[String] = ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "wav", "ogg", "mp3", "opus", "ttf", "otf", "woff", "woff2", "mp4", "webm", "glb", "gltf", "obj", "fbx", "wav"]
const RESOURCE_EXTS: Array[String] = ["tres", "res", "theme", "material", "mesh", "curve", "gradient", "environment", "occ", "anim", "physicsmaterial", "tileset", "tilemap", "fontdata", "translation", "import", "cfg", "json", "txt", "md", "csv", "shader", "gdshader", "cs"]

var deep_chain_threshold: int = 8
var hub_fan_in_threshold: int = 5
var hub_fan_out_threshold: int = 10
var autoload_coupling_threshold: int = 3
## Paths (res:// prefixes) never reported as unused. The plugin's own
## folder is always excluded from the unused list — it is editor tooling,
## not game content — but its files still appear in the graph.
var exclude_unused_prefixes: Array[String] = ["res://addons/"]

var _nodes: Dictionary = {} # path -> node Dictionary
var _edges: Array[Dictionary] = []
var _edge_keys: Dictionary = {}
var _missing: Array[Dictionary] = []
var _errors: Array[Dictionary] = []
var _autoloads: Dictionary = {} # name -> path
var _class_map: Dictionary = {} # class_name -> path
var _entry_points: Array[String] = []
var _main_scene: String = ""


func scan() -> Dictionary:
	_nodes.clear()
	_edges.clear()
	_edge_keys.clear()
	_missing.clear()
	_errors.clear()
	_autoloads.clear()
	_class_map.clear()
	_entry_points.clear()
	_main_scene = ""

	var files: Array[String] = []
	_walk("res://", files)
	files.sort()

	# Pass 1: register every file as a node and index global classes.
	for path in files:
		_register_node(path)
	for path in files:
		if path.get_extension() == "gd":
			_index_class_name(path)

	# Pass 2: project settings (autoloads, main scene) are entry points.
	_parse_project_settings()

	# Pass 3: extract dependencies file by file. A file that cannot be
	# read is quarantined into `errors` — never silently dropped.
	for path in files:
		var ext := path.get_extension()
		if ext == "tscn" or ext == "tres":
			_parse_text_resource(path)
		elif ext == "gd":
			_parse_script(path)
		elif ext == "import":
			_parse_import(path)

	_dedupe_and_validate_edges()
	return _analyse()


# ---------------------------------------------------------------- files

func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(name):
				_walk(full, out)
		else:
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _classify(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if ext == "tscn" or ext == "scn":
		return "scene"
	if ext == "gd" or ext == "cs":
		return "script"
	if ASSET_EXTS.has(ext.strip_edges()):
		return "asset"
	if RESOURCE_EXTS.has(ext):
		return "resource"
	return "other"


func _register_node(path: String) -> void:
	if _nodes.has(path):
		return
	_nodes[path] = {
		"path": path,
		"type": _classify(path),
		"name": path.get_file(),
		"fan_in": 0,
		"fan_out": 0,
		"reachable": false,
		"is_entry": false,
		"is_autoload": false,
		"autoload_name": "",
	}


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		_errors.append({"path": path, "error": "File vanished during scan"})
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_errors.append({"path": path, "error": "Could not open file (error %d)" % FileAccess.get_open_error()})
		return ""
	var text := f.get_as_text()
	f.close()
	if text.find(char(0)) != -1:
		_errors.append({"path": path, "error": "Binary format — dependencies inside binary files are not parsed in v1"})
		return ""
	return text


# ------------------------------------------------------- project.godot

func _parse_project_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://project.godot") != OK:
		_errors.append({"path": "res://project.godot", "error": "Could not parse project.godot"})
		return
	_register_node("res://project.godot")
	_nodes["res://project.godot"]["type"] = "project"
	_mark_entry("res://project.godot")

	if cfg.has_section("application"):
		var main = cfg.get_value("application", "run/main_scene", "")
		if typeof(main) == TYPE_STRING and main != "":
			_main_scene = main
			_mark_entry(main)
			_add_edge("res://project.godot", main, "main_scene", "application/run/main_scene")
		var icon = cfg.get_value("application", "config/icon", "")
		if typeof(icon) == TYPE_STRING and icon != "":
			_add_edge("res://project.godot", icon, "project_ref", "application/config/icon")

	if cfg.has_section("autoload"):
		for key in cfg.get_section_keys("autoload"):
			var raw := str(cfg.get_value("autoload", key, ""))
			var path := raw.trim_prefix("*")
			if path == "":
				continue
			_autoloads[key] = path
			_mark_entry(path)
			if _nodes.has(path):
				_nodes[path]["is_autoload"] = true
				_nodes[path]["autoload_name"] = key
			_add_edge("res://project.godot", path, "autoload", key)


func _mark_entry(path: String) -> void:
	_register_node(path)
	_nodes[path]["is_entry"] = true
	if not _entry_points.has(path):
		_entry_points.append(path)


# ---------------------------------------------------------------- edges

func _add_edge(from_path: String, to_path: String, kind: String, detail: String = "") -> void:
	if from_path == "" or to_path == "":
		return
	if not to_path.begins_with("res://"):
		return # uid:// and user:// references are noted by callers, not graphed
	var key := from_path + "\n" + to_path + "\n" + kind
	if _edge_keys.has(key):
		return
	_edge_keys[key] = true
	_register_node(to_path)
	_edges.append({"from": from_path, "to": to_path, "kind": kind, "detail": detail})


func _looks_like_file(path: String) -> bool:
	return path.get_file().contains(".")


func _dedupe_and_validate_edges() -> void:
	var seen: Dictionary = {}
	for e in _edges:
		var to_path: String = e["to"]
		var pair := str(e["from"]) + "\n" + to_path
		if seen.has(pair):
			continue
		seen[pair] = true
		if not FileAccess.file_exists(to_path):
			_missing.append({"from": e["from"], "to": to_path, "kind": e["kind"], "detail": e["detail"]})


# -------------------------------------------------------------- parsers

func _regex(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


func _extract_quoted(line: String, key: String) -> String:
	var marker := key + "=\""
	var start := line.find(marker)
	if start == -1:
		return ""
	start += marker.length()
	var end := line.find("\"", start)
	if end == -1:
		return ""
	return line.substr(start, end - start)


func _parse_text_resource(path: String) -> void:
	var text := _read_text(path)
	if text == "":
		return
	# Typed external resources (the authoritative list in .tscn/.tres).
	for line in text.split("\n"):
		if line.begins_with("[ext_resource"):
			var target := _extract_quoted(line, "path")
			if target != "":
				_add_edge(path, target, "ext_resource", _extract_quoted(line, "type"))
	# Fallback: any other res:// literal that names a file (exported
	# properties, etc.). Bare folder strings are not dependencies.
	var re := _regex("\"(res://[^\"]+)\"")
	for m in re.search_all(text):
		if _looks_like_file(m.get_string(1)):
			_add_edge(path, m.get_string(1), "resource_ref", "string literal")


func _index_class_name(path: String) -> void:
	var text := _read_text(path)
	if text == "":
		return
	var re := _regex("(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var m := re.search(text)
	if m != null:
		_class_map[m.get_string(1)] = path


func _resolve_script_ref(from_path: String, ref: String) -> String:
	if ref.begins_with("res://") or ref.begins_with("uid://"):
		return ref
	if ref.begins_with("user://"):
		return ""
	return from_path.get_base_dir().path_join(ref).simplify_path()


func _parse_script(path: String) -> void:
	var text := _read_text(path)
	if text == "":
		return
	var re_load := _regex("(preload|load)\\s*\\(\\s*\"([^\"]+)\"")
	for m in re_load.search_all(text):
		var target := _resolve_script_ref(path, m.get_string(2))
		_add_edge(path, target, m.get_string(1), "code reference")

	var re_extends_path := _regex("(?m)^\\s*extends\\s+\"([^\"]+)\"")
	var mp := re_extends_path.search(text)
	if mp != null:
		_add_edge(path, _resolve_script_ref(path, mp.get_string(1)), "extends", "base script")

	var re_extends_name := _regex("(?m)^\\s*extends\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var mn := re_extends_name.search(text)
	if mn != null and _class_map.has(mn.get_string(1)):
		_add_edge(path, _class_map[mn.get_string(1)], "extends", mn.get_string(1))

	# Any remaining res:// literal naming a file is a probable dynamic load.
	var re_literal := _regex("\"(res://[^\"]+)\"")
	for m in re_literal.search_all(text):
		if _looks_like_file(m.get_string(1)):
			_add_edge(path, m.get_string(1), "string_ref", "string literal — check for dynamic load()")

	# Autoload singleton usage: `GameState.do_thing()`.
	for autoload_name in _autoloads:
		if _autoloads[autoload_name] == path:
			continue
		var re_auto := _regex("\\b" + autoload_name + "\\s*\\.")
		if re_auto.search(text) != null:
			_add_edge(path, _autoloads[autoload_name], "autoload_ref", autoload_name)


func _parse_import(path: String) -> void:
	# A .import file sits beside its source asset and its source_file
	# points at that same asset, so it adds no dependency of its own.
	# It is still registered as a node (and excluded from the unused
	# list) so the asset's import state is visible in the counts.
	_read_text(path)


# ------------------------------------------------------------- analysis

func _analyse() -> Dictionary:
	# Fan in/out on deduped file edges (self-edges ignored).
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	for path in _nodes:
		outgoing[path] = []
		incoming[path] = []
	for e in _edges:
		var a: String = e["from"]
		var b: String = e["to"]
		if a == b:
			continue
		if not (outgoing[a] as Array).has(b):
			(outgoing[a] as Array).append(b)
		if not (incoming[b] as Array).has(a):
			(incoming[b] as Array).append(a)
	for path in _nodes:
		_nodes[path]["fan_out"] = (outgoing[path] as Array).size()
		_nodes[path]["fan_in"] = (incoming[path] as Array).size()

	# Reachability from entry points.
	var queue: Array[String] = []
	for entry in _entry_points:
		if _nodes.has(entry) and not _nodes[entry]["reachable"]:
			_nodes[entry]["reachable"] = true
			queue.append(entry)
	while not queue.is_empty():
		var cur := queue.pop_front()
		for nxt in outgoing.get(cur, []):
			if _nodes.has(nxt) and not _nodes[nxt]["reachable"]:
				_nodes[nxt]["reachable"] = true
				queue.append(nxt)

	# Unused: unreachable, and not under an excluded prefix.
	var unused: Array[Dictionary] = []
	for path in _nodes:
		var node: Dictionary = _nodes[path]
		if node["reachable"] or node["is_entry"]:
			continue
		var excluded := false
		for prefix in exclude_unused_prefixes:
			if path.begins_with(prefix):
				excluded = true
		if excluded or path == "res://project.godot" or path.get_extension() == "import":
			continue
		var reason := "orphan — nothing references it and it is not reachable from the main scene or an autoload"
		if int(node["fan_in"]) > 0:
			reason = "dead cluster — referenced only by other unreachable files"
		unused.append({"path": path, "type": node["type"], "reason": reason, "fan_in": node["fan_in"]})
	unused.sort_custom(func(a, b): return str(a["path"]) < str(b["path"]))

	var cycles := _find_cycles(outgoing)
	var deep := _find_deep_chains(outgoing)

	var hubs: Array[Dictionary] = []
	for path in _nodes:
		var node: Dictionary = _nodes[path]
		if int(node["fan_in"]) >= hub_fan_in_threshold:
			hubs.append({"path": path, "kind": "high_fan_in", "value": node["fan_in"],
				"detail": "%d files depend on this — changing it can break all of them" % int(node["fan_in"])})
		if int(node["fan_out"]) >= hub_fan_out_threshold:
			hubs.append({"path": path, "kind": "high_fan_out", "value": node["fan_out"],
				"detail": "depends on %d files — many things can break it" % int(node["fan_out"])})
	hubs.sort_custom(func(a, b): return int(a["value"]) > int(b["value"]))

	# Autoload risks: heavy coupling, and autoloads that pull in scenes.
	var autoload_risks: Array[Dictionary] = []
	var usage: Dictionary = {}
	for e in _edges:
		if e["kind"] == "autoload_ref":
			if not usage.has(e["from"]):
				usage[e["from"]] = []
			if not (usage[e["from"]] as Array).has(e["detail"]):
				(usage[e["from"]] as Array).append(e["detail"])
	for path in usage:
		if (usage[path] as Array).size() >= autoload_coupling_threshold:
			autoload_risks.append({"path": path, "kind": "heavy_autoload_coupling",
				"detail": "uses %d autoloads (%s) — tightly coupled to global state" % [(usage[path] as Array).size(), ", ".join(usage[path])]})
	for name in _autoloads:
		var apath: String = _autoloads[name]
		for target in outgoing.get(apath, []):
			if _nodes.has(target) and _nodes[target]["type"] == "scene":
				autoload_risks.append({"path": apath, "kind": "autoload_loads_scene",
					"detail": "autoload '%s' depends on scene %s — load order and circular-load risk" % [name, target]})

	var summary := {
		"files": _nodes.size(),
		"edges": _edges.size(),
		"scenes": 0, "scripts": 0, "resources": 0, "assets": 0,
		"autoloads": _autoloads.size(),
		"entries": _entry_points.size(),
		"unused": unused.size(),
		"missing": _missing.size(),
		"cycles": cycles.size(),
		"deep_chains": deep.size(),
		"hubs": hubs.size(),
		"errors": _errors.size(),
	}
	for path in _nodes:
		match _nodes[path]["type"]:
			"scene": summary["scenes"] += 1
			"script": summary["scripts"] += 1
			"resource": summary["resources"] += 1
			"asset": summary["assets"] += 1

	return {
		"summary": summary,
		"nodes": _nodes,
		"edges": _edges,
		"outgoing": outgoing,
		"incoming": incoming,
		"autoloads": _autoloads,
		"entry_points": _entry_points,
		"main_scene": _main_scene,
		"unused": unused,
		"missing": _missing,
		"cycles": cycles,
		"deep_chains": deep,
		"hubs": hubs,
		"autoload_risks": autoload_risks,
		"errors": _errors,
		"settings": {
			"deep_chain_threshold": deep_chain_threshold,
			"hub_fan_in_threshold": hub_fan_in_threshold,
			"hub_fan_out_threshold": hub_fan_out_threshold,
			"autoload_coupling_threshold": autoload_coupling_threshold,
		},
	}


# Tarjan strongly-connected components; an SCC with >1 node, or a
# self-loop, is a dependency cycle.
var _t_index: Dictionary = {}
var _t_low: Dictionary = {}
var _t_stack: Array[String] = []
var _t_on_stack: Dictionary = {}
var _t_counter: int = 0
var _t_sccs: Array = []

func _find_cycles(outgoing: Dictionary) -> Array:
	_t_index.clear(); _t_low.clear(); _t_stack.clear(); _t_on_stack.clear(); _t_sccs.clear(); _t_counter = 0
	for path in _nodes:
		if not _t_index.has(path):
			_strong_connect(path, outgoing)
	var cycles: Array = []
	for scc in _t_sccs:
		if (scc as Array).size() > 1:
			var arr: Array = (scc as Array).duplicate()
			arr.sort()
			cycles.append(arr)
		elif (scc as Array).size() == 1:
			var only: String = scc[0]
			if (outgoing.get(only, []) as Array).has(only):
				cycles.append([only])
	cycles.sort_custom(func(a, b): return (a as Array).size() > (b as Array).size())
	return cycles


func _strong_connect(v: String, outgoing: Dictionary) -> void:
	_t_index[v] = _t_counter
	_t_low[v] = _t_counter
	_t_counter += 1
	_t_stack.append(v)
	_t_on_stack[v] = true
	for w in outgoing.get(v, []):
		if not _nodes.has(w):
			continue
		if not _t_index.has(w):
			_strong_connect(w, outgoing)
			_t_low[v] = mini(int(_t_low[v]), int(_t_low[w]))
		elif _t_on_stack.get(w, false):
			_t_low[v] = mini(int(_t_low[v]), int(_t_index[w]))
	if int(_t_low[v]) == int(_t_index[v]):
		var scc: Array[String] = []
		while true:
			var w: String = _t_stack.pop_back()
			_t_on_stack[w] = false
			scc.append(w)
			if w == v:
				break
		_t_sccs.append(scc)


func _find_deep_chains(outgoing: Dictionary) -> Array:
	var memo: Dictionary = {}
	var chains: Array[Dictionary] = []
	for entry in _entry_points:
		var chain: Array[String] = []
		_longest_from(entry, outgoing, memo, {}, chain)
		if chain.size() - 1 >= deep_chain_threshold:
			chains.append({"chain": chain, "length": chain.size() - 1,
				"detail": "dependency chain of %d steps from %s — a break near the top cascades all the way down" % [chain.size() - 1, entry]})
	chains.sort_custom(func(a, b): return int(a["length"]) > int(b["length"]))
	return chains.slice(0, 10)


func _longest_from(node: String, outgoing: Dictionary, memo: Dictionary, in_stack: Dictionary, out_chain: Array[String]) -> int:
	if memo.has(node):
		var cached: Array = memo[node]
		out_chain.assign(cached)
		return cached.size() - 1
	if in_stack.get(node, false):
		out_chain.assign([node])
		return 0
	in_stack[node] = true
	var best: Array[String] = [node]
	for nxt in outgoing.get(node, []):
		if not _nodes.has(nxt):
			continue
		var sub: Array[String] = []
		_longest_from(nxt, outgoing, memo, in_stack, sub)
		var candidate: Array[String] = [node]
		candidate.append_array(sub)
		if candidate.size() > best.size():
			best = candidate
	in_stack.erase(node)
	memo[node] = best.duplicate()
	out_chain.assign(best)
	return best.size() - 1
