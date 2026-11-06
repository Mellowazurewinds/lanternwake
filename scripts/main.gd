extends Node2D

## Lanternwake: a seeded twilight platforming voyage.

const VIEW_SIZE := Vector2(1152.0, 648.0)
const LEVEL_COUNT := 3
const PLAYER_SIZE := Vector2(30.0, 46.0)
const NEW_WORLD_BUTTON := Rect2(938.0, 76.0, 196.0, 34.0)
const PAUSE_BUTTON := Rect2(938.0, 116.0, 196.0, 32.0)
const RUN_SPEED := 310.0
const GRAVITY := 1550.0
const JUMP_SPEED := -650.0
const BIOME_NAMES := ["EMBER DUSK", "BLUE HOUR", "MINT AURORA"]
const PALETTES := [
	{"top": Color("17192f"), "bottom": Color("df795f"), "far": Color("65506f"), "mid": Color("403b61"), "near": Color("272d4a"), "glow": Color("ffd18a")},
	{"top": Color("10263e"), "bottom": Color("86aebe"), "far": Color("557a98"), "mid": Color("365b78"), "near": Color("203f5d"), "glow": Color("d2f5f0")},
	{"top": Color("182c43"), "bottom": Color("8bc6ad"), "far": Color("557f78"), "mid": Color("3b675d"), "near": Color("244b4b"), "glow": Color("e5ffb4")}
]

var world_seed: int = 731204
var level_number := 1
var level_width := 4650.0
var exit_position := Vector2.ZERO
var biome_index: int = 0
var player_position := Vector2(110.0, 455.0)
var checkpoint_position := Vector2(110.0, 477.0)
var player_velocity := Vector2.ZERO
var platforms: Array[Rect2] = []
var route_platform_indices: Array[int] = []
var moving_platforms: Array[Dictionary] = []
var crumble_platform_indices: Array[int] = []
var crumble_timers: Dictionary = {}
var echo_lights: Array[Dictionary] = []
var storm_motes: Array[Dictionary] = []
var collected := 0
var hearts := 3
var invulnerability := 0.0
var world_time := 0.0
var game_state := "playing"
var grounded := false
var font: Font
var camera_x := 0.0
var facing := 1.0
var _reset_key_was_down := false
var _button_rects: Dictionary = {}
var biome_picker_return_state := "paused"
var biome_picker_previous_index := 0

func _ready() -> void:
	font = ThemeDB.fallback_font
	_build_level()
	game_state = "menu"

func _physics_process(delta: float) -> void:
	world_time += delta
	if game_state == "playing" and Input.is_key_pressed(KEY_R) and not _reset_key_was_down:
		_reset_key_was_down = true
		_generate_new_world()
	elif not Input.is_key_pressed(KEY_R):
		_reset_key_was_down = false

	if game_state == "playing":
		_advance_platform_features(delta)
		var horizontal := float(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A))
		if horizontal != 0.0:
			facing = signf(horizontal)
		player_velocity.x = horizontal * RUN_SPEED
		if grounded and (Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)):
			player_velocity.y = JUMP_SPEED
			grounded = false
		player_velocity.y = minf(player_velocity.y + GRAVITY * delta, 1050.0)
		var previous_feet := player_position.y + PLAYER_SIZE.y * 0.5
		player_position.x = clampf(player_position.x + player_velocity.x * delta, PLAYER_SIZE.x * 0.5, level_width - PLAYER_SIZE.x * 0.5)
		player_position.y += player_velocity.y * delta
		grounded = false
		if player_velocity.y >= 0.0:
			var current_feet := player_position.y + PLAYER_SIZE.y * 0.5
			for platform_index in range(platforms.size()):
				var platform: Rect2 = platforms[platform_index]
				if platform.size.x <= 0.0:
					continue
				var overlaps_x := player_position.x + PLAYER_SIZE.x * 0.5 > platform.position.x and player_position.x - PLAYER_SIZE.x * 0.5 < platform.end.x
				if overlaps_x and previous_feet <= platform.position.y and current_feet >= platform.position.y:
					player_position.y = platform.position.y - PLAYER_SIZE.y * 0.5
					player_velocity.y = 0.0
					grounded = true
					if platform_index in crumble_platform_indices:
						if not crumble_timers.has(platform_index):
							crumble_timers[platform_index] = 0.0
					elif not _is_moving_platform(platform_index):
						checkpoint_position = player_position
					break
		if player_position.y > VIEW_SIZE.y + 130.0:
			_lose_heart()
		invulnerability = maxf(0.0, invulnerability - delta)
		_check_collisions()
		if grounded and player_position.x >= exit_position.x:
			game_state = "won" if level_number >= LEVEL_COUNT else "level_complete"
		camera_x = clampf(player_position.x - VIEW_SIZE.x * 0.38, 0.0, level_width - VIEW_SIZE.x)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for button_id in _button_rects.keys():
			if _button_rects[button_id].has_point(event.position):
				_activate_button(String(button_id))
				get_viewport().set_input_as_handled()
				return

