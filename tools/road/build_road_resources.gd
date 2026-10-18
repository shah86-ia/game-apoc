extends SceneTree
## Сборщик дорожного TileSet (и, по флагу, слоёв дороги уровня 01) из результатов build_road_tiles.py.
##
## Запуск из корня проекта (после python tools/road/build_road_tiles.py [--level]):
##   godot --headless --path . --import
##   godot --headless --path . -s tools/road/build_road_resources.gd              # только TileSet
##   godot --headless --path . -s tools/road/build_road_resources.gd -- level     # + Level01.tscn
##
## ВНИМАНИЕ: сборка с флагом level перезаписывает levels/level-01-arrival/Level01.tscn целиком,
## включая ручные правки дорог, разметки, положения героя и все расставленные объекты (остановка, дом).
## Для правок дорог на готовом уровне пользуйтесь редактором Godot, а не этой сборкой.

const TILES_JSON := "res://tools/road/out/road_tiles.json"
const LEVEL_JSON := "res://tools/road/out/level01_cells.json"
const TILESET_PATH := "res://assets/tilesets/road/road_tileset.tres"
const ROAD_TEXTURE := "res://assets/tilesets/road/road-tiles-v001.png"
const MARKINGS_TEXTURE := "res://assets/tilesets/road/road-markings-v001.png"
const ROAD_MATERIAL := "res://assets/tilesets/road/road_asphalt_material.tres"
const PLAYER_SCENE := "res://characters/protagonist/Player.tscn"
const LEVEL_PATH := "res://levels/level-01-arrival/Level01.tscn"

const SOURCE_ROAD := 0
const SOURCE_MARKINGS := 1

## Слои ставятся со сдвигом (−32, 0): тогда северный угол клетки (x, y) лежит в
## ((x − y)·32, (x + y)·16) — как у сетки тестовой сцены.
const LAYER_OFFSET := Vector2(-32, 0)


func _init() -> void:
	var tiles: Array = _read_json(TILES_JSON)["tiles"]
	var tile_set := _build_tileset(tiles)
	var err := ResourceSaver.save(tile_set, TILESET_PATH)
	print("TileSet: ", TILESET_PATH, " err=", err)
	if "level" in OS.get_cmdline_user_args():
		_build_level()
	quit()


func _read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _build_tileset(tiles: Array) -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(64, 32)

	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	ts.add_terrain(0)
	ts.set_terrain_name(0, 0, "Асфальт")
	ts.set_terrain_color(0, 0, Color(0.85, 0.55, 0.2))

	var road := TileSetAtlasSource.new()
	road.resource_name = "Дорога"
	road.texture = load(ROAD_TEXTURE)
	road.texture_region_size = Vector2i(64, 32)
	ts.add_source(road, SOURCE_ROAD)

	var corner_bits := {
		1: TileSet.CELL_NEIGHBOR_TOP_CORNER,
		2: TileSet.CELL_NEIGHBOR_RIGHT_CORNER,
		4: TileSet.CELL_NEIGHBOR_BOTTOM_CORNER,
		8: TileSet.CELL_NEIGHBOR_LEFT_CORNER,
	}
	for t in tiles:
		var coords := Vector2i(int(t["x"]), int(t["y"]))
		road.create_tile(coords)
		if t.has("bits"):
			# Тайл автотайлинга «Асфальт»: асфальт в отмеченных углах.
			var td := road.get_tile_data(coords, 0)
			td.terrain_set = 0
			td.terrain = 0
			var bits := int(t["bits"])
			for b in corner_bits:
				if bits & b:
					td.set_terrain_peering_bit(corner_bits[b], 0)

	var marks := TileSetAtlasSource.new()
	marks.resource_name = "Разметка"
	marks.texture = load(MARKINGS_TEXTURE)
	marks.texture_region_size = Vector2i(64, 32)
	ts.add_source(marks, SOURCE_MARKINGS)
	for i in 4:
		marks.create_tile(Vector2i(i, 0))
	return ts


func _build_level() -> void:
	var data := _read_json(LEVEL_JSON)
	var tile_set: TileSet = load(TILESET_PATH)

	var root := Node2D.new()
	root.name = "Level01"

	var ground := Node2D.new()
	ground.name = "Ground"
	_add(root, root, ground)

	var road := TileMapLayer.new()
	road.name = "Road"
	road.tile_set = tile_set
	road.material = load(ROAD_MATERIAL)
	road.position = LAYER_OFFSET
	for c in data["road"]:
		road.set_cell(Vector2i(int(c[0]), int(c[1])), SOURCE_ROAD, Vector2i(int(c[2]), int(c[3])))
	_add(root, ground, road)

	var marks := TileMapLayer.new()
	marks.name = "RoadMarkings"
	marks.tile_set = tile_set
	marks.position = LAYER_OFFSET
	for c in data["marks"]:
		marks.set_cell(Vector2i(int(c[0]), int(c[1])), SOURCE_MARKINGS, Vector2i(int(c[2]), int(c[3])))
	_add(root, ground, marks)

	var start_cell := Vector2i(int(data["player_start_cell"][0]), int(data["player_start_cell"][1]))
	var start_pos := road.map_to_local(start_cell) + LAYER_OFFSET

	var markers := Node2D.new()
	markers.name = "Markers"
	_add(root, root, markers)
	var player_start := Marker2D.new()
	player_start.name = "PlayerStart"
	player_start.position = start_pos
	_add(root, markers, player_start)

	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	_add(root, root, world)
	var player: Node2D = (load(PLAYER_SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	player.name = "Player"
	player.position = start_pos
	_add(root, world, player)

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, LEVEL_PATH)
	print("Level01: ", LEVEL_PATH, " err=", err, " road=", data["road"].size(), " marks=", data["marks"].size(),
			" start=", start_pos)
	root.free()


func _add(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root
