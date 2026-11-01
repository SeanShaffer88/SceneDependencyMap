extends CharacterBody2D


func collect(points: int) -> void:
	GameState.add_score(points)
