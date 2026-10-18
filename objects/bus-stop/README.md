# Автобусная остановка (`BusStop.tscn`)

Переиспользуемый объект. Спрайт `bus-stop-v001.png` — копия исходника
`levels/level-01-arrival/object/bus-stop-original-reference-scale-test-v001.png` без изменений
(320×320, прозрачность сохранена, фильтр Nearest из настроек проекта).

## Как поставить на карту
Перетащите `BusStop.tscn` в узел с Y-sort (на тестовой сцене — `World/Obstacles`).
**Точка привязки** (позиция узла) — основание передней левой опоры, у урны. Ставьте её в вершину сетки.

## Масштаб
Узел `BusStop` → `Transform → Scale`, сейчас **1.15** (опора до крыши ≈ 146 px при росте героя 112 px).
Масштаб применяется ко всему объекту — картинка и коллизии меняются вместе.

## Устройство
- `Visual` — картинка, разрезанная на 10 вертикальных полос (`Sprite2D` с `region` одного и того же PNG,
  файл не изменяется). Каждая полоса сортируется по своей точке на краю остановки, поэтому герой
  правильно оказывается перед или за любой её частью:
  - `Slice01`–`Slice06` — по переднему краю (левая стенка и фасад);
  - `Slice07`–`Slice09` — по заднему краю (задняя стенка и правое ограждение): над ними карман под навесом,
    и стоящий там герой рисуется перед стенкой и ограждением, а не за всей остановкой.
- `Body` (`StaticBody2D`) — коллизии на плоскости земли:
  - `PostBackLeft`, `PostFrontLeft`, `PostBackRight`, `PostFrontRight` — опоры (круги);
  - `WallBack`, `WallLeft` — задняя и левая стенки, `RailingRight` — правое ограждение (капсулы со скруглёнными
    концами: герой не цепляется за углы);
  - `BenchAndBin` — скамейка и урна одной выпуклой формой (щель между ними всё равно непроходима).
- Перед остановкой открыто; под навес можно зайти в карман справа от скамейки.
- Группа `occludable`: когда остановка закрывает заметную часть героя (за задней стенкой), полупрозрачной становится **вся** остановка. В кармане под навесом прозрачность не включается.

## Ограничение и как его снять
Исходник — одно изображение, крыша не отделена от стенок и скамейки. Автоматически вырезать крышу
небезопасно (можно повредить края), поэтому сейчас прозрачной становится вся остановка целиком.
Чтобы прозрачной была только крыша (и передние элементы), нужен второй PNG того же размера 320×320 —
отдельный слой крыши (остальное прозрачно) и слой без крыши. Тогда в `Visual` добавляется слой `Roof`
со своей сортировкой, и прозрачность вешается только на него.

## Перспектива и новая картинка
Нынешняя картинка нарисована не в проекции 2:1: длинная сторона идёт под ≈ 13° вместо 26,6°, поэтому
остановка стоит под углом к дорогам. Выровнять наклоном (как дом) можно только ценой сужения на ~23 %,
поэтому решено перерисовать картинку.

Как получить новую (ChatGPT или другой генератор):
1. Приложите две картинки: `bus-stop-v001.png` (дизайн) и `reference/bus-stop-guide-2to1.png` (шаблон:
   сетка 2:1, красное «пятно» остановки 6 × 3 клетки ≈ 3,7 × 1,8 м, герой для масштаба).
2. Промпт:
```
Redraw the bus stop shelter from the first image as pixel art for an isometric game in a TRUE 2:1
dimetric projection. Use the second image as the exact guide: the red outline is the shelter's footprint
on the ground grid. Every ground and roof edge must follow the grid lines (2 pixels across for 1 pixel up,
26.57°); all posts and walls strictly vertical. Long side along the up-right grid line, back wall on the
far (top-left) side, open side with the bench facing the viewer (bottom-right).
Keep the same design, colors and wear: rusty corrugated roof, blue-grey metal frame, posters, wooden bench,
trash bin at the front-left post. Scale: the character in the guide is 1.75 m tall; the roof is about 2.4 m
above the ground. Output only the shelter: no grid, no red outline, no character, no ground, no shadow
on the ground, no text. Plain flat single-color background (or transparent), PNG, 1024×1024.
```
3. Если углы опять «уехали», напишите: «Rewrite strictly along the grid lines of the guide: footprint must
   match the red outline exactly». Обычно нужно 2–3 попытки.
4. Готовую картинку положите в эту папку (например `bus-stop-v002-source.png`) — фон уберу, подгоню масштаб
   и пересоберу коллизии.
