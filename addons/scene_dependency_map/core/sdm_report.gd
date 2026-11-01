## Scene Dependency Map — report exporters (JSON, Markdown, HTML).
## Same operation as the editor dock and CLI: takes a scanner result
## Dictionary and renders it. No editor-only APIs.
extends RefCounted

const TEMPLATE_PATH := "res://addons/scene_dependency_map/templates/report_template.html"


static func graph_only(result: Dictionary) -> Dictionary:
	# Nodes/edges in a JSON-safe shape (the live result also carries
	# helper dictionaries that JSON can handle, but keep exports lean).
	var nodes: Array = []
	var node_dict: Dictionary = result["nodes"]
	var keys: Array = node_dict.keys()
	keys.sort()
	for path in keys:
		nodes.append(node_dict[path])
	return {
		"summary": result["summary"],
		"nodes": nodes,
		"edges": result["edges"],
		"autoloads": result["autoloads"],
		"entry_points": result["entry_points"],
		"main_scene": result["main_scene"],
		"unused": result["unused"],
		"missing": result["missing"],
		"cycles": result["cycles"],
		"deep_chains": result["deep_chains"],
		"hubs": result["hubs"],
		"autoload_risks": result["autoload_risks"],
		"errors": result["errors"],
		"settings": result["settings"],
	}


static func to_json(result: Dictionary) -> String:
	return JSON.stringify(graph_only(result), "\t")


static func to_markdown(result: Dictionary) -> String:
	var s: Dictionary = result["summary"]
	var lines: Array[String] = []
	lines.append("# Scene Dependency Map — report")
	lines.append("")
	lines.append("Main scene: `%s`" % str(result["main_scene"]))
	lines.append("")
	lines.append("## Summary")
	lines.append("")
	lines.append("| Count | What |")
	lines.append("|---|---|")
	lines.append("| %d | files scanned |" % int(s["files"]))
	lines.append("| %d | dependency links |" % int(s["edges"]))
	lines.append("| %d | scenes |" % int(s["scenes"]))
	lines.append("| %d | scripts |" % int(s["scripts"]))
	lines.append("| %d | resources |" % int(s["resources"]))
	lines.append("| %d | imported assets |" % int(s["assets"]))
	lines.append("| %d | autoloads |" % int(s["autoloads"]))
	lines.append("")
	lines.append("## Autoloads")
	lines.append("")
	if (result["autoloads"] as Dictionary).is_empty():
		lines.append("None.")
	else:
		for name in result["autoloads"]:
			lines.append("- **%s** — `%s`" % [name, result["autoloads"][name]])
	lines.append("")
	lines.append("## Missing files (%d)" % (result["missing"] as Array).size())
	lines.append("")
	if (result["missing"] as Array).is_empty():
		lines.append("None — every referenced file exists.")
	else:
		for m in result["missing"]:
			lines.append("- `%s` references missing `%s` (%s)" % [m["from"], m["to"], m["kind"]])
	lines.append("")
	lines.append("## Unused files (%d)" % (result["unused"] as Array).size())
	lines.append("")
	lines.append("Not reachable from the main scene or any autoload. Check before deleting — a file loaded only by a string built at run time can look unused.")
	lines.append("")
	for u in result["unused"]:
		lines.append("- `%s` — %s" % [u["path"], u["reason"]])
	lines.append("")
	lines.append("## Dependency cycles (%d)" % (result["cycles"] as Array).size())
	lines.append("")
	if (result["cycles"] as Array).is_empty():
		lines.append("None.")
	else:
		for c in result["cycles"]:
			lines.append("- Cycle: %s" % " → ".join(c))
	lines.append("")
	lines.append("## Deep chains (%d)" % (result["deep_chains"] as Array).size())
	lines.append("")
	if (result["deep_chains"] as Array).is_empty():
		lines.append("None over the threshold of %d steps." % int(result["settings"]["deep_chain_threshold"]))
	else:
		for d in result["deep_chains"]:
			lines.append("- %d steps: %s" % [int(d["length"]), " → ".join(d["chain"])])
	lines.append("")
	lines.append("## Hub files (%d)" % (result["hubs"] as Array).size())
	lines.append("")
	for h in result["hubs"]:
		lines.append("- `%s` — %s" % [h["path"], h["detail"]])
	if (result["hubs"] as Array).is_empty():
		lines.append("None over the thresholds.")
	lines.append("")
	lines.append("## Autoload risks (%d)" % (result["autoload_risks"] as Array).size())
	lines.append("")
	for r in result["autoload_risks"]:
		lines.append("- `%s` — %s" % [r["path"], r["detail"]])
	if (result["autoload_risks"] as Array).is_empty():
		lines.append("None.")
	lines.append("")
	lines.append("## Files that could not be parsed (%d)" % (result["errors"] as Array).size())
	lines.append("")
	for e in result["errors"]:
		lines.append("- `%s` — %s" % [e["path"], e["error"]])
	if (result["errors"] as Array).is_empty():
		lines.append("None.")
	lines.append("")
	return "\n".join(lines)


static func to_html(result: Dictionary) -> String:
	var data := to_json(result)
	if FileAccess.file_exists(TEMPLATE_PATH):
		var f := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
		if f != null:
			var tpl := f.get_as_text()
			f.close()
			return tpl.replace("__SDM_DATA__", data).replace("__SDM_TITLE__", "Scene Dependency Map")
	# Fallback if the template is missing: data-only page, still useful.
	return "<!doctype html><meta charset=\"utf-8\"><title>Scene Dependency Map</title><h1>Scene Dependency Map</h1><p>The interactive template file is missing, so here is the raw scan data:</p><pre>" + data.xml_escape() + "</pre>"
