# Передача работы — Сонная стройка v0.22 (выпущена 19.11.2026)

Обновлено: 19.11.2026, МСК. v0.22 закрывает список владельца из 16 пунктов (pt92u–pt108u). Подробности — CHANGELOG_V0.22.md.

## Репозиторий
- https://github.com/Dre1km0ns/sonnaya-stroyka, checkout `/workspace/sonnaya-stroyka`.
- `main` = `wip/v0.22` (fast-forward), тег `v0.22`. База v0.21 — f0707e1.
- Этапы: b4e4fde (боссы), 3953be7 (скобки, хотбар Сна), ac2fac0 (сводка, кровать, лагерь, спавн, факелы, падение, рамка), 8306c5d (осыпь, время ×4, мышь, отдача, руки, консоль), затем финал (версия, документы, бот).

## Правила владельца
- Каждой новой функции нужна консольная команда DevSeed (6767676767) с русской справкой, примерами и Tab.
- **Указаний в скобках в интерфейсе нет и больше не добавлять** (pt97u).
- Отчётных документов не создавать. Фиксы не имитировать: каждый подтверждать смоуком, ботом или кадрами.
- Видео владельца на Drive не трогать.
- Новый большой список идей: сначала изложить понимание и ждать «работай».
- Лимит: если недельный расход больше 80 %, остановиться, запушить WIP и оставить шаги в этом файле.

## Где код v0.22
- Хотбар Сна: `game_state.gd` — `PALETTE_SLOT`, `palette_slot_active`, `dream_palette_kind`; `build_controller._place_at`; `hud._refresh_inv`.
- Время ×4: `game_state.gd` — `DREAM_WAKE_TIME_SCALE`, `advance_wake_clock`, `night_counts`, `night_dreamt`, `wake_time_skipped`; `day_cycle._process`; `threat_director._on_player_woke` (`WAKE_SPAWN_GRACE`, `DAY_WAKE_CAP`).
- Дневной спавн: `threat_director.gd` — `DAY_SPAWN_RATE`, `spawn_interval`, `_ghost_can_spawn`.
- Факелы: `build_controller.gd` — `torch_attach_for`, `torch_supported`, `drop_unsupported_torches` (по сигналу `GameState.wake_cell_removed`), ключ `attach` в `wake_blocks`.
- Падение: `game_state.gd` — `FALL_SAFE_BLOCKS`, `FALL_DMG_PER_BLOCK`, `fall_damage_for`, `apply_fall`; `player_controller._track_fall`.
- Рамка: `game_state.dream_clear` (без цены и лимита).
- Мышь: действия `attack_break` (ЛКМ) и `use_place` (ПКМ) в `project.godot` и `game_settings.BINDABLE`; логика в `build_controller._process`.
- Отдача: `viewmodel_rig.play_recoil` / `_do_recoil`. Откидывание: `enemy_navigation.apply_knockback` и мета `kb` в `apply_movement`; `build_controller._combat_feedback`, `KNOCKBACK`.
- Руки: `scripts/fp_arms.gd` (под `ViewModelRoot`), модель `assets/models/kenney_blocky/`. Подгонка: `SHOULDER`, `AIM`, `SCALE`.
- Осыпь: константы в начале `game_state.gd`, `try_steal`, `DUST_STEAL_CHANCE`.
- Боссы v0.11: `block_mother.gd`, `boss_anaconda.gd`, `anaconda_worm.gd` (из 21333e4). Агрессия: `TORCH_AGGRO_*`, `update_torch_aggro`, `break_torch_forced`.
- Сводка Сна: `world_switcher.wake_up` (окно только при `not ok`). Кровать: `hud._update_bed_prompt`. Лагерь: `main.gd` (вызов `_camp_label` убран).
- Консоль: `dev_console._v022_cmd`. Смоук: `_v022_checks`, `_v022_scene_checks` (22001–22091).

## Как собрать и проверить (Godot 4.7.2: /home/box/godot/godot)
- Импорт: `godot --headless --path . --import`.
- Parse: `--script res://tools/parse_check.gd` → `PARSE DONE bad=0`.
- Смоук: `XDG_DATA_HOME=/tmp/x godot --headless --path . --script res://scripts/smoke_test.gd` → `SMOKE: OK`.
- Бот: `--headless --path . --fixed-fps 60 -s res://tools/v020_bot.gd -- --minutes=40` (около 10 мин). Бот перезаписывает `benchmarks/v020_bot.json`: результат копировать в `benchmarks/v022_bot.json`, затем `git checkout benchmarks/v020_bot.json`.
- Кадры: `DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v022_screens.gd -- --out=/workspace/shots/v022` (Xvfb :77 1280×720).
- Exe: `--headless --export-release "Windows Desktop" build/windows/SonnayaStroyka.exe`; проверка: `--main-pack build/windows/SonnayaStroyka.exe --script res://scripts/smoke_test.gd`.

## Известные недочёты
1. Exe не запускался на настоящей Windows.
2. Руки от первого лица: инструмент не привязан к кисти. Он машет своим твином, рука — клипом модели; синхронно по времени, но не одно целое. Ходьба, прыжок и сон сделаны процедурно.
3. Опору факелов проверяет сигнал `GameState.wake_cell_removed` (игрок, мобы, `destroy_wake_structure`, `remove_terrain_cell`). Если блок убран в обход этих функций, факел останется висеть; тогда поможет `torch drop`.
4. Время ×4 двигает только часы суток и ночные счётчики. Таймеры, привязанные к бодрствованию (`awake_time`, рост угрозы), во Сне стоят, как и раньше.
5. Очистка рамки не трогает закреплённые блоки и станции: их снятие не отменяется Z.
6. Шовник после откидывания может упасть с обрыва — это честная физика.
7. `boss_combat_sm.gd` и режим «носильщиков» блоклингов — мёртвый код после отката боссов; удалить вместе со старыми блоками smoke 13001+.
8. Рельефа у земли Сна нет (перенос в Явь опирается на y=0).

## Если продолжать
- Привязать инструмент к кисти модели (BoneAttachment не нужен, кисть — конец меша `arm-right`).
