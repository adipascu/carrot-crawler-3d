extends CharacterBody3D

const SPEED := 2.4
const AGGRO := 12.0
const BITE_RANGE := 1.5
const BITE_CD := 1.12

var main: Node3D
var bite_cd := 0.0
var wander_t := 0.0
var wander_dir := Vector3.ZERO
var hop_t := 0.0
var lunge := 0.0
var face_yaw := 0.0


func _physics_process(delta: float) -> void:
	if main.ended:
		return
	var to_player: Vector3 = main.player.global_position - global_position
	to_player.y = 0
	var dist: float = to_player.length()
	bite_cd = maxf(0.0, bite_cd - delta)
	lunge = maxf(0.0, lunge - delta * 3.0)

	if dist < AGGRO:
		velocity = to_player.normalized() * SPEED
	else:
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(1.0, 3.0)
			var a := randf() * TAU
			wander_dir = Vector3(cos(a), 0, sin(a))
		velocity = wander_dir * SPEED * 0.5
	velocity.y = 0
	move_and_slide()
	position.y = 0.0

	if dist < BITE_RANGE and bite_cd == 0.0:
		bite_cd = BITE_CD
		lunge = 1.0
		main.damage(1)
		main.player.shake(0.3)

	var vis := get_node("vis") as Node3D
	if velocity.length_squared() > 0.05:
		face_yaw = lerp_angle(face_yaw, atan2(-velocity.x, -velocity.z), delta * 8.0)
	vis.rotation.y = face_yaw
	hop_t += delta * (9.0 if dist < AGGRO else 5.0)
	var hop := absf(sin(hop_t))
	vis.position.y = hop * 0.25
	var squash := 1.0 + 0.12 * sin(hop_t * 2.0) + lunge * 0.25
	vis.scale = Vector3(2.0 - squash, squash, 2.0 - squash).clamp(
			Vector3(0.7, 0.7, 0.7), Vector3(1.35, 1.35, 1.35))
