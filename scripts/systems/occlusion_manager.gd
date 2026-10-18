class_name OcclusionManager
extends Node
## Универсальная прозрачность объектов, которые закрывают героя.
##
## Один такой узел на сцену обслуживает все объекты из группы `occludable`.
## Объекту не нужен свой скрипт: достаточно добавить его в группу.
##
## Объект становится полупрозрачным, только если одновременно:
##   1) хотя бы одна его видимая часть рисуется ПОЗЖЕ героя (порядок Y-sort);
##   2) видимая форма этой части (полигоны / спрайты, а не коллизия)
##      пересекается с непрозрачной частью текущего кадра героя.
##
## Параметры конкретного объекта можно переопределить метаданными
## (Инспектор → Metadata → Add Metadata):
##   occlusion_alpha       (float) — непрозрачность при перекрытии;
##   occlusion_fade_time   (float) — время перехода, сек;
##   occlusion_enabled     (bool)  — false временно отключает объект.
##
## Прозрачность меняется через modulate у визуальных дочерних узлов объекта
## (Polygon2D, Sprite2D, контейнеры Node2D…). Физическое тело и коллизии не трогаются.

const GROUP := &"occludable"

## Спрайт героя, которого нужно «открывать». Обычно Player/AnimatedSprite2D.
@export var target_sprite: AnimatedSprite2D

## Непрозрачность объекта, когда он закрывает героя.
@export_range(0.0, 1.0, 0.01) var occluded_alpha: float = 0.35

## Время перехода между обычной и полупрозрачной непрозрачностью, сек.
@export_range(0.0, 2.0, 0.01) var fade_time: float = 0.2

## Задержка перед возвратом непрозрачности, сек. Гасит мерцание на краях,
## когда силуэт героя меняется от кадра к кадру анимации.
@export_range(0.0, 1.0, 0.01) var release_delay: float = 0.1

## Расширение контура героя в пикселях при проверке (запас вокруг силуэта).
@export var target_margin: float = 2.0

## Состояние по каждому объекту: { Node: {targets, alphas, occluded, release_timer} }.
var _states: Dictionary = {}
## Кэш непрозрачной области кадров: { Texture2D: Rect2 }.
var _used_rect_cache: Dictionary = {}


func _process(delta: float) -> void:
	if target_sprite == null or not is_instance_valid(target_sprite):
		return

	var hero_poly := _target_polygon()
	var hero_sort_y := _sort_key(target_sprite)

	var alive := {}
	for obj in get_tree().get_nodes_in_group(GROUP):
		if not (obj is Node2D):
			continue
		alive[obj] = true
		var st: Dictionary = _states.get(obj, {})
		if st.is_empty():
			st = _register(obj)
			_states[obj] = st

		var enabled: bool = obj.get_meta(&"occlusion_enabled", true)
		var now_occluding := enabled and _is_occluding(st.targets, hero_poly, hero_sort_y)

		if now_occluding:
			st.occluded = true
			st.release_timer = release_delay
		elif st.occluded:
			st.release_timer -= delta
			if st.release_timer <= 0.0:
				st.occluded = false

		var alpha_occ: float = obj.get_meta(&"occlusion_alpha", occluded_alpha)
		var time: float = obj.get_meta(&"occlusion_fade_time", fade_time)
		for i in st.targets.size():
			var t: CanvasItem = st.targets[i]
			if not is_instance_valid(t):
				continue
			var base: float = st.alphas[i]
			var goal := minf(base, alpha_occ) if st.occluded else base
			var step := absf(base - alpha_occ) / maxf(time, 0.001) * delta
			t.modulate.a = move_toward(t.modulate.a, goal, step)

	# Объекты, удалённые из группы или со сцены, возвращаем в исходное состояние.
	for obj in _states.keys():
		if not alive.has(obj):
			_restore(obj)
			_states.erase(obj)


## Запоминает визуальные части объекта и их исходную непрозрачность.
func _register(obj: Node) -> Dictionary:
	var targets: Array[CanvasItem] = []
	var alphas: Array[float] = []
	for child in obj.get_children():
		if child is CanvasItem and not (child is CollisionShape2D or child is CollisionPolygon2D \
				or child is CollisionObject2D):
			targets.append(child)
			alphas.append(child.modulate.a)
	return {"targets": targets, "alphas": alphas, "occluded": false, "release_timer": 0.0}


