# Постапокалипсис

Игра на Godot 4.

## Как открыть
1. Установите [Godot 4.7](https://godotengine.org/download) (проект проверен на 4.7.2, рендерер Compatibility).
2. В менеджере проектов нажмите **Import** и выберите `project.godot`.

## Текущий прототип
Главная сцена — `scenes/test/iso_movement_test.tscn`: изометрическая сетка, главный герой (Idle, ходьба и бег в 8 направлениях), камера и тестовые препятствия (`World/Obstacles`).
Запуск — **F5**. Управление — **WASD** (работает и на русской раскладке), **Shift** (левый или правый) + WASD — бег.

- Скорость ходьбы: узел `World/Player` → инспектор → `Move Speed` (120 px/s).
- Бег: там же `Run Speed Multiplier` (1.6 → 192 px/s) и `Speed Change Rate` — плавность перехода ходьба ↔ бег (300 px/s², ≈ 0,25 с).
- FPS анимаций: двойной клик по `characters/protagonist/animations/protagonist_frames.tres` → панель SpriteFrames → выбрать анимацию → поле FPS. Сейчас `walk_*` — 8, `run_*` — 10.
- Масштаб героя: узел `World/Player/AnimatedSprite2D` → `Node2D → Transform → Scale` (сейчас 0.5 = рост 112 px).
- Плавность камеры: узел `World/Player/Camera2D` → `Position Smoothing → Speed` (меньше — плавнее).
- Препятствия (`World/Obstacles`) — обычные узлы сцены, без скриптов: `StaticBody2D` → `CollisionShape2D` (ромб на земле, точки тянутся мышкой) и узлы-клетки `Cell` с гранями `Polygon2D` (`Top`, `FaceLeft`, `FaceRight`) и контуром `Line2D`. Позиция блока — северный угол его ромба, ставится в вершину сетки: клетка (x, y) → ((x − y)·32, (x + y)·16). Новый блок — дублировать существующий (Ctrl+D) и передвинуть.
- Герой и препятствия лежат в узле `World` с Y-sort: кто ниже на экране, тот рисуется поверх.
- Размер ромба сетки: узел `IsoGrid` → `Tile Size` (временно 64×32).

## Структура
```
scenes/          — сцены (.tscn)
scenes/test/     — тестовые сцены прототипа
scripts/         — скрипты GDScript (.gd)
scripts/player/  — скрипты персонажа (player.gd)
characters/<имя>/animations/ — игровые анимации персонажа и SpriteFrames
scripts/test/    — вспомогательные скрипты тестовых сцен
assets/sprites/  — графика
assets/audio/    — звуки и музыка
assets/fonts/    — шрифты
```

## Git
- Папка `.godot/` не коммитится — Godot пересоздаёт её сам.
- Файлы `*.import` коммитятся (в них настройки импорта ассетов).
- Коммитим небольшими шагами с понятным описанием, например:
  `Добавлен игрок: движение и анимация бега`.