func _generate_new_world() -> void:
	var old_seed := world_seed
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	world_seed = rng.randi_range(1, 999999)
	if world_seed == old_seed:
		world_seed = world_seed % 999999 + 1
	var next_biome := rng.randi_range(0, BIOME_NAMES.size() - 2)
	if next_biome >= biome_index:
		next_biome += 1
	biome_index = next_biome
	level_number = 1
	hearts = 3
	_build_level()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if game_state == "playing":
			game_state = "paused"
		elif game_state == "paused":
			game_state = "playing"
		elif game_state == "biome_picker":
			biome_index = biome_picker_previous_index
			game_state = biome_picker_return_state
	elif event.keycode == KEY_ENTER:
		if game_state == "menu":
			_start_selected_world()
		elif game_state == "biome_picker":
			_start_new_biome()
		elif game_state == "level_complete":
			_continue_to_next_level()
		elif game_state == "won" or game_state == "lost":
			_restart_campaign()
	queue_redraw()

func _activate_button(button_id: String) -> void:
	if button_id.begins_with("biome_"):
		biome_index = int(button_id.get_slice("_", 1))
	elif button_id == "start":
		_start_selected_world()
	elif button_id == "reroll_seed":
		var previous_state := game_state
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		world_seed = rng.randi_range(1, 999999)
		_build_level()
		game_state = previous_state
	elif button_id == "pause":
		game_state = "paused"
	elif button_id == "resume":
		game_state = "playing"
	elif button_id == "restart_level":
		hearts = 3
		_build_level()
	elif button_id == "pick_biome":
		biome_picker_return_state = game_state
		biome_picker_previous_index = biome_index
		game_state = "biome_picker"
	elif button_id == "back_from_picker":
		biome_index = biome_picker_previous_index
		game_state = biome_picker_return_state
	elif button_id == "new_biome_start":
		_start_new_biome()
	elif button_id == "main_menu":
		game_state = "menu"
	elif button_id == "continue":
		_continue_to_next_level()
	elif button_id == "restart_campaign":
		_restart_campaign()
	elif button_id == "new_world":
		_generate_new_world()
	elif button_id == "quit":
		get_tree().quit()
	queue_redraw()

func _start_selected_world() -> void:
	level_number = 1
	hearts = 3
	_build_level()

func _start_new_biome() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	world_seed = rng.randi_range(1, 999999)
	level_number = 1
	hearts = 3
	_build_level()

func _continue_to_next_level() -> void:
	level_number += 1
	_build_level()

func _restart_campaign() -> void:
	level_number = 1
	hearts = 3
	_build_level()

func _build_level() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + level_number * 100003 + biome_index * 300007
	player_position = Vector2(110.0, 455.0)
	checkpoint_position = Vector2(110.0, 477.0)
	player_velocity = Vector2.ZERO
	camera_x = 0.0
	grounded = false
	collected = 0
	invulnerability = 0.0
	game_state = "playing"
	platforms.clear()
	route_platform_indices.clear()
	moving_platforms.clear()
	crumble_platform_indices.clear()
	crumble_timers.clear()
	echo_lights.clear()
	storm_motes.clear()
	platforms.append(Rect2(0.0, 500.0, 570.0, 34.0))
	route_platform_indices.append(0)
	var next_x := 650.0
	var previous_y := 500.0
	var platform_index := 0
	while next_x < 3700.0:
		var platform_width := rng.randf_range(270.0 - level_number * 18.0, 330.0 - level_number * 18.0)
		var next_y := clampf(previous_y + rng.randf_range(-78.0 - level_number * 8.0, 78.0 + level_number * 8.0), 290.0, 500.0)
		var platform := Rect2(next_x, next_y, platform_width, 28.0)
		platforms.append(platform)
		var platform_id := platforms.size() - 1
		route_platform_indices.append(platform_id)
		var light_x := next_x + platform_width * rng.randf_range(0.35, 0.68)
		echo_lights.append({"position": Vector2(light_x, next_y - 48.0), "phase": rng.randf_range(0.0, TAU), "collected": false})
		if platform_index % 3 == 1:
			var ledge_width := rng.randf_range(112.0, 146.0)
			var ledge_y := next_y - rng.randf_range(78.0, 112.0)
			platforms.append(Rect2(next_x + platform_width * 0.24, ledge_y, ledge_width, 18.0))
			echo_lights.append({"position": Vector2(next_x + platform_width * 0.24 + ledge_width * 0.5, ledge_y - 38.0), "phase": rng.randf_range(0.0, TAU), "collected": false})
		if level_number >= 2 and platform_index % 4 == 2:
			moving_platforms.append({"index": platform_id, "base_x": next_x, "base_y": next_y, "phase": rng.randf_range(0.0, TAU), "amplitude": 18.0 + level_number * 7.0, "rate": 0.85 + level_number * 0.12, "horizontal": level_number >= 3 and platform_index % 2 == 0})
		if level_number >= 3 and platform_index % 5 == 3:
			crumble_platform_indices.append(platform_id)
		next_x += platform_width + rng.randf_range(90.0 + level_number * 10.0, 132.0 + level_number * 15.0)
		previous_y = next_y
		platform_index += 1
	var final_platform_x := next_x + rng.randf_range(90.0 + level_number * 10.0, 132.0 + level_number * 15.0)
	platforms.append(Rect2(final_platform_x, previous_y, 360.0, 30.0))
	route_platform_indices.append(platforms.size() - 1)
	level_width = final_platform_x + 420.0
	exit_position = Vector2(final_platform_x + 315.0, previous_y - PLAYER_SIZE.y * 0.5)
	for index in range(mini(3 + level_number, route_platform_indices.size() - 2)):
		var platform: Rect2 = platforms[route_platform_indices[mini(2 + index * 2, route_platform_indices.size() - 1)]]
		storm_motes.append({"position": Vector2(platform.position.x + platform.size.x * 0.5, platform.position.y - 42.0), "phase": rng.randf_range(0.0, TAU), "radius": rng.randf_range(24.0, 46.0)})
	queue_redraw()

