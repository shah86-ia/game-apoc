class_name OcclusionManager
extends Node
## Универсальная прозрачность объектов, которые закрывают героя.
##
## Один такой узел на сцену обслуживает все объекты из группы `occludable`.
## Объекту не нужен свой скрипт: достаточно добавить его в группу.
##
## Объект становится полупрозрачным, только если его видимые части, которые рисуются
## ПОЗЖЕ героя (порядок Y-sort), закрывают заметную долю непрозрачных пикселей
## текущего кадра героя (порог min_coverage). Считаются реальные пиксели:
## у полигонов — их форма, у спрайтов — непрозрачные пиксели картинки.
## Коллизия и дистанция до героя не используются.
##
## Параметры конкретного объекта можно переопределить метаданными
## (Инспектор → Metadata → Add Metadata):
##   occlusion_alpha       (float) — непрозрачность при перекрытии;
##   occlusion_fade_time   (float) — время перехода, сек;
##   occlusion_min_coverage (float) — своя доля закрытого героя для включения;
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

## Какая доля непрозрачных пикселей героя должна быть закрыта объектом, чтобы он стал
## полупрозрачным (0.25 = четверть силуэта). Выключается при доле вдвое меньше — без мерцания.
@export_range(0.0, 1.0, 0.01) var min_coverage: float = 0.25

## Шаг выборки пикселей героя (в пикселях текстуры). Меньше — точнее, но дороже.
@export_range(1, 16, 1) var sample_step: int = 3

## Последняя посчитанная доля перекрытия по объекту (для отладки и тестов).
var last_coverage: Dictionary = {}

## Состояние по каждому объекту: { Node: {targets, alphas, occluded, release_timer} }.
var _states: Dictionary = {}
## Кэш непрозрачной области кадров: { [Texture2D, Rect2]: Rect2 }.
var _used_rect_cache: Dictionary = {}
## Кэш распакованных изображений: { Texture2D: Image }.
var _image_cache: Dictionary = {}
## Кэш выборки непрозрачных пикселей кадра героя: { Texture2D: PackedVector2Array }.
var _sample_cache: Dictionary = {}


func _process(delta: float) -> void:
	if target_sprite == null or not is_instance_valid(target_sprite):
		return

	var hero_poly := _target_polygon()
	var hero_samples := _target_samples()
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
		var threshold: float = obj.get_meta(&"occlusion_min_coverage", min_coverage)
		var coverage := _coverage(st.targets, hero_poly, hero_samples, hero_sort_y) if enabled else 0.0
		last_coverage[obj] = coverage
		# Гистерезис: включаем на пороге, держим, пока покрытие не упадёт вдвое.
		var now_occluding := coverage >= threshold if not st.occluded else coverage >= threshold * 0.5

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
			last_coverage.erase(obj)


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


## Доля непрозрачных пикселей героя (0…1), закрытых видимыми частями объекта,
## которые рисуются позже героя.
func _coverage(targets: Array, hero_poly: PackedVector2Array, samples: PackedVector2Array, hero_sort_y: float) -> float:
	if samples.is_empty():
		return 0.0
	# Части объекта, которые рисуются позже героя и хотя бы грубо пересекают его силуэт.
	var parts: Array[Dictionary] = []
	for t in targets:
		if is_instance_valid(t) and t.is_visible_in_tree():
			_collect_parts(t, parts)
	var front: Array[Dictionary] = []
	for part in parts:
		if part.key > hero_sort_y and not Geometry2D.intersect_polygons(part.bounds, hero_poly).is_empty():
			front.append(part)
	if front.is_empty():
		return 0.0
	var covered := 0
	for g in samples:
		for part in front:
			if _part_covers(part, g):
				covered += 1
				break
	return float(covered) / samples.size()


## Собирает видимые части узла и его потомков: ключ сортировки, грубая рамка
## в глобальных координатах и сам узел (для попиксельной проверки).
func _collect_parts(node: Node, out: Array[Dictionary]) -> void:
	if node is CanvasItem and not node.visible:
		return
	var bounds := PackedVector2Array()
	if node is Polygon2D and node.polygon.size() >= 3:
		var xf: Transform2D = node.global_transform.translated_local(node.offset)
		bounds = xf * node.polygon
	elif node is Sprite2D and node.texture:
		var r: Rect2 = node.get_rect()
		if node.hframes == 1 and node.vframes == 1:
			var region: Rect2 = node.region_rect if node.region_enabled else Rect2()
			var used := _used_rect(node.texture, region)
			r = Rect2(r.position + used.position, used.size)
		bounds = _rect_to_global(node, r)
	elif node is AnimatedSprite2D and node.sprite_frames:
		var tex: Texture2D = node.sprite_frames.get_frame_texture(node.animation, node.frame)
		if tex:
			var size := tex.get_size()
			var origin: Vector2 = node.offset - (size / 2.0 if node.centered else Vector2.ZERO)
			var used := _used_rect(tex)
			bounds = _rect_to_global(node, Rect2(origin + used.position, used.size))
	if bounds.size() >= 3 and _area(bounds) > 0.0:
		out.append({"key": _sort_key(node), "bounds": bounds, "node": node})
	for child in node.get_children():
		if not (child is CollisionShape2D or child is CollisionPolygon2D or child is CollisionObject2D):
			_collect_parts(child, out)