func _restore(obj: Node) -> void:
	if not is_instance_valid(obj):
		return
	var st: Dictionary = _states[obj]
	for i in st.targets.size():
		if is_instance_valid(st.targets[i]):
			st.targets[i].modulate.a = st.alphas[i]


## true, если хоть одна видимая часть рисуется позже героя и закрывает его силуэт.
func _is_occluding(targets: Array, hero_poly: PackedVector2Array, hero_sort_y: float) -> bool:
	for t in targets:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		var shapes: Array[PackedVector2Array] = []
		_collect_shapes(t, shapes)
		# shapes: [ключ сортировки (в .y первой точки), полигон, ключ, полигон, …]
		for i in range(0, shapes.size(), 2):
			var sort_y := shapes[i][0].y
			if sort_y <= hero_sort_y:
				continue # эта часть рисуется раньше героя — не закрывает
			if not Geometry2D.intersect_polygons(shapes[i + 1], hero_poly).is_empty():
				return true
	return false


## Собирает видимые формы узла и его потомков в глобальных координатах,
## парами: [ключ сортировки, полигон].
func _collect_shapes(node: Node, out: Array[PackedVector2Array]) -> void:
	if node is CanvasItem and not node.visible:
		return
	var poly := PackedVector2Array()
	if node is Polygon2D and node.polygon.size() >= 3:
		var xf: Transform2D = node.global_transform.translated_local(node.offset)
		poly = xf * node.polygon
	elif node is Sprite2D and node.texture:
		var r: Rect2 = node.get_rect()
		if not node.region_enabled and node.hframes == 1 and node.vframes == 1:
			var used := _used_rect(node.texture)
			r = Rect2(r.position + used.position, used.size)
		poly = _rect_to_global(node, r)
	elif node is AnimatedSprite2D and node.sprite_frames:
		var tex: Texture2D = node.sprite_frames.get_frame_texture(node.animation, node.frame)
		if tex:
			var size := tex.get_size()
			var origin: Vector2 = node.offset - (size / 2.0 if node.centered else Vector2.ZERO)
			var used := _used_rect(tex)
			poly = _rect_to_global(node, Rect2(origin + used.position, used.size))
	if poly.size() >= 3:
		out.append(PackedVector2Array([Vector2(0.0, _sort_key(node))]))
		out.append(poly)
	for child in node.get_children():
		if not (child is CollisionShape2D or child is CollisionPolygon2D or child is CollisionObject2D):
			_collect_shapes(child, out)


## Ключ Y-sort: позиция того предка, который участвует в сортировке.
## Узел сортируется своей позицией, если его родитель — Y-sort; иначе рисуется вместе с родителем.
func _sort_key(node: Node) -> float:
	var n := node
	while n.get_parent() is CanvasItem and not (n.get_parent() as CanvasItem).y_sort_enabled:
		n = n.get_parent()
	return (n as Node2D).global_position.y if n is Node2D else 0.0


## Непрозрачная часть текущего кадра героя в глобальных координатах (с запасом).
func _target_polygon() -> PackedVector2Array:
	var s := target_sprite
	var tex: Texture2D = s.sprite_frames.get_frame_texture(s.animation, s.frame)
	if tex == null:
		return PackedVector2Array()
	var used: Rect2 = _used_rect(tex)
	var size := tex.get_size()
	var origin: Vector2 = s.offset - (size / 2.0 if s.centered else Vector2.ZERO)
	var local := Rect2(origin + used.position, used.size)
	var poly := _rect_to_global(s, local)
	if target_margin > 0.0:
		var grown := Geometry2D.offset_polygon(poly, target_margin)
		if not grown.is_empty():
			return grown[0]
	return poly


## Прямоугольник непрозрачных пикселей кадра (считается один раз на текстуру).
func _used_rect(tex: Texture2D) -> Rect2:
	if _used_rect_cache.has(tex):
		return _used_rect_cache[tex]
	var r := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img:
		if img.is_compressed():
			img.decompress()
		r = Rect2(img.get_used_rect())
	_used_rect_cache[tex] = r
	return r


func _rect_to_global(node: CanvasItem, r: Rect2) -> PackedVector2Array:
	var xf: Transform2D = node.get_global_transform()
	return PackedVector2Array([
		xf * r.position,
		xf * Vector2(r.end.x, r.position.y),
		xf * r.end,
		xf * Vector2(r.position.x, r.end.y),
	])
