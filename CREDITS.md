# Сонная стройка — модели и лицензии

Kenney — Pickaxe (Survival Kit), 100 triangles, original GLB geometry.
License: Creative Commons CC0 1.0 Universal (public domain).
https://creativecommons.org/publicdomain/zero/1.0/
Author: Kenney — https://kenney.nl/
Official asset pack: https://kenney.nl/assets/survival-kit
Download and explicit CC0 listing: https://poly.pizza/m/UHZH2OoWCS
Original binary: https://static.poly.pizza/e54e2797-c7b2-424a-bfbc-fb9d1e97fd79.glb
Local original: assets/models/kenney/pickaxe.glb (unchanged).
Adaptations: game scale/grip transform, UV reprojection and original 16x16 wood/stone textures.
Icons and crack masks are original artwork, released CC0; no Minecraft texture files copied.

## Дверь — Kenney Wooden Door, Building Kit
Source: https://poly.pizza/m/P09FqyST04
Author: Kenney — https://kenney.nl/
License: CC0 1.0 Universal / public domain — https://creativecommons.org/publicdomain/zero/1.0/
Original download: https://static.poly.pizza/16c02d69-21ae-49c2-bed1-6325570e356a.glb
Original local file: assets/models/kenney/wooden_door.glb (unchanged; 240 triangles).
Adaptation: coordinate/scale fit to one block wide and two blocks tall, 0.16-thick leaf; original beveled panels, both faces, hinges, handle and palette UV retained. Nearest filtering and brightness adaptation. Inventory icon rendered from this same model. No stretched plank atlas on the door.

## Руки от первого лица (v0.22) — Kenney Blocky Characters 2.0
Source: https://kenney.nl/assets/blocky-characters
Author: Kenney — https://kenney.nl/
License: CC0 1.0 Universal / public domain — https://creativecommons.org/publicdomain/zero/1.0/ (копия: assets/models/kenney_blocky/License.txt)
Local files: assets/models/kenney_blocky/character-a.glb, Textures/texture-a.png (unchanged).
Usage: только правая рука модели, видна от первого лица; клипы модели holding-right, attack-melee-right, interact-right. Ходьба, прыжок и засыпание — процедурное движение той же руки. Вида от третьего лица в игре нет.

## v0.24 — авторы и источники
- **Идея, геймдизайн, тестирование:** Димон Войнов. Эти же титры показывает экран победы после Бургера Смерти.
- **Музыка Бургера Смерти** (фаза 1 — assets/audio/burger_phase1_ost.mp3, фаза 2 — burger_phase2_ost.ogg) и короткий звук появления/атаки (burger_sting.ogg) — файлы, присланные автором игры (pt129u–pt132u), использованы без изменений, кроме перекодирования.
- **Звуки v0.24** (лук, стрелы, лазер, удары, шаги, дождь, эмбиент Сна, выпадение предметов) — сгенерированы процедурно скриптом tools/make_v024_sfx.py, CC0.
- **Иконки и текстуры v0.24** (руда, слитки, луки, стрелы, зубы, призывалка, зелье скорости) — tools/make_v024_art.py, оригинальные, CC0.
- **Антон t2x2** — процедурная модель из примитивов (scripts/boss_burger.gd), своя анимация; **Бургер Смерти** — по дизайну /workspace/deepseek/BURGER_OF_DEATH.md.
- **Аватары игроков в сетевой игре** — Kenney Blocky Characters 2.0 (character-a.glb, CC0), разный оттенок на игрока.
- **Движок:** Godot Engine 4.7 — MIT, https://godotengine.org/license
