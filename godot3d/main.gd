extends Node3D

const L := 80
const ROWS := 24
const M := 1920
const CELL := 2.0
const WALL := 35
const OPEN := 46
const MAXHP := 10
const REGEN_S := 2.8

var rng := RandomNumberGenerator.new()
var lcg_state := 0
var grid := PackedInt32Array()
var enemy_cells: Array[int] = []
var coin_cells: Array[int] = []
var loaded_row := -1
var loaded_col := -1
var seed_v := 0
var depth := 0
var money := 0
var health := MAXHP
var gens := 0
var down_cell := -1
var up_cell := -1
var regen_accum := 0.0
var stairs_lock := 0.0
var game_paused := false
var ended := false
var was_captured := false

var level_root: Node3D
var player: CharacterBody3D
var hud_stats: Label
var hud_save: Label
var minimap: Control
var pause_layer: CanvasLayer
var end_layer: CanvasLayer
var end_title: Label
var end_stats: Label
var flash_rect: ColorRect
var enemies: Array[Node3D] = []
var coins: Array[Area3D] = []
var sfx := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	grid.resize(M)
	seed_v = int(Time.get_unix_time_from_system()) & 0x7fffffff
	_build_environment()
	_build_player()
	_build_ui()
	_build_audio()
	var args := OS.get_cmdline_user_args()
	gen()
	var spawn := rand_floor_cell()
	var loaded := false
	for a in args:
		if ":" in a and _load_save(a):
			loaded = true
	if not loaded and OS.has_feature("web"):
		var qs := str(JavaScriptBridge.eval(
				"new URLSearchParams(location.search).get('save')||''", true))
		if qs.length() >= 11:
			loaded = _load_save(qs)
	if loaded:
		gen()
	build_level()
	_place_player(loaded_row * L + loaded_col if loaded else spawn)
	if "--selftest" in args:
		selftest()
	elif "--screenshot" in args:
		screenshot_run()


func screenshot_run() -> void:
	minimap.visible = true
	for _i in 90:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://screenshot.png")
	print("SCREENSHOT SAVED")
	get_tree().quit()


func _load_save(s: String) -> bool:
	var re := RegEx.create_from_string("[0-9a-fA-F]+")
	var found := re.search_all(s)
	if found.size() < 6:
		return false
	var f: Array[int] = []
	for k in 6:
		f.append(("0x" + found[k].get_string()).hex_to_int())
	seed_v = f[0]
	depth = f[1]
	health = clampi(f[2], 1, MAXHP)
	loaded_row = clampi(f[3], 1, ROWS - 1)
	loaded_col = clampi(f[4], 0, L - 1)
	money = f[5]
	return true


func apply_save(s: String) -> bool:
	if not _load_save(s):
		return false
	gens = 1
	gen()
	build_level()
	_place_player(loaded_row * L + loaded_col)
	return true


func save_token() -> String:
	return ":%x:%02x:%02x:%02x:%02x:%02x:" % [seed_v, depth, health,
			int(player.position.z / CELL), int(player.position.x / CELL), money]


func lcg_srand(s: int) -> void:
	lcg_state = (s & 0xFFFFFFFF) - 1


func lcg_rand() -> int:
	lcg_state = lcg_state * 6364136223846793005 + 1
	return (lcg_state >> 33) & 0x7FFFFFFF


func edge(i: int) -> bool:
	return i < L or i > 1839 or ((i + 1) & ~1) % L == 0


@warning_ignore("integer_division")
func gen() -> void:
	gens += 1
	lcg_srand(seed_v)
	for i in range(0, L):
		grid[i] = 0
	for i in range(L, M):
		var carved := ((i + 1) & ~1) % L != 0 and i / L < 13 and i / L > 10
		if carved:
			grid[i] = OPEN
		else:
			var dug := lcg_rand() % 100 < 45
			grid[i] = WALL if edge(i) or dug else OPEN
	for _pass in 2:
		for i in range(L, M):
			if not edge(i):
				var s := grid[i - 81] + grid[i - L] + grid[i - 79] + grid[i - 1] + grid[i] \
						+ grid[i + 1] + grid[i + 79] + grid[i + L] + grid[i + 81]
				grid[i] = WALL if s < 360 else OPEN
	var cell := rand_floor_cell()
	down_cell = cell if depth < 100 else -1
	cell = rand_floor_cell()
	up_cell = cell if depth > 0 else -1
	lcg_srand(seed_v * gens)
	enemy_cells.clear()
	coin_cells.clear()
	var lo := 6 * depth
	var hi := lo + (6 + depth / 5 if depth < 100 else 0)
	for j in range(lo, hi):
		if j < 600:
			enemy_cells.append(rand_floor_cell())
			coin_cells.append(rand_floor_cell())