func _advance_platform_features(delta: float) -> void:
	for feature in moving_platforms:
		var index: int = feature["index"]
		var platform: Rect2 = platforms[index]
		var previous_position := platform.position
		var phase := world_time * float(feature["rate"]) + float(feature["phase"])
		platform.position.y = float(feature["base_y"]) + sin(phase) * float(feature["amplitude"])
		if feature["horizontal"]:
			platform.position.x = float(feature["base_x"]) + cos(phase * 0.7) * 38.0
		if grounded and absf(player_position.y + PLAYER_SIZE.y * 0.5 - previous_position.y) < 4.0 and player_position.x >= previous_position.x - PLAYER_SIZE.x * 0.5 and player_position.x <= previous_position.x + platforms[index].size.x + PLAYER_SIZE.x * 0.5:
			player_position += platform.position - previous_position
		platforms[index] = platform
	for key in crumble_timers.keys():
		crumble_timers[key] = float(crumble_timers[key]) + delta
		if float(crumble_timers[key]) >= 1.15:
			var platform: Rect2 = platforms[int(key)]
			platform.size.x = 0.0
			platforms[int(key)] = platform
			crumble_timers.erase(key)

func _check_collisions() -> void:
	for light in echo_lights:
		if not light["collected"] and player_position.distance_to(light["position"]) < 38.0:
			light["collected"] = true
			collected += 1
	for mote in storm_motes:
		var drift: Vector2 = Vector2(sin(world_time * 0.8 + mote["phase"]), cos(world_time * 0.6 + mote["phase"])) * float(mote["radius"])
		if invulnerability <= 0.0 and player_position.distance_to(mote["position"] + drift) < 34.0:
			_lose_heart()
			break

func _lose_heart() -> void:
	if invulnerability > 0.0:
		return
	hearts -= 1
	invulnerability = 1.5
	if hearts <= 0:
		game_state = "lost"
	else:
		player_position = checkpoint_position
		player_velocity = Vector2.ZERO
		grounded = false

func _draw() -> void:
	_button_rects.clear()
	var palette: Dictionary = PALETTES[biome_index]
	_draw_sky(palette)
	_draw_stars()
	_draw_biome_details(palette)
	_draw_ridge(0.10, 365.0, 92.0, palette["far"], 91)
	_draw_ridge(0.22, 430.0, 72.0, palette["mid"], 173)
	_draw_ridge(0.38, 492.0, 49.0, palette["near"], 281)
	_draw_platforms(palette)
	_draw_world_objects(palette)
	_draw_exit(palette)
	_draw_hero(palette)
	_draw_atmosphere_overlay(palette)
	_draw_hud(palette)
	_draw_menu_ui(palette)

func _draw_sky(palette: Dictionary) -> void:
	var top: Color = palette["top"]
	var bottom: Color = palette["bottom"]
	for band in range(54):
		var ratio := float(band) / 53.0
		draw_rect(Rect2(0.0, ratio * VIEW_SIZE.y, VIEW_SIZE.x, VIEW_SIZE.y / 53.0 + 1.0), top.lerp(bottom, ratio))
	var glow: Color = palette["glow"]
	var sun := Vector2(925.0, 160.0)
	for halo in range(7, 0, -1):
		var radius := 32.0 + halo * 13.0
		draw_circle(sun, radius, Color(glow, 0.018 + (7.0 - halo) * 0.006))
	draw_circle(sun, 33.0, glow)
	draw_circle(sun + Vector2(-9.0, -10.0), 8.0, Color.WHITE)
	# Soft horizon haze gives the silhouettes more separation from the sky.
	for band in range(16):
		var alpha := 0.025 * (1.0 - float(band) / 16.0)
		draw_rect(Rect2(0.0, 320.0 + band * 8.0, VIEW_SIZE.x, 9.0), Color(glow, alpha))
	_draw_distant_clouds(palette)

func _draw_distant_clouds(palette: Dictionary) -> void:
	var cloud_color: Color = palette["far"].lightened(0.42)
	for cloud_index in range(5):
		var x := fposmod(float(cloud_index) * 278.0 - camera_x * 0.055 + 110.0, VIEW_SIZE.x)
		var y := 205.0 + float((cloud_index * 43) % 78)
		var cloud_width := 82.0 + float((cloud_index * 31) % 55)
		draw_circle(Vector2(x, y), 13.0, Color(cloud_color, 0.16))
		draw_circle(Vector2(x + 20.0, y - 5.0), 17.0, Color(cloud_color, 0.16))
		draw_circle(Vector2(x + 41.0, y), 12.0, Color(cloud_color, 0.16))
		draw_rect(Rect2(x - 5.0, y, cloud_width, 10.0), Color(cloud_color, 0.12))

func _draw_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 92341
	for index in range(110):
		var star := Vector2(rng.randf_range(0.0, VIEW_SIZE.x), rng.randf_range(20.0, 345.0))
		var screen_star := Vector2(fposmod(star.x - camera_x * 0.08, VIEW_SIZE.x), star.y)
		var size := rng.randf_range(0.8, 2.0)
		var brightness := 0.52 + 0.38 * (0.5 + 0.5 * sin(world_time * rng.randf_range(0.4, 1.5) + index))
		draw_circle(screen_star, size, Color(0.85, 0.91, 1.0, brightness))
		if size > 1.65:
			draw_line(screen_star - Vector2(4.0, 0.0), screen_star + Vector2(4.0, 0.0), Color(0.85, 0.91, 1.0, brightness * 0.5), 1.0)
			draw_line(screen_star - Vector2(0.0, 4.0), screen_star + Vector2(0.0, 4.0), Color(0.85, 0.91, 1.0, brightness * 0.5), 1.0)