## Закрывает ли видимая часть точку g (глобальные координаты): форма полигона
## или непрозрачный пиксель картинки.
func _part_covers(part: Dictionary, g: Vector2) -> bool:
	var node: Node = part.node
	if node is Polygon2D:
		return Geometry2D.is_point_in_polygon(g, part.bounds)
	var tex: Texture2D
	var rect: Rect2
	var src_origin := Vector2.ZERO
	if node is Sprite2D:
		tex = node.texture
		rect = node.get_rect()
		if node.region_enabled:
			src_origin = node.region_rect.position
	elif node is AnimatedSprite2D:
		tex = node.sprite_frames.get_frame_texture(node.animation, node.frame)
		var size := tex.get_size()
		rect = Rect2(node.offset - (size / 2.0 if node.centered else Vector2.ZERO), size)
	else:
		return false
	var local: Vector2 = (node as CanvasItem).get_global_transform().affine_inverse() * g
	if not rect.has_point(local):
		return false
	var img := _image(tex)
	if img == null:
		return true
	var px := Vector2i(src_origin + (local - rect.position))
	px = px.clamp(Vector2i.ZERO, img.get_size() - Vector2i.ONE)
	return img.get_pixelv(px).a > 0.5


## Ключ Y-sort: позиция того предка, который участвует в сортировке.
## Узел сортируется своей позицией, если его родитель — Y-sort; иначе рисуется вместе с родителем.
func _sort_key(node: Node) -> float:
	var n := node
	while n.get_parent() is CanvasItem and not (n.get_parent() as CanvasItem).y_sort_enabled:
		n = n.get_parent()
	return (n as Node2D).global_position.y if n is Node2D else 0.0


## Рамка непрозрачной части кадра героя (для быстрой отсечки далёких объектов).
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
	# Небольшой запас, чтобы грубая проверка не отсекала касание по краю.
	var grown := Geometry2D.offset_polygon(poly, 2.0)
	return grown[0] if not grown.is_empty() else poly


## Непрозрачные пиксели текущего кадра героя (с шагом sample_step) в глобальных координатах.
func _target_samples() -> PackedVector2Array:
	var s := target_sprite
	var tex: Texture2D = s.sprite_frames.get_frame_texture(s.animation, s.frame)
	if tex == null:
		return PackedVector2Array()
	if not _sample_cache.has(tex):
		var pts := PackedVector2Array()
		var img := _image(tex)
		if img:
			var used := img.get_used_rect()
			for y in range(used.position.y, used.end.y, sample_step):
				for x in range(used.position.x, used.end.x, sample_step):
					if img.get_pixel(x, y).a > 0.5:
						pts.append(Vector2(x + 0.5, y + 0.5))
		_sample_cache[tex] = pts
	var size := tex.get_size()
	var origin: Vector2 = s.offset - (size / 2.0 if s.centered else Vector2.ZERO)
	var xf := s.get_global_transform().translated_local(origin)
	return xf * (_sample_cache[tex] as PackedVector2Array)


func _image(tex: Texture2D) -> Image:
	if _image_cache.has(tex):
		return _image_cache[tex]
	var img := tex.get_image()
	if img and img.is_compressed():
		img.decompress()
	_image_cache[tex] = img
	return img


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5


## Прямоугольник непрозрачных пикселей кадра (считается один раз на текстуру).
## Если задан region (спрайт показывает часть текстуры) — только внутри него,
## в координатах этого региона.
func _used_rect(tex: Texture2D, region: Rect2 = Rect2()) -> Rect2:
	var key := [tex, region]
	if _used_rect_cache.has(key):
		return _used_rect_cache[key]
	var full := region.has_area()
	var r := Rect2(Vector2.ZERO, region.size if full else tex.get_size())
	var img := _image(tex)
	if img:
		if full:
			img = img.get_region(Rect2i(region))
		r = Rect2(img.get_used_rect())
	_used_rect_cache[key] = r
	return r


func _rect_to_global(node: CanvasItem, r: Rect2) -> PackedVector2Array:
	var xf: Transform2D = node.get_global_transform()
	return PackedVector2Array([
		xf * r.position,
		xf * Vector2(r.end.x, r.position.y),
		xf * r.end,
		xf * Vector2(r.position.x, r.end.y),
	])