func rand_floor_cell() -> int:
	for _i in 100000:
		var i := lcg_rand() % M
		if grid[i] == OPEN:
			return i
	return L + 1


@warning_ignore("integer_division")
func cell_pos(i: int) -> Vector3:
	return Vector3((i % L) * CELL + CELL / 2.0, 0.0, (i / L) * CELL + CELL / 2.0)


@warning_ignore("integer_division")
func entity_count() -> int:
	return 6 + depth / 5 if depth < 100 else 0


func _noise_mat(tint: Color, rough := 0.95) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.12
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 128
	tex.height = 128
	var nnoise := FastNoiseLite.new()
	nnoise.frequency = 0.2
	var ntex := NoiseTexture2D.new()
	ntex.noise = nnoise
	ntex.width = 128
	ntex.height = 128
	ntex.as_normal_map = true
	ntex.bump_strength = 7.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = tex
	mat.normal_enabled = true
	mat.normal_texture = ntex
	mat.roughness = rough
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.3, 0.3, 0.3)
	return mat


func _flame_particles(color: Color, amount := 14, radius := 0.06) -> GPUParticles3D:
	var pp := ParticleProcessMaterial.new()
	pp.direction = Vector3(0, 1, 0)
	pp.spread = 14.0
	pp.initial_velocity_min = 0.4
	pp.initial_velocity_max = 1.0
	pp.gravity = Vector3(0, 0.7, 0)
	pp.scale_min = 0.4
	pp.scale_max = 1.0
	pp.color = color
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pp.emission_sphere_radius = radius
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qmat.albedo_color = color
	qmat.vertex_color_use_as_albedo = true
	quad.material = qmat
	var p := GPUParticles3D.new()
	p.process_material = pp
	p.draw_pass_1 = quad
	p.amount = amount
	p.lifetime = 0.7
	return p


