class_name Player
extends CharacterBody2D
## Главный герой. Управление WASD относительно экрана.
## Точка начала координат узла — ноги персонажа (точка опоры).
## Внешний вид — дочерний AnimatedSprite2D с ресурсом SpriteFrames.

## Скорость перемещения в пикселях в секунду.
@export var move_speed: float = 120.0

## Доля от move_speed, ниже которой герой считается стоящим (упёрся в стену).
@export_range(0.0, 1.0, 0.01) var min_walk_speed_ratio: float = 0.15

## Суффиксы направлений по часовой стрелке, начиная с востока (угол 0 в Godot).
const DIRECTION_SUFFIXES: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

## Последнее направление взгляда — сохраняется после остановки.
var facing: StringName = &"s"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_update_animation()


func _physics_process(_delta: float) -> void:
	# get_vector() уже ограничивает длину вектора единицей,
	# поэтому по диагонали скорость та же, что и по прямой.
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

	# Без инерции: скорость задаётся напрямую и сразу обнуляется при отпускании клавиш.
	velocity = direction * move_speed
	move_and_slide()

	# Поворачиваемся только при вводе; без ввода остаётся последнее направление.
	if direction != Vector2.ZERO:
		facing = _direction_to_suffix(direction)

	# Ходьбу показываем по фактической скорости после столкновений:
	# если герой упёрся в препятствие, он стоит в Idle, а не шагает на месте.
	# При скольжении вдоль стены скорость ненулевая — ходьба продолжается.
	var is_moving := get_real_velocity().length() > move_speed * min_walk_speed_ratio
	_update_animation(is_moving)


## Переводит вектор движения в одно из 8 направлений (секторы по 45°).
func _direction_to_suffix(direction: Vector2) -> StringName:
	var index := wrapi(roundi(direction.angle() / (PI / 4.0)), 0, 8)
	return DIRECTION_SUFFIXES[index]


## При движении включает walk_<направление>, если такая анимация уже есть в SpriteFrames;
## иначе (и при остановке) — idle_<направление>.
func _update_animation(is_moving: bool = false) -> void:
	var anim := StringName("idle_" + facing)
	if is_moving:
		var walk_anim := StringName("walk_" + facing)
		if sprite.sprite_frames.has_animation(walk_anim):
			anim = walk_anim
	if sprite.animation != anim:
		sprite.play(anim)

