extends Node
## Demo autoload. Many demo scripts use GameState on purpose: it is the
## hub file in this fixture (high fan-in risk).

var score: int = 0


func add_score(points: int) -> void:
	score += points