func _pcm(samples: PackedFloat32Array, rate := 22050, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var ws := AudioStreamWAV.new()
	ws.format = AudioStreamWAV.FORMAT_16_BITS
	ws.mix_rate = rate
	ws.stereo = false
	ws.data = bytes
	if loop:
		ws.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ws.loop_end = samples.size()
	return ws


func _chirp(f0: float, f1: float, dur: float, gain := 0.7) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(f0, f1, t) / rate
		var env := minf(t * 30.0, 1.0) * pow(1.0 - t, 1.6)
		s[i] = (sin(phase) + 0.3 * sin(phase * 2.0)) * env * gain
	return _pcm(s)


func _thud() -> AudioStreamWAV:
	var rate := 22050
	var n := int(0.25 * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var rumble := 0.0
	for i in n:
		var t := float(i) / n
		phase += TAU * lerpf(150.0, 55.0, t) / rate
		rumble = rumble * 0.72 + (randf() * 2.0 - 1.0) * 0.28
		var env := minf(t * 40.0, 1.0) * pow(1.0 - t, 2.2)
		s[i] = (sin(phase) * 0.8 + rumble * 0.7) * env
	return _pcm(s)


func _jingle(notes: Array) -> AudioStreamWAV:
	var rate := 22050
	var note_n := int(0.16 * rate)
	var s := PackedFloat32Array()
	s.resize(note_n * notes.size())
	for k in notes.size():
		var phase := 0.0
		for i in note_n:
			var t := float(i) / note_n
			phase += TAU * float(notes[k]) / rate
			var env := minf(t * 25.0, 1.0) * pow(1.0 - t, 1.3)
			s[k * note_n + i] = (sin(phase) + 0.25 * sin(phase * 3.0)) * env * 0.6
	return _pcm(s)


func _cave_drone() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 4
	var s := PackedFloat32Array()
	s.resize(n)
	var acc := 0.0
	var peak := 0.001
	for i in n:
		acc = acc * 0.998 + (randf() * 2.0 - 1.0) * 0.04
		var swell := 1.0 + 0.4 * sin(TAU * float(i) / n)
		s[i] = acc * swell
		peak = maxf(peak, absf(s[i]))
	for i in n:
		s[i] = s[i] / peak * 0.8
	return _pcm(s, rate, true)


func _midi(n: int) -> float:
	return 440.0 * pow(2.0, (n - 69) / 12.0)


func _render_note(buf: PackedFloat32Array, rate: int, start: float, dur: float,
		freq: float, vol: float, attack: float, bright: float, fade := 0.001) -> void:
	var i0 := int(start * rate)
	var n := int(dur * rate)
	var phase := 0.0
	var w := TAU * freq / rate
	var decay := 1.0
	var dfac := pow(fade, 1.0 / n)
	var atk_n := maxf(attack * rate, 1.0)
	for i in n:
		var idx := i0 + i
		if idx >= buf.size():
			return
		phase += w
		decay *= dfac
		var env := minf(i / atk_n, 1.0) * decay
		var v := sin(phase)
		if bright > 0.0:
			v += bright * sin(phase * 2.0) + bright * 0.4 * sin(phase * 3.0)
		buf[idx] += v * vol * env


func _build_music() -> void:
	var rate := 9000
	var beat := 60.0 / 84.0
	var bars := 8
	var buf := PackedFloat32Array()
	buf.resize(int(bars * 4.0 * beat * rate))
	var roots := [45, 41, 48, 43, 45, 41, 38, 40]
	var thirds := {45: 3, 41: 4, 48: 4, 43: 4, 38: 3, 40: 4}
	for b in bars:
		var t0 := b * 4.0 * beat
		var root: int = roots[b]
		var third: int = thirds[root]
		_render_note(buf, rate, t0, 4.0 * beat, _midi(root - 12), 0.34, 0.01, 0.25, 0.1)
		for iv in [0, third, 7]:
			_render_note(buf, rate, t0, 4.0 * beat, _midi(root + 12 + iv), 0.065, 0.9, 0.0, 0.05)
		var seq := [0, 7, 12, third + 12, 19, 12, third + 12, 7]
		for e in 8:
			_render_note(buf, rate, t0 + e * beat / 2.0, 0.3,
					_midi(root + 24 + seq[e]), 0.085, 0.004, 0.5)
	var melody := [[1.0, 81], [2.5, 79], [3.5, 76], [4.5, 81], [6.0, 74], [7.0, 76]]
	for m in melody:
		_render_note(buf, rate, m[0] * 4.0 * beat, 1.8, _midi(m[1]), 0.085, 0.01, 0.12)
	var peak := 0.001
	for i in buf.size():
		peak = maxf(peak, absf(buf[i]))
	for i in buf.size():
		buf[i] = buf[i] / peak * 0.85
	var music := AudioStreamPlayer.new()
	music.stream = _pcm(buf, rate, true)
	music.volume_db = -13.0
	music.autoplay = true
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)


func _build_audio() -> void:
	_build_music.call_deferred()
	sfx["coin"] = _chirp(900.0, 1900.0, 0.16)
	sfx["bite"] = _thud()
	sfx["teleport"] = _chirp(1400.0, 250.0, 0.35)
	sfx["stairs"] = _chirp(180.0, 620.0, 0.5)
	sfx["win"] = _jingle([523, 659, 784, 1047, 1319])
	sfx["lose"] = _jingle([392, 311, 233, 156, 98])
	var amb := AudioStreamPlayer.new()
	amb.stream = _cave_drone()
	amb.volume_db = -22.0
	amb.autoplay = true
	amb.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(amb)


func play_sfx(sound: String) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = sfx[sound]
	p.volume_db = -8.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func _glow_mat(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 1.2
	return mat


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.53, 0.62)
	env.ambient_light_energy = 1.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.015, 0.015, 0.025)
	env.fog_density = 0.012
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.7
	col.shape = cap
	col.position.y = 0.85
	player.add_child(col)
	var cam := Camera3D.new()
	cam.position.y = 1.5
	cam.fov = 80
	player.add_child(cam)
	var torch := OmniLight3D.new()
	torch.position.y = 1.6
	torch.light_color = Color(1.0, 0.82, 0.55)
	torch.light_energy = 4.6
	torch.omni_range = 32.0
	torch.shadow_enabled = true
	torch.set_script(load("res://torch.gd"))
	player.add_child(torch)
	player.set_script(load("res://player.gd"))
	player.main = self
	player.cam = cam
	add_child(player)


