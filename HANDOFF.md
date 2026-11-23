# Передача работы — Сонная стройка v0.22.1 (выпущена 23.11.2026)

Обновлено: 23.11.2026, МСК. v0.22.1 — правки владельца по документу «Всё про всё» (pt111u). Подробности — CHANGELOG_V0.22.1.md. Следующие версии называть 0.23, 0.24 и т. д.

## Репозиторий
- https://github.com/Dre1km0ns/sonnaya-stroyka, checkout `/workspace/sonnaya-stroyka`.
- `main` = `wip/v0.22.1`, тег `v0.22.1`. База v0.22 — e58d16b.
- Этапы: fbd3b07 (чат, подсказки, боссы, Земля, без светоблоков, фиолетовый Сон, копия станций), 9d5a712 (мышь, стамина, настенные факелы, лагерь, озёра, подпорка, консоль, смоук), 6b94ab4 (шейдер Сна, площадка Сна), затем финал.
- Документ «Всё про всё» на Drive: 1pLDpLHtOg43x_Ai9ty8AHmI0G28UP08V2HIHK5mY05M; сборщик /workspace/doc (build.py, build2.py) и `tools/doc_dump.gd`, `tools/doc_blocks.gd`, `tools/doc_screens.gd`.

## Правила владельца
- Каждой новой функции нужна консольная команда DevSeed (6767676767) с русской справкой, примерами и Tab.
- **Указаний в скобках в интерфейсе нет и больше не добавлять.**
- В чат идут только сообщения из белого списка (`chat(..., keep=true)`); всё остальное — в `muted_chat`. Подсказки Яви не показывать.
- Отчётных документов не создавать. Фиксы не имитировать: каждый подтверждать смоуком, ботом или кадрами.
- Видео владельца на Drive не трогать.
- Новый большой список идей: сначала изложить понимание и ждать «работай».
- Лимит: если недельный расход больше 80 %, остановиться, запушить WIP и оставить шаги в этом файле.

## Где код v0.22.1
- Чат: `game_state.chat(text, color, keep)`, `muted_chat`, `CHAT_HINT_DENY`, `dream_hint_allowed`, `set_hint`. Подсказки у прицела: `context_hints.gd` (только Сон).
- Земля и удалённые блоки: `game_state.KIND_ALIASES`, `canon_kind`, `migrate_v0221(old_save)`; `block_tex.faces_for` ветка `"dirt"` (exposed_top); `voxel_world` ключ тайла `dirt|0/1`; `chunk_job`/`chunk_manager` генерация `dirt`.
- Фиолетовый Сон: `shaders/terrain.gdshader` (`dream`, `tint`; альфа вершины 0 — не перекрашивать), `block_tex.dream_material`, `DREAM_TINT`, `dream_tinted`; меши Сна в `voxel_world` и `chunk_manager` получают `material_override`.
- Копия станций: `game_state.resolve_wake` (цикл оплаты, флаг `paid` у станций из инвентаря Сна), `materialize_cost`, `place_dream_block`.
- Мышь: `build_controller._process` (`TAP_TIME 0.22`, `DREAM_BREAK_REPEAT 0.2`).
- Стамина: `game_state` `STAMINA_*`, `tick_stamina`, `can_sprint`; `player_controller`; `hud` `StaminaBar`.
- Настенные факелы: `voxel_world.wall_dir`, `apply_wall_torch`, `WALL_TORCH_TILT`; `build_controller._attach_dream_torch`; опора как в v0.22.
- Лагерь: `main._build_starter_camp`; старые миры — `game_state.lower_floating_camp` и `_lower_dream_pad` (только при формате сейва < 16). Площадка Сна: `world_switcher.enter_dream`. Озёра: `chunk_has_lake` в обоих файлах чанков.
- Подпорка: тайл 41 атласа, `tools/make_strut_tile.py` (make_textures.py атлас целиком не пересобирает — не запускать его без проверки).
- Анаконда: `boss_anaconda.SEGMENTS = 15`, сообщения, без яйца в дропе, гнездо без условия Матери.
- Консоль: `dev_console._v0221_cmd`. Смоук: `_v0221_checks` (22101–22135).

## Как собрать и проверить (Godot 4.7.2: /home/box/godot/godot)
- Импорт: `godot --headless --path . --import`.
- Parse: `--script res://tools/parse_check.gd` → `PARSE DONE bad=0`.
- Смоук: `XDG_DATA_HOME=/tmp/x godot --headless --path . --script res://scripts/smoke_test.gd` → `SMOKE: OK`.
- Бот: `--headless --path . --fixed-fps 60 -s res://tools/v020_bot.gd -- --minutes=40` (около 10 мин). Бот перезаписывает `benchmarks/v020_bot.json`: результат копировать в `benchmarks/v0221_bot.json`, затем `git checkout benchmarks/v020_bot.json`.
- Кадры: `DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v0221_screens.gd -- --out=/workspace/shots/v0221` (Xvfb :77 1280×720).
- Exe: `--headless --export-release "Windows Desktop" build/windows/SonnayaStroyka.exe`; проверка: `--main-pack build/windows/SonnayaStroyka.exe --script res://scripts/smoke_test.gd`.

## Известные недочёты
1. Exe не запускался на настоящей Windows.
2. Руки от первого лица: инструмент не привязан к кисти.
3. Опору факелов проверяет сигнал `GameState.wake_cell_removed`; в обход него факел может остаться висеть — `torch drop`.
4. Время ×4 двигает только часы суток и ночные счётчики.
5. `tools/anaconda_sim.gd` устарел после отката боссов в v0.22 (нет `set_seed`) — 15 сегментов проверены смоуком и кадрами, симулятор не запускается.
6. Иконки в хотбаре Сна остаются обычного цвета, фиолетовые только блоки в мире.
7. `boss_combat_sm.gd` и режим «носильщиков» блоклингов — мёртвый код.
8. Рельефа у земли Сна нет (перенос в Явь опирается на y=0).
9. parse_check не ловит ошибки вывода типов (`:=` от нетипизированного значения) — после правок обязательно гонять смоук.
