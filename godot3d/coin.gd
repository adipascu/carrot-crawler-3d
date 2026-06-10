extends Area3D

var main: Node3D
var t := randf() * TAU


func _ready() -> void:
	body_entered.connect(_on_body)


func _on_body(body: Node3D) -> void:
	if body == main.player:
		main.call_deferred("collect_coin", self)


func _process(delta: float) -> void:
	if main.game_paused or main.ended:
		return
	t += delta
	rotation.y = t * 2.2
	position.y = 1.0 + sin(t * 2.0) * 0.12
