extends Control

const PX := 5.0

var main: Node3D


func _draw() -> void:
	var L: int = main.L
	var rows: int = main.ROWS
	draw_rect(Rect2(0, 0, L * PX, rows * PX), Color(0, 0, 0, 0.65))
	for r in rows:
		for c in L:
			if main.grid[r * L + c] != main.OPEN:
				draw_rect(Rect2(c * PX, r * PX, PX, PX), Color(0.5, 0.48, 0.55, 0.9))
	for coin in main.coins:
		if is_instance_valid(coin):
			_dot(coin.global_position, Color(1.0, 0.85, 0.1))
	for foe in main.enemies:
		if is_instance_valid(foe):
			_dot(foe.global_position, Color(1.0, 0.3, 0.15))
	if main.down_cell >= 0:
		_dot(main.cell_pos(main.down_cell), Color(0.2, 0.9, 1.0))
	if main.up_cell >= 0:
		_dot(main.cell_pos(main.up_cell), Color(1.0, 0.3, 1.0))
	var p: Vector3 = main.player.global_position
	var center := Vector2(p.x / main.CELL * PX, p.z / main.CELL * PX)
	draw_circle(center, PX * 0.7, Color(0.3, 1.0, 0.3))
	var yaw: float = main.player.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	draw_line(center, center + fwd * PX * 2.0, Color(0.3, 1.0, 0.3), 1.5)


func _dot(world: Vector3, color: Color) -> void:
	draw_circle(Vector2(world.x / main.CELL * PX, world.z / main.CELL * PX), PX * 0.55, color)