func _place_player(cell: int) -> void:
	player.position = cell_pos(cell) + Vector3(0, 0.05, 0)
	stairs_lock = 1.0


func build_level() -> void:
	if level_root:
		level_root.queue_free()
	enemies.clear()
	coins.clear()
	level_root = Node3D.new()
	level_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level_root)

	var ground := StaticBody3D.new()
	var gmesh := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(L * CELL, 0.2, ROWS * CELL)
	gbox.material = _noise_mat(Color(0.35, 0.3, 0.26))
	gmesh.mesh = gbox
	ground.add_child(gmesh)
	var gcol := CollisionShape3D.new()
	var gshape := BoxShape3D.new()
	gshape.size = gbox.size
	gcol.shape = gshape
	ground.add_child(gcol)
	ground.position = Vector3(L * CELL / 2.0, -0.1, ROWS * CELL / 2.0)
	level_root.add_child(ground)

	var ceiling := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(L * CELL, 0.2, ROWS * CELL)
	cbox.material = _noise_mat(Color(0.2, 0.18, 0.17))
	ceiling.mesh = cbox
	ceiling.position = Vector3(L * CELL / 2.0, 3.1, ROWS * CELL / 2.0)
	level_root.add_child(ceiling)

	var wall_cells: Array[int] = []
	for r in ROWS:
		for c in L:
			if grid[r * L + c] != OPEN:
				wall_cells.append(r * L + c)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var wbox := BoxMesh.new()
	wbox.size = Vector3(CELL, 3.0, CELL)
	wbox.material = _noise_mat(Color(0.45, 0.42, 0.5))
	mm.mesh = wbox
	mm.instance_count = wall_cells.size()
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	level_root.add_child(mmi)
	var walls_body := StaticBody3D.new()
	level_root.add_child(walls_body)
	var wshape := BoxShape3D.new()
	wshape.size = Vector3(CELL, 3.0, CELL)
	for k in wall_cells.size():
		var p := cell_pos(wall_cells[k]) + Vector3(0, 1.5, 0)
		mm.set_instance_transform(k, Transform3D(Basis(), p))
		var wc := CollisionShape3D.new()
		wc.shape = wshape
		wc.position = p
		walls_body.add_child(wc)

	_spawn_torches()
	for j in enemy_cells.size():
		_spawn_enemy(enemy_cells[j])
		_spawn_coin(coin_cells[j])
	if down_cell >= 0:
		_spawn_portal(down_cell, 1, Color(0.2, 0.9, 1.0))
	if up_cell >= 0:
		_spawn_portal(up_cell, -1, Color(1.0, 0.3, 1.0))


func _spawn_torches() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.16, 0.1)
	for r in range(1, ROWS - 1):
		for c in range(1, L - 1):
			if grid[r * L + c] == OPEN or (r * 31 + c * 17) % 11 != 0:
				continue
			var open_dir := Vector3.ZERO
			for d in [[0, 1], [0, -1], [1, 0], [-1, 0]]:
				if grid[(r + d[0]) * L + c + d[1]] == OPEN:
					open_dir = Vector3(d[1], 0, d[0])
					break
			if open_dir == Vector3.ZERO:
				continue
			var torch := Node3D.new()
			torch.position = cell_pos(r * L + c) + open_dir * (CELL / 2.0 + 0.12) \
					+ Vector3(0, 2.0, 0)
			var handle := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.035
			cyl.bottom_radius = 0.05
			cyl.height = 0.5
			cyl.material = wood
			handle.mesh = cyl
			handle.position = open_dir * 0.06 - Vector3(0, 0.18, 0)
			handle.rotation = Vector3(open_dir.z * 0.45, 0, -open_dir.x * 0.45)
			torch.add_child(handle)
			torch.add_child(_flame_particles(Color(1.0, 0.55, 0.15), 12))
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.6, 0.25)
			light.light_energy = 1.1
			light.omni_range = 9.0
			light.set_script(load("res://torch.gd"))
			torch.add_child(light)
			level_root.add_child(torch)


