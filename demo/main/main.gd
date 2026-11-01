extends Node2D


func _ready() -> void:
	GameState.add_score(1)
	AudioBus.play_click()
