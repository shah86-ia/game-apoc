class_name Player
extends CharacterBody2D
## Главный герой. Управление WASD относительно экрана, Shift — бег.
## Точка начала координат узла — ноги персонажа (точка опоры).
## Внешний вид — дочерний AnimatedSprite2D с ресурсом SpriteFrames.
## FPS анимаций (walk_* — 8, run_* — 10) задаются в SpriteFrames, а не здесь.

## Скорость ходьбы в пикселях в секунду.
@export var move_speed: float = 120.0

## Скорость бега = move_speed × этот множитель (Shift + WASD).
@export_range(1.0, 3.0, 0.05) var run_speed_multiplier: float = 1.6

## Насколько быстро скорость меняется между ходьбой и бегом, пикс/с².
## Чем больше, тем резче переход; при 300 разгон 120 → 192 занимает ≈ 0,25 с.
@export var speed_change_rate: float = 300.0

## Доля от move_speed, ниже которой герой считается стоящим (упёрся в стену).
@export_range(0.0, 1.0, 0.01) var min_walk_speed_ratio: float = 0.15

## Суффиксы направлений по часовой стрелке, начиная с востока (угол 0 в Godot).
const DIRECTION_SUFFIXES: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

## Последнее направление взгляда — сохраняется после остановки.
var facing: StringName = &"s"

## Текущая скорость движения: плавно меняется между ходьбой и бегом.
var current_speed: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	current_speed = move_speed
	_update_animation(false, false)


func _physics_process(delta: float) -> void:
	# get_vector() уже ограничивает длину вектора единицей,
	# поэтому по диагонали скорость та же, что и по прямой.
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var wants_run := Input.is_action_pressed(&"run")

	if direction == Vector2.ZERO:
		# Без инерции: остановка мгновенная, следующий шаг снова начинается с ходьбы.
		current_speed = move_speed
	else:
		# Переход ходьба ↔ бег — плавный, без рывка.
		var target_speed := move_speed * (run_speed_multiplier if wants_run else 1.0)
		current_speed = move_toward(current_speed, target_speed, speed_change_rate * delta)

	velocity = direction * current_speed
	move_and_slide()

	# Поворачиваемся только при вводе; без ввода остаётся последнее направление.
	if direction != Vector2.ZERO:
		facing = _direction_to_suffix(direction)

	# Движение определяем по фактической скорости после столкновений:
	# если герой упёрся в препятствие, он стоит в Idle, а не шагает на месте.
	var is_moving := get_real_velocity().length() > move_speed * min_walk_speed_ratio
	_update_animation(is_moving, wants_run)


## Переводит вектор движения в одно из 8 направлений (секторы по 45°).
func _direction_to_suffix(direction: Vector2) -> StringName:
	var index := wrapi(roundi(direction.angle() / (PI / 4.0)), 0, 8)
	return DIRECTION_SUFFIXES[index]


## Idle — стоим; walk_<направление> — идём; run_<направление> — бежим (зажат Shift).
## Если нужной анимации нет в SpriteFrames, берётся ближайшая доступная: run → walk → idle.
## Анимация перезапускается только при смене имени, а не каждый кадр.
func _update_animation(is_moving: bool, is_running: bool) -> void:
	var anim := StringName("idle_" + facing)
	if is_moving:
		var walk_anim := StringName("walk_" + facing)
		var run_anim := StringName("run_" + facing)
		if is_running and sprite.sprite_frames.has_animation(run_anim):
			anim = run_anim
		elif sprite.sprite_frames.has_animation(walk_anim):
			anim = walk_anim
	if sprite.animation == anim:
		return

	# Ходьба ↔ бег в ту же сторону: продолжаем с той же фазы шага, чтобы ноги не «дёргались».
	var keep_phase := is_moving and String(sprite.animation).ends_with("_" + facing) \
			and not String(sprite.animation).begins_with("idle_")
	var frame := sprite.frame
	var progress := sprite.frame_progress
	sprite.play(anim)
	if keep_phase and frame < sprite.sprite_frames.get_frame_count(anim):
		sprite.set_frame_and_progress(frame, progress)
