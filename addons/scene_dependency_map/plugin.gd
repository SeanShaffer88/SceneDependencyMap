## Scene Dependency Map — editor plugin entry point.
@tool
extends EditorPlugin

const Dock := preload("res://addons/scene_dependency_map/ui/sdm_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = Dock.new()
	_dock.open_file_requested.connect(_open_file)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	add_tool_menu_item("Scene Dependency Map: Scan Project", func() -> void: _dock.rescan())


func _exit_tree() -> void:
	remove_tool_menu_item("Scene Dependency Map: Scan Project")
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()


func _open_file(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	var iface := get_editor_interface()
	if path.get_extension() == "tscn":
		iface.open_scene_from_path(path)
	else:
		var res := load(path)
		if res != null:
			iface.edit_resource(res)
		else:
			iface.select_file(path)
