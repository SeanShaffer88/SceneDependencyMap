extends Area2D


func _on_body_entered(_body: Node) -> void:
	GameState.add_score(10)
	AudioBus.play_click()
