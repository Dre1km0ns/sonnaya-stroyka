# Передача работы — Сонная стройка v0.24 (в работе, ветка `wip/v0.24`)

Обновлено: 23.11.2026, МСК. Идёт сборка v0.24 поверх v0.23 (`main` = v0.23, тег `v0.23`). Ниже — что уже сделано, где код и что осталось. Старый раздел v0.23 сохранён ниже.

### v0.24 — этап 3 (сеть, разнообразие, Антон-толстяк) — состояние на 23.11 20:00 МСК
- F сеть (LAN, ENet, порт 24567, поиск 24568): scripts/net_session.gd (автозагрузка NetSession), net_avatar.gd (Kenney + табличка игрока), net_proxy.gd (мобы хоста у клиента, без табличек). Меню: «Создать сетевую игру», «Подключиться» (имя, IP, «Найти игры в сети»). Чат — Enter. Консоль: net status/host/chat/leave. Проверка: tools/mp_smoke.gd двумя процессами (host+client) — оба OK.
- п.14: рощи/поляны/башни/пещерные края (chunk_manager.forest_kind, cave_rich, ruin shape 3); консоль variety. Частота гнёзд Матери прежняя.
- п.20: вехи прогресса (scripts/progress_store.gd, меню «Прогресс», консоль progress).
- п.24: единая тема UiTheme.shared() на инвентарь/крафт/сундук/подушку/смерть/победу. п.25: иконки у всех предметов (smoke 24133). п.26: переназначения (24134). п.27: полоса загрузки с реальным прогрессом ResourceLoader.
- pt138u: Антон t2x2 переделан в толстяка «как Пудж»: процедурная модель и анимация (_build_anton/_tick_rig), капсула r 1.8, хитбокс 2.0, FIST_RANGE 4.3, комбо правой-левой. Табличка над Антоном убрана, лазер исправлен (масштаб в локальных осях).
- Осталось: п.22 баланс (старые tools/boss_sim.gd и anaconda_sim.gd устарели — падают на set_seed, нужен новый бот), п.6/9 проверка кадрами, кадры погоды/частиц/MP, CREDITS, весь финальный конвейер (40-мин бот, CHANGELOG, док «Всё про всё v0.24», merge/tag, Windows, Drive).

## Как продолжить
1. `cd /workspace/sonnaya-stroyka && git checkout wip/v0.24 && git pull`.
2. Импорт: `/home/box/godot/godot --headless --path . --import`.
3. Парс: `godot --headless --path . --script res://tools/parse_check.gd` → `PARSE DONE bad=0`.
4. Смоук: `XDG_DATA_HOME=/tmp/x godot --headless --path . --script res://scripts/smoke_test.gd` → в конце `SMOKE: OK` (код выхода 1 даже при успехе — так было и раньше). Новые проверки v0.24 — `scripts/smoke_v024.gd` (коды 24000+), вызов из `smoke_test._run` после `_v011_checks`; `smoke24.done` проверяется (24000), чтобы скриптовая ошибка не прошла молча.
5. Кадры: `Xvfb :77 &` затем `DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v024_screens.gd -- --out=/workspace/shots/v024` (`--only=bow` — только лук).
6. Лимит владельца: остановка на **95 %** недельного расхода (pt133u), а не 80 %.