func _draw_biome_details(palette: Dictionary) -> void:
	var accent: Color = palette["glow"]
	if biome_index == 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed + 72017
		for index in range(40):
			var ember_x := fposmod(rng.randf_range(0.0, VIEW_SIZE.x) - camera_x * 0.24 + world_time * rng.randf_range(5.0, 18.0), VIEW_SIZE.x)
			var ember_y := fposmod(rng.randf_range(80.0, 470.0) - world_time * rng.randf_range(4.0, 13.0), 470.0) + 40.0
			draw_circle(Vector2(ember_x, ember_y), rng.randf_range(1.0, 2.6), Color("ffb26d", rng.randf_range(0.28, 0.75)))
	elif biome_index == 1:
		for index in range(5):
			var x := fposmod(float(index) * 287.0 - camera_x * 0.16 + 120.0, VIEW_SIZE.x)
			var y := 116.0 + float((index * 71) % 150)
			draw_line(Vector2(x, y), Vector2(x + 35.0, y + 12.0), Color(accent, 0.35), 1.0)
			draw_line(Vector2(x + 35.0, y + 12.0), Vector2(x + 77.0, y - 4.0), Color(accent, 0.35), 1.0)
			draw_circle(Vector2(x, y), 2.0, accent)
			draw_circle(Vector2(x + 35.0, y + 12.0), 2.0, accent)
			draw_circle(Vector2(x + 77.0, y - 4.0), 2.0, accent)
	else:
		for ribbon in range(3):
			var points := PackedVector2Array()
			for sample in range(49):
				var x := float(sample) * 25.0
				var y := 115.0 + ribbon * 34.0 + sin(x * 0.009 + world_time * 0.28 + ribbon) * 24.0
				points.append(Vector2(x, y))
			draw_polyline(points, Color(accent, 0.22 - ribbon * 0.035), 5.0 - ribbon)

