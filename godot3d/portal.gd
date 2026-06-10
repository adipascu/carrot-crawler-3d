#   ___
#      |___    stairs between floors
#          |___
extends Area3D

var main: Node3D
var delta := 1
var t := 0.0


func _ready() -> void:
	body_entered.connect(_on_body)


func _on_body(body: Node3D) -> void:
	if body == main.player:
		main.call_deferred("use_stairs", delta)


func _process(dt: float) -> void:
	if main.game_paused or main.ended:
		return
	t += dt
	var ring := get_node("ring") as MeshInstance3D
	ring.rotation.z = t * 0.8
	var pulse := 1.0 + 0.06 * sin(t * 3.0)
	ring.scale = Vector3(pulse, pulse, pulse)
