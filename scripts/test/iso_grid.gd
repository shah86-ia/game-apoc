@tool
class_name IsoGrid
extends Node2D
## Временная изометрическая сетка для тестовой сцены.
## Рисуется программно через _draw(), спрайты не нужны.
## @tool — сетку видно прямо в редакторе.

## Размер одного ромба (ширина × высота). 2:1 — классическая пиксельная изометрия.
@export var tile_size: Vector2 = Vector2(64, 32):
	set(value):
		tile_size = value
		queue_redraw()

## Сколько клеток в каждую сторону от центра.
@export_range(1, 200) var half_extent: int = 30:
	set(value):
		half_extent = value
		queue_redraw()

@export var ground_color: Color = Color(0.20, 0.21, 0.18):
	set(value):
		ground_color = value
		queue_redraw()

@export var line_color: Color = Color(0.36, 0.38, 0.32):
	set(value):
		line_color = value
		queue_redraw()

## Цвет осей, проходящих через центр, — помогает видеть направление.
@export var axis_color: Color = Color(0.62, 0.52, 0.30):
	set(value):
		axis_color = value
		queue_redraw()


## Перевод координат клетки (x, y) в экранные координаты.
func cell_to_screen(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * tile_size.x * 0.5, (cell.x + cell.y) * tile_size.y * 0.5)


func _draw() -> void:
	var n := float(half_extent)

	# Подложка-ромб под всю сетку.
	draw_colored_polygon(PackedVector2Array([
		cell_to_screen(Vector2(-n, -n)),
		cell_to_screen(Vector2(n, -n)),
		cell_to_screen(Vector2(n, n)),
		cell_to_screen(Vector2(-n, n)),
	]), ground_color)

	# Две группы диагональных линий образуют ромбы.
	for i in range(-half_extent, half_extent + 1):
		var color := axis_color if i == 0 else line_color
		var width := 2.0 if i == 0 else 1.0
		draw_line(cell_to_screen(Vector2(i, -n)), cell_to_screen(Vector2(i, n)), color, width)
		draw_line(cell_to_screen(Vector2(-n, i)), cell_to_screen(Vector2(n, i)), color, width)