## Этап 1 — сделано (B + C + D + E-ядро)
- **B. ЛКМ ломает любым предметом** (в т. ч. блоком): убраны проверки «нужна кирка» в `game_state.mine_wake_block` и `build_controller._mine_terrain_cell`. Скорость — `mining_rules.seconds` по уровню кирки (`scripts/gear.gd`).
- **B. Дальность меча**: `gear.gd` `SWORDS` — деревянный 3.5 м, каменный 3.8, металлический 4.15, чешуйчатый 4.5. `build_controller._try_sword` берёт дальность/урон из Gear, `last_sword_reach`.
- Кирка повёрнута на 90° (`viewmodel_rig.TOOL_CONFIG[...].spin`), проверено кадром `02_pickaxe2_idle_ore.png`.
- **C. Металл**: `scripts/ore_rules.gd` (глубина −7…−26, кластеры 2×2×2), руда в `chunk_job/_ug_tiles` и `chunk_manager.terrain_kind_at`. Добыча и дроп только каменной киркой и лучше (`mining_rules.ORE_MIN_TIER`). Слиток, металлическая кирка/меч/броня, лук, металлический лук, стрелы, стрелы из детёнышей — `game_state.v024_recipes()`.
- **C. Лук**: `scripts/bow_controller.gd` (зажать ЛКМ — натяжение, отпустить — выстрел), `scripts/arrow.gd` (гравитация, втыкается, подбирается, слабые точки Бургера). Ящерки-детёныши после Анаконды: `scripts/lizard_minion.gd`, спавн в `threat_director._lizard_t`; дроп «молочные зубки».
- **D. Сложность**: выбор «Нормальный/Эксперт» в `main_menu` (OptionButton `Difficulty`, мета мира `difficulty`, тег «эксперт» в списке миров), хранится в сейве (`v024.difficulty`, SAVE_FORMAT 18). Множители `game_state.diff_*` (HP ×1.75, урон ×1.35, скорость ×1.2, обзор ×1.35, поводок ×1.5) — в `apply_enemy_scaling`, `enemy_navigation`, Матери, Анаконде, призраках.
- **E. Бургер Смерти**: `scripts/boss_burger.gd` (4000 HP на нормале, ×1.75 эксперт, ×(1+0.6·(игроки−1)) в сети), `weak_point.gd`, `clown_bomb.gd`, `grill_saucer.gd`, `burger_summon.gd` (призывалка, ровно 60 с, предупреждение в чате и за 10 с). Токены 35 %: `roll_boss_token` / `drop_boss_token` у Матери и Анаконды. Музыка: `music_controller` ключи `burger1/burger2`. Экран победы и титры: `scripts/victory_screen.gd` (HUD, сигнал `GameState.victory`, флаг `victory_open` в `ui_blocked`).
- **Зелье скорости** (t134u): алхимия, `heal1 + 4 листвы + reagent2`; 60 с бег без стамины и ×1.12 скорости (`player_controller`).
- Звуки: `tools/make_v024_sfx.py` (синтез), иконки и тайлы атласа: `tools/make_v024_art.py`.
- Консоль: `scripts/console_v024.gd` — `difficulty`, `ore`, `bow`, `arrows`, `burger …`, `summoner …`, `speedpotion …`, `lizards …`, `kit`; справка `help <команда>`, Tab.