func _draw_ridge(parallax: float, base_y: float, amplitude: float, color: Color, salt: int) -> void:
	const SAMPLE_SPACING := 110.0
	var offset := camera_x * parallax
	var first_sample := int(floor((offset - VIEW_SIZE.x * 0.5) / SAMPLE_SPACING)) - 1
	var last_sample := int(ceil((offset + VIEW_SIZE.x * 0.5) / SAMPLE_SPACING)) + 1
	var points := PackedVector2Array()
	var first_x := first_sample * SAMPLE_SPACING - offset + VIEW_SIZE.x * 0.5
	points.append(Vector2(first_x, base_y))
	for sample_index in range(first_sample, last_sample + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed + salt + sample_index * 1877
		var screen_x := sample_index * SAMPLE_SPACING - offset + VIEW_SIZE.x * 0.5
		points.append(Vector2(screen_x, base_y - rng.randf_range(amplitude * 0.2, amplitude)))
	var last_x := last_sample * SAMPLE_SPACING - offset + VIEW_SIZE.x * 0.5
	points.append(Vector2(last_x, base_y))
	points.append(Vector2(last_x, VIEW_SIZE.y))
	points.append(Vector2(first_x, VIEW_SIZE.y))
	draw_colored_polygon(points, color)

func _draw_platforms(palette: Dictionary) -> void:
	var stone: Color = palette["near"].lightened(0.14)
	if biome_index == 0:
		stone = Color("56404d")
	elif biome_index == 1:
		stone = Color("355467")
	else:
		stone = Color("34594d")
	var top_color: Color = palette["glow"].darkened(0.24)
	for platform_index in range(platforms.size()):
		var platform: Rect2 = platforms[platform_index]
		if platform.size.x <= 0.0:
			continue
		var screen_rect := Rect2(platform.position.x - camera_x, platform.position.y, platform.size.x, platform.size.y)
		if screen_rect.end.x < -20.0 or screen_rect.position.x > VIEW_SIZE.x + 20.0:
			continue
		# Deep undersides and a highlight lip make the stepping stones read as chunky 3D forms.
		draw_rect(Rect2(screen_rect.position.x + 3.0, screen_rect.end.y, screen_rect.size.x - 2.0, 7.0), Color("101526", 0.46))
		draw_rect(screen_rect, stone)
		for bevel in range(5):
			draw_rect(Rect2(screen_rect.position.x, screen_rect.position.y + bevel, screen_rect.size.x, 1.0), Color(top_color, 0.74 - bevel * 0.11))
		draw_line(Vector2(screen_rect.position.x + 5.0, screen_rect.end.y - 2.0), Vector2(screen_rect.end.x - 5.0, screen_rect.end.y - 2.0), Color("11172b", 0.55), 2.0)
		if biome_index == 0:
			for seam in range(int(platform.size.x / 48.0)):
				var seam_x := screen_rect.position.x + 30.0 + seam * 48.0
				draw_line(Vector2(seam_x, screen_rect.position.y + 8.0), Vector2(seam_x - 5.0, screen_rect.position.y + 25.0), Color("29273c", 0.8), 2.0)
			if platform_index % 3 == 1:
				draw_line(Vector2(screen_rect.position.x + 15.0, screen_rect.position.y), Vector2(screen_rect.position.x + 20.0, screen_rect.position.y - 18.0), Color("db775e"), 3.0)
		elif biome_index == 1:
			var crystal_x := screen_rect.position.x + screen_rect.size.x * 0.72
			draw_colored_polygon(PackedVector2Array([Vector2(crystal_x - 8.0, screen_rect.position.y), Vector2(crystal_x, screen_rect.position.y - 25.0), Vector2(crystal_x + 8.0, screen_rect.position.y)]), Color("a6d7df"))
			draw_colored_polygon(PackedVector2Array([Vector2(crystal_x + 9.0, screen_rect.position.y), Vector2(crystal_x + 17.0, screen_rect.position.y - 16.0), Vector2(crystal_x + 23.0, screen_rect.position.y)]), Color("76b8ce"))
		else:
			for tuft in range(int(platform.size.x / 58.0)):
				var tuft_x := screen_rect.position.x + 24.0 + tuft * 58.0
				draw_line(Vector2(tuft_x, screen_rect.position.y + 3.0), Vector2(tuft_x - 4.0, screen_rect.position.y - 8.0), Color("a6ca83"), 3.0)
				draw_line(Vector2(tuft_x, screen_rect.position.y + 3.0), Vector2(tuft_x + 5.0, screen_rect.position.y - 6.0), Color("83b987"), 3.0)
		if _is_moving_platform(platform_index):
			var rail_y := screen_rect.position.y + screen_rect.size.y * 0.5
			draw_rect(Rect2(screen_rect.position.x - 5.0, screen_rect.position.y - 7.0, screen_rect.size.x + 10.0, 3.0), Color(top_color, 0.23))
			draw_line(Vector2(screen_rect.position.x + 10.0, rail_y), Vector2(screen_rect.position.x + 10.0, rail_y + 8.0), top_color, 2.0)
			draw_line(Vector2(screen_rect.end.x - 10.0, rail_y), Vector2(screen_rect.end.x - 10.0, rail_y + 8.0), top_color, 2.0)
		if platform_index in crumble_platform_indices:
			var warning := 0.0
			if crumble_timers.has(platform_index):
				warning = clampf(float(crumble_timers[platform_index]) / 1.15, 0.0, 1.0)
			var crack_color := Color("f3a27d", 0.45 + warning * 0.5)
			draw_line(Vector2(screen_rect.position.x + screen_rect.size.x * 0.42, screen_rect.position.y + 5.0), Vector2(screen_rect.position.x + screen_rect.size.x * 0.48, screen_rect.position.y + 14.0), crack_color, 2.0)
			draw_line(Vector2(screen_rect.position.x + screen_rect.size.x * 0.48, screen_rect.position.y + 14.0), Vector2(screen_rect.position.x + screen_rect.size.x * 0.45, screen_rect.position.y + 25.0), crack_color, 2.0)

func _draw_world_objects(palette: Dictionary) -> void:
	var glow: Color = palette["glow"]
	for mote in storm_motes:
		var drift: Vector2 = Vector2(sin(world_time * 0.8 + mote["phase"]), cos(world_time * 0.6 + mote["phase"])) * float(mote["radius"])
		var point := _to_screen(mote["position"] + drift)
		if _on_screen(point, 60.0):
			var pulse := 1.0 + 0.08 * sin(world_time * 4.0 + mote["phase"])
			draw_circle(point, 33.0 * pulse, Color("625878", 0.10))
			draw_arc(point, 25.0 * pulse, world_time + mote["phase"], world_time + mote["phase"] + PI * 1.35, 28, Color("aa8bb3", 0.58), 2.0)
			draw_arc(point, 21.0, -world_time * 1.4 + mote["phase"], -world_time * 1.4 + mote["phase"] + PI * 1.25, 28, Color("81749e", 0.62), 1.5)
			draw_circle(point, 17.0, Color("171729"))
			draw_circle(point + Vector2(-5.0, -3.0), 3.0, Color("d6b8ce", 0.85))
			draw_circle(point + Vector2(4.0, 4.0), 2.0, Color("8b7197", 0.9))
	for light in echo_lights:
		if light["collected"]:
			continue
		var point := _to_screen(light["position"])
		if _on_screen(point, 38.0):
			var pulse := 1.0 + 0.12 * sin(world_time * 3.0 + light["phase"])
			draw_circle(point, 27.0 * pulse, Color(glow, 0.08))
			draw_circle(point, 17.0 * pulse, Color(glow, 0.18))
			draw_arc(point, 13.0 * pulse, world_time, world_time + PI * 1.5, 28, Color(glow, 0.7), 1.5)
			draw_line(point - Vector2(18.0, 0.0), point - Vector2(12.0, 0.0), Color(glow, 0.68), 1.0)
			draw_line(point + Vector2(12.0, 0.0), point + Vector2(18.0, 0.0), Color(glow, 0.68), 1.0)
			draw_colored_polygon(PackedVector2Array([point + Vector2(0.0, -12.0), point + Vector2(8.0, 0.0), point + Vector2(0.0, 12.0), point + Vector2(-8.0, 0.0)]), glow)
			draw_circle(point, 3.0, Color.WHITE)

func _draw_exit(palette: Dictionary) -> void:
	var point := _to_screen(exit_position)
	var glow: Color = palette["glow"]
	var pulse := 1.0 + sin(world_time * 2.2) * 0.08
	draw_rect(Rect2(point.x - 30.0, point.y - 52.0, 60.0, 65.0), Color(glow, 0.04))
	draw_circle(point, 47.0 * pulse, Color(glow, 0.08))
	draw_circle(point, 34.0 * pulse, Color(glow, 0.13))
	draw_circle(point, 23.0, Color(glow, 0.3))
	draw_arc(point, 29.0, PI, TAU, 40, glow, 5.0)
	draw_arc(point, 20.0, 0.0, TAU, 40, Color.WHITE, 1.5)
	draw_line(point + Vector2(-29.0, 0.0), point + Vector2(-29.0, 14.0), glow, 6.0)
	draw_line(point + Vector2(29.0, 0.0), point + Vector2(29.0, 14.0), glow, 6.0)
	for spark in range(5):
		var angle := world_time * 0.8 + float(spark) * TAU / 5.0
		var spark_point := point + Vector2(cos(angle), sin(angle)) * 38.0
		draw_circle(spark_point, 2.0, Color.WHITE)

func _draw_hero(palette: Dictionary) -> void:
	var point := _to_screen(player_position) + Vector2(0.0, 2.0 * sin(world_time * 9.0) if grounded else 0.0)
	if invulnerability > 0.0 and int(world_time * 14.0) % 2 == 0:
		return
	var cloth: Color = palette["glow"]
	var step := sin(world_time * 12.0) * 4.0 if grounded and absf(player_velocity.x) > 0.0 else 0.0
	var cape_tip := point + Vector2(-facing * (23.0 + 3.0 * sin(world_time * 7.0)), 10.0)
	_draw_ellipse(point + Vector2(0.0, 25.0), Vector2(19.0, 5.0), Color("111527", 0.38))
	# Wind-swept travel cape, with a lighter inner fold.
	draw_colored_polygon(PackedVector2Array([point + Vector2(-8.0 * facing, -7.0), point + Vector2(8.0 * facing, -8.0), cape_tip, point + Vector2(-11.0 * facing, 14.0)]), Color("57465f"))
	draw_line(point + Vector2(-8.0 * facing, -1.0), cape_tip + Vector2(0.0, -2.0), Color("8a6376", 0.72), 2.0)
	# Boots and robe silhouette.
	draw_line(point + Vector2(-6.0, 14.0), point + Vector2(-8.0 + step, 23.0), Color("29283e"), 5.0)
	draw_line(point + Vector2(6.0, 14.0), point + Vector2(8.0 - step, 23.0), Color("29283e"), 5.0)
	draw_line(point + Vector2(-10.0 + step, 23.0), point + Vector2(-4.0 + step, 23.0), Color("d4b18e"), 3.0)
	draw_line(point + Vector2(5.0 - step, 23.0), point + Vector2(11.0 - step, 23.0), Color("d4b18e"), 3.0)
	draw_colored_polygon(PackedVector2Array([point + Vector2(-10.0, -9.0), point + Vector2(10.0, -9.0), point + Vector2(15.0, 17.0), point + Vector2(-15.0, 17.0)]), Color("35415a"))
	draw_colored_polygon(PackedVector2Array([point + Vector2(-7.0, -4.0), point + Vector2(0.0, 0.0), point + Vector2(7.0, -4.0), point + Vector2(10.0, 14.0), point + Vector2(-10.0, 14.0)]), Color("4c586b"))
	draw_line(point + Vector2(-10.0, 5.0), point + Vector2(10.0, 5.0), Color("d5b482", 0.78), 2.0)
	# Head, hood, and face turned in the travel direction.
	draw_circle(point + Vector2(0.0, -17.0), 10.0, Color("d7a887"))
	draw_colored_polygon(PackedVector2Array([point + Vector2(-12.0, -16.0), point + Vector2(-8.0, -28.0), point + Vector2(0.0, -33.0), point + Vector2(10.0, -27.0), point + Vector2(13.0, -14.0), point + Vector2(7.0, -18.0), point + Vector2(-5.0, -18.0)]), Color("29253d"))
	draw_line(point + Vector2(3.0 * facing, -16.0), point + Vector2(7.0 * facing, -16.0), Color("362b3b"), 2.0)
	# Lantern glow, handle and glass body.
	var lantern := point + Vector2(13.0 * facing, 1.0)
	draw_circle(lantern, 17.0, Color(cloth, 0.13))
	draw_line(point + Vector2(8.0 * facing, -3.0), lantern + Vector2(0.0, -4.0), Color("d9c4a2"), 2.0)
	draw_arc(lantern + Vector2(0.0, -1.0), 5.0, PI, TAU, 16, Color("d8c49f"), 1.5)
	draw_rect(Rect2(lantern + Vector2(-4.0, -1.0), Vector2(8.0, 10.0)), Color("765c58"))
	draw_rect(Rect2(lantern + Vector2(-2.0, 1.0), Vector2(4.0, 6.0)), cloth)
	draw_circle(lantern + Vector2(0.0, 4.0), 2.0, Color.WHITE)

func _draw_atmosphere_overlay(palette: Dictionary) -> void:
	# A gentle edge falloff keeps the bright play area focused without hiding hazards.
	for band in range(10):
		var alpha := 0.018 * (1.0 - float(band) / 10.0)
		draw_rect(Rect2(0.0, band * 8.0, VIEW_SIZE.x, 8.0), Color(palette["top"], alpha))
		draw_rect(Rect2(0.0, VIEW_SIZE.y - (band + 1) * 8.0, VIEW_SIZE.x, 8.0), Color("101426", alpha * 1.4))
		var side_alpha := alpha * 0.8
		draw_rect(Rect2(band * 8.0, 0.0, 8.0, VIEW_SIZE.y), Color("101426", side_alpha))
		draw_rect(Rect2(VIEW_SIZE.x - (band + 1) * 8.0, 0.0, 8.0, VIEW_SIZE.y), Color("101426", side_alpha))

func _draw_hud(palette: Dictionary) -> void:
	draw_rect(Rect2(18.0, 18.0, 490.0, 94.0), Color(0.045, 0.055, 0.12, 0.78))
	draw_rect(Rect2(18.0, 18.0, 4.0, 94.0), palette["glow"])
	draw_string(font, Vector2(34.0, 48.0), "LANTERNWAKE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("fff0d5"))
	draw_string(font, Vector2(34.0, 81.0), "LEVEL %d / %d    ECHOES %02d" % [level_number, LEVEL_COUNT, collected], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d6d8e6"))
	draw_rect(Rect2(34.0, 94.0, 234.0, 4.0), Color("ffffff", 0.16))
	draw_rect(Rect2(34.0, 94.0, 234.0 * clampf(player_position.x / level_width, 0.0, 1.0), 4.0), palette["glow"])
	for heart in range(3):
		var heart_color := Color("ffb27c") if heart < hearts else Color(0.42, 0.40, 0.50, 0.6)
		_draw_heart(Vector2(360.0 + heart * 34.0, 72.0), heart_color)
	draw_string(font, Vector2(894.0, 40.0), "SEED %06d" % world_seed, HORIZONTAL_ALIGNMENT_RIGHT, 240.0, 16, Color("fff0d5"))
	draw_string(font, Vector2(894.0, 64.0), BIOME_NAMES[biome_index], HORIZONTAL_ALIGNMENT_RIGHT, 240.0, 14, Color("d8e1ed"))
	if game_state == "playing":
		_draw_button("new_world", NEW_WORLD_BUTTON, "NEW WORLD  [R]", palette)
		_draw_button("pause", PAUSE_BUTTON, "PAUSE  [ESC]", palette)
	draw_string(font, Vector2(24.0, 628.0), "A / D OR ARROWS  RUN     SPACE / W / UP  JUMP     ESC  PAUSE", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f7e6d1"))

func _draw_menu_ui(palette: Dictionary) -> void:
	if game_state == "playing":
		return
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color(0.025, 0.035, 0.09, 0.76))
	if game_state == "menu" or game_state == "biome_picker":
		var choosing_initial_world := game_state == "menu"
		var panel := Rect2(184.0, 54.0, 784.0, 540.0)
		draw_rect(panel, Color(0.055, 0.065, 0.13, 0.96))
		draw_rect(panel, Color(palette["glow"], 0.72), false, 2.0)
		var heading := "LANTERNWAKE" if choosing_initial_world else "CHOOSE A NEW BIOME"
		draw_string(font, Vector2(panel.position.x, 104.0), heading, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 34, Color("fff0d5"))
		var subtitle := "PICK A WORLD FOR YOUR VOYAGE" if choosing_initial_world else "YOUR CURRENT LEVEL WILL RESTART WITH A NEW WORLD"
		draw_string(font, Vector2(panel.position.x, 138.0), subtitle, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 15, Color("d8e1ed"))
		for index in range(BIOME_NAMES.size()):
			var card := Rect2(220.0 + index * 240.0, 176.0, 224.0, 152.0)
			_draw_biome_card(index, card, palette)
		if choosing_initial_world:
			_draw_button("start", Rect2(414.0, 352.0, 324.0, 54.0), "START VOYAGE", palette)
			_draw_button("reroll_seed", Rect2(414.0, 421.0, 324.0, 42.0), "NEW SEED   %06d" % world_seed, palette)
			_draw_button("quit", Rect2(480.0, 478.0, 192.0, 42.0), "QUIT", palette)
		else:
			_draw_button("new_biome_start", Rect2(414.0, 376.0, 324.0, 54.0), "START NEW WORLD", palette)
			var back_label := "BACK TO PAUSE MENU" if biome_picker_return_state == "paused" else "BACK"
			_draw_button("back_from_picker", Rect2(414.0, 447.0, 324.0, 44.0), back_label, palette)
	elif game_state == "paused":
		var panel := Rect2(330.0, 66.0, 492.0, 520.0)
		draw_rect(panel, Color(0.055, 0.065, 0.13, 0.97))
		draw_rect(panel, Color(palette["glow"], 0.72), false, 2.0)
		draw_string(font, Vector2(panel.position.x, 122.0), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 34, Color("fff0d5"))
		draw_string(font, Vector2(panel.position.x, 154.0), "%s  |  LEVEL %d" % [BIOME_NAMES[biome_index], level_number], HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 16, Color("d8e1ed"))
		_draw_button("resume", Rect2(420.0, 184.0, 312.0, 48.0), "RESUME   [ESC]", palette)
		_draw_button("restart_level", Rect2(420.0, 242.0, 312.0, 48.0), "RESTART LEVEL", palette)
		_draw_button("pick_biome", Rect2(420.0, 300.0, 312.0, 48.0), "PICK A NEW BIOME", palette)
		_draw_button("main_menu", Rect2(420.0, 358.0, 312.0, 48.0), "MAIN MENU", palette)
		_draw_button("quit", Rect2(420.0, 416.0, 312.0, 48.0), "QUIT GAME", palette)
	elif game_state == "level_complete":
		_draw_result_panel("LEVEL %d COMPLETE" % level_number, "ECHOES COLLECTED: %02d" % collected, "continue", "CONTINUE TO LEVEL %d" % (level_number + 1), palette)
	elif game_state == "won":
		_draw_result_panel("THE SKY REMEMBERS", "YOU REACHED THE END OF THE VOYAGE", "restart_campaign", "PLAY AGAIN", palette)
		_draw_button("pick_biome", Rect2(420.0, 446.0, 312.0, 44.0), "PICK A NEW BIOME", palette)
		_draw_button("quit", Rect2(420.0, 500.0, 312.0, 40.0), "QUIT", palette)
	elif game_state == "lost":
		_draw_result_panel("THE STORM FOUND YOU", "YOUR VOYAGE ENDS HERE", "restart_campaign", "RESTART CAMPAIGN", palette)
		_draw_button("pick_biome", Rect2(420.0, 446.0, 312.0, 44.0), "PICK A NEW BIOME", palette)
		_draw_button("quit", Rect2(420.0, 500.0, 312.0, 40.0), "QUIT", palette)

func _draw_result_panel(title: String, subtitle: String, button_id: String, button_text: String, palette: Dictionary) -> void:
	var panel := Rect2(310.0, 150.0, 532.0, 430.0)
	draw_rect(panel, Color(0.055, 0.065, 0.13, 0.97))
	draw_rect(panel, Color(palette["glow"], 0.72), false, 2.0)
	draw_string(font, Vector2(panel.position.x, 226.0), title, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 29, palette["glow"])
	draw_string(font, Vector2(panel.position.x, 266.0), subtitle, HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 15, Color("d8e1ed"))
	_draw_button(button_id, Rect2(420.0, 374.0, 312.0, 52.0), button_text, palette)

func _draw_biome_card(index: int, rect: Rect2, palette: Dictionary) -> void:
	var selected := biome_index == index
	var biome: Dictionary = PALETTES[index]
	draw_rect(rect, Color(biome["top"], 0.96))
	draw_rect(rect, Color(palette["glow"], 0.95) if selected else Color(0.78, 0.82, 0.91, 0.58), false, 3.0 if selected else 1.0)
	var preview := Rect2(rect.position + Vector2(9.0, 9.0), Vector2(rect.size.x - 18.0, 68.0))
	for band in range(12):
		var ratio := float(band) / 11.0
		draw_rect(Rect2(preview.position.x, preview.position.y + ratio * preview.size.y, preview.size.x, preview.size.y / 11.0 + 1.0), biome["top"].lerp(biome["bottom"], ratio * 0.72))
	draw_circle(preview.position + Vector2(preview.size.x * 0.78, 21.0), 13.0, Color(biome["glow"], 0.24))
	draw_circle(preview.position + Vector2(preview.size.x * 0.78, 21.0), 8.0, biome["glow"])
	draw_colored_polygon(PackedVector2Array([
		preview.position + Vector2(0.0, 48.0),
		preview.position + Vector2(47.0, 24.0),
		preview.position + Vector2(82.0, 48.0),
		preview.position + Vector2(132.0, 20.0),
		preview.position + Vector2(preview.size.x, 49.0),
		preview.position + Vector2(preview.size.x, preview.size.y),
		preview.position + Vector2(0.0, preview.size.y)
	]), biome["far"])
	draw_rect(Rect2(preview.position.x + 30.0, preview.end.y - 9.0, preview.size.x - 52.0, 9.0), biome["near"])
	draw_rect(Rect2(preview.position.x + 30.0, preview.end.y - 9.0, preview.size.x - 52.0, 2.0), biome["glow"])
	draw_circle(preview.position + Vector2(preview.size.x * 0.45, preview.size.y - 20.0), 4.0, Color.WHITE)
	draw_string(font, rect.position + Vector2(0.0, 94.0), BIOME_NAMES[index], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 17, Color("fff0d5"))
	var descriptions := ["CINDERS & RUIN STONE", "CONSTELLATIONS & ICE", "AURORA & MOSS PATHS"]
	draw_string(font, rect.position + Vector2(0.0, 123.0), descriptions[index], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11, Color("d8e1ed"))
	_button_rects["biome_%d" % index] = rect

func _draw_button(button_id: String, rect: Rect2, label: String, palette: Dictionary) -> void:
	draw_rect(rect, Color(palette["near"], 0.96))
	draw_rect(Rect2(rect.position.x + 3.0, rect.end.y - 4.0, rect.size.x - 6.0, 3.0), Color("111527", 0.5))
	draw_rect(rect, Color(palette["glow"], 0.82), false, 2.0)
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.67), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color("fff0d5"))
	_button_rects[button_id] = rect

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for step_index in range(25):
		var angle := TAU * float(step_index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)

func _draw_heart(center: Vector2, color: Color) -> void:
	draw_circle(center + Vector2(-5.0, -2.0), 7.0, color)
	draw_circle(center + Vector2(5.0, -2.0), 7.0, color)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-12.0, 0.0), center + Vector2(12.0, 0.0), center + Vector2(0.0, 14.0)]), color)

func _is_moving_platform(platform_index: int) -> bool:
	for feature in moving_platforms:
		if int(feature["index"]) == platform_index:
			return true
	return false

func _to_screen(world_position: Vector2) -> Vector2:
	return world_position - Vector2(camera_x, 0.0)

func _on_screen(point: Vector2, margin: float) -> bool:
	return point.x > -margin and point.x < VIEW_SIZE.x + margin and point.y > -margin and point.y < VIEW_SIZE.y + margin