func _spawn_coin(cell: int) -> void:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.8
	shape.shape = sph
	area.add_child(shape)
	var gold := _glow_mat(Color(1.0, 0.85, 0.1))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.26
	torus.outer_radius = 0.34
	torus.material = gold
	ring.mesh = torus
	ring.rotation.x = PI / 2
	area.add_child(ring)
	var sign_mesh := MeshInstance3D.new()
	var txt := TextMesh.new()
	txt.text = "$"
	txt.font_size = 60
	txt.pixel_size = 0.008
	txt.depth = 0.06
	txt.material = gold
	sign_mesh.mesh = txt
	area.add_child(sign_mesh)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.2)
	light.light_energy = 0.6
	light.omni_range = 3.0
	area.add_child(light)
	area.position = cell_pos(cell) + Vector3(0, 1.0, 0)
	area.set_script(load("res://coin.gd"))
	area.main = self
	level_root.add_child(area)
	coins.append(area)


func _spawn_enemy(cell: int) -> void:
	var foe := CharacterBody3D.new()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.4
	col.shape = cap
	col.position.y = 0.8
	foe.add_child(col)
	var vis := Node3D.new()
	vis.name = "vis"
	var body := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.34
	cone.bottom_radius = 0.02
	cone.height = 1.2
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.45, 0.1)
	orange.roughness = 0.7
	cone.material = orange
	body.mesh = cone
	body.position.y = 0.8
	vis.add_child(body)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.2, 0.7, 0.2)
	for k in 3:
		var leaf := MeshInstance3D.new()
		var lcone := CylinderMesh.new()
		lcone.top_radius = 0.02
		lcone.bottom_radius = 0.09
		lcone.height = 0.5
		lcone.material = green
		leaf.mesh = lcone
		leaf.position = Vector3(0, 1.55, 0)
		leaf.rotation = Vector3(0.5, k * TAU / 3.0, 0)
		vis.add_child(leaf)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.05)
	for side in [-1, 1]:
		var eye := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.06
		sph.height = 0.12
		sph.material = black
		eye.mesh = sph
		eye.position = Vector3(side * 0.13, 1.1, -0.28)
		vis.add_child(eye)
	foe.add_child(vis)
	foe.position = cell_pos(cell)
	foe.set_script(load("res://enemy.gd"))
	foe.main = self
	level_root.add_child(foe)
	enemies.append(foe)


func _spawn_portal(cell: int, delta: int, color: Color) -> void:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CELL * 0.9, 3.0, CELL * 0.9)
	shape.shape = box
	shape.position.y = 1.5
	area.add_child(shape)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.8
	torus.material = _glow_mat(color)
	ring.mesh = torus
	ring.rotation.x = PI / 2
	ring.position.y = 1.4
	ring.name = "ring"
	area.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.position.y = 1.4
	area.add_child(light)
	var sparks := _flame_particles(color, 24, 0.7)
	sparks.position.y = 0.6
	area.add_child(sparks)
	area.position = cell_pos(cell)
	area.set_script(load("res://portal.gd"))
	area.main = self
	area.delta = delta
	level_root.add_child(area)


func collect_coin(coin: Area3D) -> void:
	if ended:
		return
	money += 1
	play_sfx("coin")
	var sparkle := _flame_particles(Color(1.0, 0.9, 0.3), 20, 0.25)
	sparkle.one_shot = true
	sparkle.explosiveness = 1.0
	sparkle.position = coin.global_position
	level_root.add_child(sparkle)
	get_tree().create_timer(1.2).timeout.connect(sparkle.queue_free)
	coins.erase(coin)
	coin.queue_free()