## Осталось (по порядку)
- A-пункты: 4 (мёртвый код boss_combat_sm.gd, режим тумбочки), 5 (лог ошибок в user://, путь в паузе/настройках), 6 (блок в руке не уходит за экран), 7 (шаги, удар, урон, подбор), 8 (покачивание и тряска камеры), 10 (деспаун дропа 5 мин, Q над слотом), 11 (фиолетовые иконки во Сне), 12 (пояснения M и J при первом нажатии), 13, 14, 15 (прыгун, лучник, вор), 16, 17 (дождь, туман), 20, 21 (новые атаки Матери и Анаконды), 22, 24, 25, 26 (громкость музыки/звуков, FOV), 27 (загрузка с прогрессом).
- F: сеть LAN до 4 игроков (`scripts/combat_util.gd` уже умеет `hurt` удалённым игрокам через узел `net_session`).
- Бот 40 мин, кадры, CHANGELOG_V0.24, «Всё про всё v0.24», слияние, тег, Windows-сборка, Drive.


---

# Передача работы — Сонная стройка v0.23 (выпущена 23.11.2026)

Обновлено: 23.11.2026, МСК. v0.23 — мышь как в v0.22, предмет в кисти руки во всех действиях, удар в воздух, выбрасывание как в Minecraft (pt115u, pt117u). Подробности — CHANGELOG_V0.23.md, раньше — CHANGELOG_V0.22.1.md. Следующая версия — 0.24.

## Репозиторий
- https://github.com/Dre1km0ns/sonnaya-stroyka, checkout `/workspace/sonnaya-stroyka`.
- `main` = `wip/v0.23`, тег `v0.23`. База v0.22.1 — 7de38ba (тег v0.22.1).
- Этапы: 4d71e94 (мышь, рука, удар в воздух, выбрасывание, консоль, смоук), затем финал.
- Документ «Всё про всё v0.23» на Drive (новый документ; старый v0.22.1 — 1Vk_rd889ke8ImFlqwQS9SJLzHlq4TG4BuEwE9v-lk4g); сборщик /workspace/doc (build.py, build2.py) и `tools/doc_dump.gd`, `tools/doc_blocks.gd`, `tools/doc_screens.gd`.

## Правила владельца
- Каждой новой функции нужна консольная команда DevSeed (6767676767) с русской справкой, примерами и Tab.
- **Указаний в скобках в интерфейсе нет и больше не добавлять.**
- В чат идут только сообщения из белого списка (`chat(..., keep=true)`); всё остальное — в `muted_chat`. Подсказки Яви не показывать.
- Отчётных документов не создавать. Фиксы не имитировать: каждый подтверждать смоуком, ботом или кадрами.
- Видео владельца на Drive не трогать.
- Новый большой список идей: сначала изложить понимание и ждать «работай».
- Лимит: если недельный расход больше 80 %, остановиться, запушить WIP и оставить шаги в этом файле.

## Где код v0.23
- Мышь: `build_controller._process` (ветка Яви: ПКМ дверь → яйцо → факел → блок; ЛКМ меч → `_try_sword`, иначе факел → `swing_air` без цели → `_tick_mining`). Сон: ПКМ `_try_place`, ЛКМ `_try_remove`.
- Рука: `fp_arms.gd` (`HAND_SOCKET` на `arm-right`, `extra`, клипы `CLIPS`, в т. ч. `drink`); `viewmodel_rig.gd` (`follow_hand`, `HOLD_ROT`, `process_priority = 50`, модели `block` и `item`, `kick_offset` — отдача всей руки). `WRIST_SWING = 0` — у предмета нет своей анимации.
- Временный предмет в руке: `build_controller.show_in_hand(id, сек, действие)` (зелье на H из `world_switcher`).
- Выбрасывание: `build_controller.drop_selected / throw_payload / spawn_drop / spawn_saved_drops`; `scripts/dropped_item.gd`; `game_state` `take_from_slot`, `can_drop_items`, `register_drop`, `unregister_drop`, `give_payload`, `dropped_items`, `_drops_to_json/_drops_from_json`, `SAVE_FORMAT 17`; `inventory_ui._on_outside_input / drop_held`; клавиша `drop_item` и `SHARED_KEYS` в `game_settings`.
- Консоль: `dev_console._v023_cmd` (`drop`, `swing`, `hand`). Смоук: блок 23001–23017 в `_v011_scene_checks`.

## Где код v0.22.1
- Чат: `game_state.chat(text, color, keep)`, `muted_chat`, `CHAT_HINT_DENY`, `dream_hint_allowed`, `set_hint`. Подсказки у прицела: `context_hints.gd` (только Сон).
- Земля и удалённые блоки: `game_state.KIND_ALIASES`, `canon_kind`, `migrate_v0221(old_save)`; `block_tex.faces_for` ветка `"dirt"` (exposed_top); `voxel_world` ключ тайла `dirt|0/1`; `chunk_job`/`chunk_manager` генерация `dirt`.
- Фиолетовый Сон: `shaders/terrain.gdshader` (`dream`, `tint`; альфа вершины 0 — не перекрашивать), `block_tex.dream_material`, `DREAM_TINT`, `dream_tinted`; меши Сна в `voxel_world` и `chunk_manager` получают `material_override`.
- Копия станций: `game_state.resolve_wake` (цикл оплаты, флаг `paid` у станций из инвентаря Сна), `materialize_cost`, `place_dream_block`.
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
- Бот: `--headless --path . --fixed-fps 60 -s res://tools/v020_bot.gd -- --minutes=40` (около 7 мин). Бот перезаписывает `benchmarks/v020_bot.json`: результат копировать в `benchmarks/v023_bot.json`, затем `git checkout benchmarks/v020_bot.json`.
- Кадры: `DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v023_screens.gd -- --out=/workspace/shots/v023` (Xvfb :77 1280×720).
- Exe: `--headless --export-release "Windows Desktop" build/windows/SonnayaStroyka.exe`; проверка: `--main-pack build/windows/SonnayaStroyka.exe --script res://scripts/smoke_test.gd`.

## Известные недочёты
1. Exe не запускался на настоящей Windows.
2. Положение предметов в кисти подобрано по кадрам: блок при замахе уходит из кадра вместе с кистью, меч держится почти вертикально.
3. Опору факелов проверяет сигнал `GameState.wake_cell_removed`; в обход него факел может остаться висеть — `torch drop`.
4. Время ×4 двигает только часы суток и ночные счётчики.
5. `tools/anaconda_sim.gd` устарел после отката боссов в v0.22 (нет `set_seed`) — 15 сегментов проверены смоуком и кадрами, симулятор не запускается.
6. Иконки в хотбаре Сна остаются обычного цвета, фиолетовые только блоки в мире.
7. `boss_combat_sm.gd` и режим «носильщиков» блоклингов — мёртвый код.
8. Рельефа у земли Сна нет (перенос в Явь опирается на y=0).
9. parse_check не ловит ошибки вывода типов (`:=` от нетипизированного значения) — после правок обязательно гонять смоук.
10. Выброшенные предметы не исчезают со временем (лимит 256 на мир, старые вытесняются).
11. В открытом инвентаре Q не выбрасывает предмет под курсором — только щелчок за окном.
