extends Node3D

## 起動シーン。ルールエンジンの初期配置を 3D 盤に載せ、オービットカメラで眺める。
## 駒の移動操作はまだない(Issue #5)。

func _ready() -> void:
	_setup_environment()
	_setup_light()

	var board_view := BoardView.new()
	add_child(board_view)
	board_view.build_from(Board.chess_start())

	var orbit := OrbitCamera.new()
	orbit.name = "OrbitCamera"
	add_child(orbit)


func _setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.55
	world_env.environment = env
	add_child(world_env)


func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
