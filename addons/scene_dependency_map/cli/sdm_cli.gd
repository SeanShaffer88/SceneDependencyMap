## Scene Dependency Map — headless command-line scan.
## Usage (from the root of YOUR Godot project, with this addon installed):
##   godot --headless --path . --script res://addons/scene_dependency_map/cli/sdm_cli.gd -- [options]
## Options:
##   --out=<dir>        output folder, res:// path (default res://dependency_reports)
##   --format=<list>    comma list: json,md,html (default all three)
##   --deep=<n>         deep-chain threshold in steps (default 8)
##   --fail-on=<list>   comma list: missing,cycles,unused,deep,hubs,errors
##                      exit code 2 if any listed problem is found (CI gate)
## Exit codes: 0 clean / no --fail-on match, 2 a --fail-on problem, 3 scan failed.
extends SceneTree

const Scanner := preload("res://addons/scene_dependency_map/core/sdm_scanner.gd")
const Report := preload("res://addons/scene_dependency_map/core/sdm_report.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := "res://dependency_reports"
	var formats: Array[String] = ["json", "md", "html"]
	var fail_on: Array[String] = []
	var scanner = Scanner.new()

	for arg in args:
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--format="):
			formats.assign(arg.trim_prefix("--format=").split(","))
		elif arg.begins_with("--fail-on="):
			fail_on.assign(arg.trim_prefix("--fail-on=").split(","))
		elif arg.begins_with("--deep="):
			scanner.deep_chain_threshold = int(arg.trim_prefix("--deep="))
		elif arg == "--help" or arg == "-h":
			print("Scene Dependency Map CLI — see the header of sdm_cli.gd for options.")
			quit(0)
			return

	var result: Dictionary = scanner.scan()
	if (result["errors"] as Array).size() > 0 and int(result["summary"]["files"]) == 0:
		printerr("SDM: scan produced no files — are you running this inside a Godot project?")
		quit(3)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var wrote: Array[String] = []
	if formats.has("json"):
		if _write(out_dir.path_join("dependency_map.json"), Report.to_json(result)):
			wrote.append("dependency_map.json")
	if formats.has("md"):
		if _write(out_dir.path_join("dependency_report.md"), Report.to_markdown(result)):
			wrote.append("dependency_report.md")
	if formats.has("html"):
		if _write(out_dir.path_join("dependency_map.html"), Report.to_html(result)):
			wrote.append("dependency_map.html")

	var s: Dictionary = result["summary"]
	print("SDM scan: %d files, %d links, %d unused, %d missing, %d cycles, %d deep chains, %d hubs, %d autoload risks" % [
		s["files"], s["edges"], s["unused"], s["missing"], s["cycles"], s["deep_chains"], s["hubs"], (result["autoload_risks"] as Array).size()])
	for w in wrote:
		print("SDM wrote: ", out_dir.path_join(w))

	var failed := false
	if fail_on.has("missing") and not (result["missing"] as Array).is_empty(): failed = true
	if fail_on.has("cycles") and not (result["cycles"] as Array).is_empty(): failed = true
	if fail_on.has("unused") and not (result["unused"] as Array).is_empty(): failed = true
	if fail_on.has("deep") and not (result["deep_chains"] as Array).is_empty(): failed = true
	if fail_on.has("hubs") and not (result["hubs"] as Array).is_empty(): failed = true
	if fail_on.has("errors") and not (result["errors"] as Array).is_empty(): failed = true
	quit(2 if failed else 0)


func _write(path: String, content: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("SDM: could not write ", path)
		return false
	f.store_string(content)
	f.close()
	return true
