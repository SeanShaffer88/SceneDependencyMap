extends Node2D

var config: Resource = preload("res://demo/shared/game_config.tres")


func _ready() -> void:
	GameState.add_score(0)