func damage(n: int) -> void:
	if ended:
		return
	health -= n
	play_sfx("bite")
	flash_rect.color.a = 0.45
	if health < 1:
		end_game("EATEN BY CARROTS")


func teleport() -> void:
	if money < 3 or ended:
		return
	money -= 3
	play_sfx("teleport")
	_place_player(rand_floor_cell())


func use_stairs(delta: int) -> void:
	if stairs_lock > 0 or ended:
		return
	depth += delta
	seed_v += delta
	if depth > 99:
		end_game("YOU WIN!")
		return
	play_sfx("stairs")
	gen()
	build_level()
	_place_player(up_cell if delta == 1 else down_cell)


func end_game(title: String) -> void:
	ended = true
	play_sfx("win" if title == "YOU WIN!" else "lose")
	end_title.text = title
	end_stats.text = "Gold: %d    Floor: %d" % [money, depth]
	end_layer.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func restart() -> void:
	ended = false
	end_layer.visible = false
	seed_v = randi() & 0x7fffffff
	depth = 0
	money = 0
	health = MAXHP
	gens = 0
	gen()
	build_level()
	_place_player(rand_floor_cell())
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func set_paused(p: bool) -> void:
	if ended:
		return
	game_paused = p
	pause_layer.visible = p
	get_tree().paused = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not ended:
		if game_paused:
			set_paused(false)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE, KEY_P:
				if not ended:
					set_paused(not game_paused)
			KEY_T:
				if not game_paused and not ended:
					teleport()
			KEY_M:
				minimap.visible = not minimap.visible


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not ended and not game_paused:
		set_paused(true)


@warning_ignore("integer_division")
func _process(delta: float) -> void:
	if not game_paused and not ended and was_captured \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		set_paused(true)
	was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if flash_rect.color.a > 0:
		flash_rect.color.a = maxf(0.0, flash_rect.color.a - delta * 1.5)
	if game_paused or ended:
		return
	stairs_lock = maxf(0.0, stairs_lock - delta)
	regen_accum += delta
	if regen_accum >= REGEN_S:
		regen_accum = 0.0
		if health < MAXHP:
			health += 1
	var prow := int(player.position.z / CELL)
	var pcol := int(player.position.x / CELL)
	hud_stats.text = "HP [%s%s]   Gold %d   Floor %d" % [
		"#".repeat(maxi(health, 0)), "-".repeat(MAXHP - maxi(health, 0)), money, depth]
	hud_save.text = "Save " + save_token()
	if minimap.visible:
		minimap.queue_redraw()


func _build_ui() -> void:
	var hud := CanvasLayer.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.8, 0.0, 0.0, 0.0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash_rect)

	hud_stats = Label.new()
	hud_stats.position = Vector2(16, 12)
	hud_stats.add_theme_font_size_override("font_size", 22)
	hud.add_child(hud_stats)

	hud_save = Label.new()
	hud_save.position = Vector2(16, 40)
	hud_save.add_theme_font_size_override("font_size", 13)
	hud_save.modulate = Color(1, 1, 1, 0.6)
	hud.add_child(hud_save)

	var hint := Label.new()
	hint.text = "click to capture mouse · WASD move · mouse looks · T teleport (3 gold) · M map · Esc pause"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(16, -34)
	hint.add_theme_font_size_override("font_size", 15)
	hint.modulate = Color(1, 1, 1, 0.55)
	hud.add_child(hint)

	minimap = Control.new()
	minimap.set_script(load("res://minimap.gd"))
	minimap.main = self
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-416, 12)
	minimap.custom_minimum_size = Vector2(400, 120)
	minimap.visible = false
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(minimap)

	pause_layer = _menu_layer("PAUSED", "Mouse released while paused",
			"Resume", func(): set_paused(false))
	end_layer = CanvasLayer.new()
	end_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	end_layer.visible = false
	add_child(end_layer)
	var panel := _menu_panel()
	end_layer.add_child(panel)
	end_title = Label.new()
	end_title.add_theme_font_size_override("font_size", 42)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.get_node("vbox").add_child(end_title)
	end_stats = Label.new()
	end_stats.add_theme_font_size_override("font_size", 20)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.get_node("vbox").add_child(end_stats)
	var again := Button.new()
	again.text = "Play again"
	again.pressed.connect(restart)
	panel.get_node("vbox").add_child(again)
	panel.get_node("vbox").add_child(_source_button())


