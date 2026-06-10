#   ___
#      |___    first person legs and eyes
#          |___
extends CharacterBody3D

const SPEED := 5.0
const SENS := 0.0023

var main: Node3D
var cam: Camera3D
var yaw := 0.0
var pitch := 0.0
var bob_t := 0.0
var shake_amt := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, -1.45, 1.45)
		rotation.y = yaw
		cam.rotation.x = pitch


func shake(amount := 0.25) -> void:
	shake_amt = amount


func _physics_process(delta: float) -> void:
	if main.ended or main.game_paused:
		return
	var dir := Vector3.ZERO
	var fwd := -transform.basis.z
	var right := transform.basis.x
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir += fwd
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir -= fwd
	if Input.is_key_pressed(KEY_A):
		dir -= right
	if Input.is_key_pressed(KEY_D):
		dir += right
	dir.y = 0
	velocity = dir.normalized() * SPEED if dir.length_squared() > 0.01 else Vector3.ZERO
	move_and_slide()
	position.y = 0.05

	var speed_frac := velocity.length() / SPEED
	bob_t += delta * (10.0 if speed_frac > 0.1 else 0.0)
	var bob := sin(bob_t) * 0.045 * speed_frac
	shake_amt = maxf(0.0, shake_amt - delta * 1.2)
	var sx := (randf() - 0.5) * shake_amt
	var sy := (randf() - 0.5) * shake_amt
	cam.position = Vector3(sx, 1.5 + bob + sy, 0)
