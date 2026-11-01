extends Node
## Demo autoload with a deliberate risk: an autoload that preloads a scene
## (load-order / circular-load risk the tool should flag).

var popup_scene: PackedScene = preload("res://demo/ui/hud.tscn")


func play_click() -> void:
	pass