func _menu_panel() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	vbox.name = "vbox"
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dim.add_child(vbox)
	return dim


func _menu_layer(title: String, subtitle: String, btn_text: String, btn_fn: Callable) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.visible = false
	add_child(layer)
	var panel := _menu_panel()
	layer.add_child(panel)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 42)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.get_node("vbox").add_child(t)
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_font_size_override("font_size", 16)
	sub.modulate = Color(1, 1, 1, 0.7)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.get_node("vbox").add_child(sub)
	var b := Button.new()
	b.text = btn_text
	b.pressed.connect(btn_fn)
	panel.get_node("vbox").add_child(b)
	var cp := Button.new()
	cp.text = "Copy save"
	cp.pressed.connect(func(): DisplayServer.clipboard_set(save_token()))
	panel.get_node("vbox").add_child(cp)
	var paste := LineEdit.new()
	paste.placeholder_text = "paste a save here"
	paste.select_all_on_focus = true
	paste.custom_minimum_size = Vector2(340, 0)
	paste.alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.get_node("vbox").add_child(paste)
	var ld := Button.new()
	ld.text = "Load save"
	ld.pressed.connect(func():
		if apply_save(paste.text):
			paste.text = ""
			set_paused(false))
	panel.get_node("vbox").add_child(ld)
	var cl := Button.new()
	cl.text = "Copy link with save"
	cl.pressed.connect(func(): DisplayServer.clipboard_set(
			str(JavaScriptBridge.eval("location.origin+location.pathname", true))
			+ "?save=" + save_token().uri_encode()))
	panel.get_node("vbox").add_child(cl)
	panel.get_node("vbox").add_child(_source_button())
	return layer


func _source_button() -> Button:
	var b := Button.new()
	b.text = "Source code"
	b.pressed.connect(func(): OS.shell_open("https://github.com/adipascu/carrot-crawler-3d"))
	return b


func selftest() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var checks := []
	checks.append(["walls built", level_root.get_child_count() >= 4])
	checks.append(["coins spawned", coins.size() == entity_count()])
	checks.append(["enemies spawned", enemies.size() == entity_count()])
	var c := coins[0]
	player.global_position = c.global_position - Vector3(0, 1.0, 0)
	for _i in 20:
		await get_tree().physics_frame
	checks.append(["coin collected", money == 1])
	money = 3
	var before := player.global_position
	teleport()
	checks.append(["teleport moved player", player.global_position.distance_to(before) > 0.01])
	checks.append(["teleport cost", money == 0])
	stairs_lock = 0.0
	var d0 := depth
	player.global_position = cell_pos(down_cell)
	for _i in 20:
		await get_tree().physics_frame
	checks.append(["stairs descended", depth == d0 + 1])
	var foe: Node3D = enemies[0]
	player.global_position = foe.global_position + Vector3(1.0, 0, 0)
	var hp0 := health
	var foe_pos := foe.global_position
	set_paused(true)
	for _i in 90:
		await get_tree().physics_frame
	checks.append(["enemies frozen while paused",
			foe.global_position.distance_to(foe_pos) < 0.001])
	checks.append(["no damage while paused", health == hp0])
	set_paused(false)
	checks.append(["apply_save imports", apply_save(":1:00:0a:0c:28:00:")
			and seed_v == 1 and depth == 0
			and int(player.position.z / CELL) == 12
			and int(player.position.x / CELL) == 40])
	damage(99)
	checks.append(["death ends game", ended and end_title.text == "EATEN BY CARROTS"])
	get_tree().paused = false
	var all_ok := true
	for chk in checks:
		print("%s: %s" % [chk[0], "OK" if chk[1] else "FAIL"])
		if not chk[1]:
			all_ok = false
	print("SELFTEST %s" % ("PASSED" if all_ok else "FAILED"))
	get_tree().quit(0 if all_ok else 1)
