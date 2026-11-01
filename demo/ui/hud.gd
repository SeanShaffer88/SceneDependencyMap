extends CanvasLayer
## Deliberate fixture risk: this one script leans on all three autoloads
## (heavy autoload coupling — the tool should flag it).


func refresh() -> void:
	var _score: int = GameState.score
	AudioBus.play_click()
	SaveBus.save_game()
