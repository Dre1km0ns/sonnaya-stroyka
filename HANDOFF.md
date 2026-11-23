# Передача работы — Сонная стройка v0.25.1 (выпущена 24.11.2026)

Обновлено: 24.11.2026, МСК. v0.25.1 слита в `main`, тег `v0.25.1`. Изменения — CHANGELOG_V0.25.1.md. Раздел v0.25 ниже в силе.

## Что в v0.25.1 (где код)
- `scripts/chunky_body.gd`: `_build_slim` — свои стройные модели всех мобов и игрока (пресеты PRESETS, поле look), `_build_lizard`, `_build_cube_mother` (Мать блоков — большой куб, пресет `mother`; `_build_golem` не используется), `pixel_tex` — пиксельные текстуры 16×16, `_armor_slim` — броня на стройной модели. Толстый вариант (`_build`) остался только у Антона.
- `scripts/boss_anaconda.gd` `_build_body`: голова с челюстями и клыками, сегменты с брюхом и шипами (`_amat`, `_abox`).
- `scripts/block_mother.gd` и `net_proxy.gd`: Мать — `attach_chunky(self, "mother")` вместо greenblob.glb.
- Кадры моделей: `DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v0251_lineup.gd -- --out=/workspace/shots/v0251` (40–50).

## Известные недочёты v0.25.1
1. Анаконда и Мать сняты отдельной сценой (`v0251_lineup`), в бою в игровом мире отдельными кадрами не снимались.
2. Блоклинги и черви Анаконды остались прежними.
3. Мать и Анаконда в сети по-прежнему бьют только хоста; сеть проверена двумя процессами на одной машине; exe не запускался на настоящей Windows.
4. Бот 40 мин (BOT OK, 41,8 игровой минуты, 0 провалов, p50 3,3 мс, p99 16,5 мс, худший кадр 1,1 с на старте). В более раннем прогоне был кадр 22 с — тогда бокс ставился на паузу (часы процесса отставали от настенных), в чистом прогоне спайка нет, в т. ч. при переносе башни.

---

# Передача работы — Сонная стройка v0.25 (выпущена 23.11.2026)

Обновлено: 23.11.2026, МСК. v0.25 слита в `main`, тег `v0.25`. Полный список изменений — CHANGELOG_V0.25.md. Следующая версия — 0.26. Разделы v0.24 и v0.23 ниже в силе (запуск, сборка, правила владельца).

## Как проверить v0.25
- Парс, смоук, бот 40 мин, Windows — как в разделе v0.24 ниже. Проверки v0.25 в `scripts/smoke_v024.gd` (код 25001 — консоль v0.25) и в смоуке Матери (900 HP).
- Сеть: `tools/mp_smoke.gd` (host и client) — проверяет общий мир (`same_world_seed_and_terrain`), раскопку и дроп хоста у клиента, рост и броню аватара, удар, модели мобов и босса с именем. С окном: `DISPLAY=:77 … --rendering-method gl_compatibility … -- --role=host --shot=/workspace/shots/v025/15_mp.png` (клиент пишет `_client.png`).
- Кадры: `DISPLAY=:77 XDG_DATA_HOME=/tmp/xs godot --path . --rendering-method gl_compatibility -s res://tools/v025_screens.gd -- --out=/workspace/shots/v025` (22–33).

## Что в v0.25 (где код)
- **Общий мир**: корень — `main.gd` (клиент не создаёт временный мир 1337, ждёт мир хоста). Строки мобов в `net_session._mob_list`: [10] пресет модели, [11] счётчик атак, [12] доп. данные (точки Анаконды, фаза Бургера, масштаб Матери).
- **Модели у клиента**: `net_proxy.gd` (толстый пресет, Мать — greenblob, Анаконда — `boss_anaconda._build_body`, Бургер — `_build_saucer` ×2 и Антон с фазы 2), имя на полосе — `boss_title()`.
- **Игроки**: капсула 1,75 м, камера 1,55 м (`scenes/player.tscn`); `net_avatar.gd` — толстячок `player`, броня `set_armor`, действия `NetSession.local_action` (удар, ломать, ставить, выстрел).
- **Мобы**: `scripts/chunky_body.gd` — пресеты, `make()`, `play_state()` (attack, jump, crouch, draw, hurt, place, death, walk, idle). Подключение: `enemy_visuals.attach_chunky`, `wake_mob._build`, `lizard_minion`, `clown_bomb`. Консоль `chunky`.
- **Боссы**: `block_mother.gd` (MAX_HP 900, P2 594, P3 297, `phase_speed`), `boss_anaconda.gd` (`phase_speed`, кружит в REST/STUNNED), `boss_burger.gd` (HOVER_H 13.5, SAUCER_SCALE 2, CHASE_FAR/NEAR/MAX, `roll_drops` → только нос). Призывалка — `game_state.roll_boss_token`, миграция `migrate_v025_items` (вызов в `save_system`).
- **Урон раз в секунду**: `GameState.DAMAGE_TICK`, `_src_hit` в `_damage_player_core`.
- **Лук**: `gear.BOWS` (cd, range), `bow_controller.fire`, `arrow.gd` (range_m, прямой полёт 75 %, урон до 80 %), `viewmodel_rig` (масштаб 0.8, разворот).
- **Карта**: `scripts/world_map.gd`, клавиши `world_map` (Tab) и `goals_panel` (F2) в `game_settings.BINDABLE`, состояние в секции `hud`. Консоль `map`.
- **Иконки**: `tools/make_v025_art.py` (зелье скорости, металлическая броня), после — `godot --headless --path . --import`.
- **Консоль**: `scripts/console_v025.gd` (регистрируется в `dev_console._ready` через `console_v024.extra_help/handlers`): `map`, `chunky`, `bowinfo`, `dmgtick`, `chase`, `mpsync`.

## Известные недочёты v0.25
1. Мать блоков и Анаконда в сети по-прежнему бьют только хоста (урон через `GameState.damage_player` локально).
2. Блоклинги остаются блоками (это блоки), черви Анаконды — прежние модели.
3. Сеть проверена двумя процессами на одной машине (mp_smoke с окном и без), настоящей партии по LAN не было.
4. Exe не запускался на настоящей Windows (проверка — смоук внутри exe через `--main-pack` в Linux).
5. Одинаковый вид блоков в слоте, инвентаре и руке проверен кадрами на досках и бревне, остальные блоки — по общему атласу, отдельными кадрами не сверялись.
6. Кадр 33 (удар аватара) снят в момент, когда замах уже закончился; сама анимация проверена в mp_smoke (`avatar_swing`, `client_swing_seen`).
7. Смоук после «SMOKE: OK» иногда падает при выходе («corrupted size vs. prev_size») — это при освобождении движка, на результат не влияет.
8. Бот 40 мин (BOT OK, 41,8 игровой минуты, 0 провалов, p50 3,3 мс, p99 18,2 мс): один долгий кадр 3,4 с — снова при переносе башни 5×4×5 (100 блоков) из Сна в Явь, как в v0.24 (п. 8). Не исправлено.

---

# Передача работы — Сонная стройка v0.24 (выпущена 23.11.2026)

Обновлено: 23.11.2026, МСК. v0.24 слита в `main`, тег `v0.24`. Полный список изменений — CHANGELOG_V0.24.md, баланс — BALANCE_V0.24.md, титры — CREDITS.md. Следующая версия — 0.25. Раздел v0.23 сохранён ниже (правила владельца, сборка, старые пути кода — всё в силе).

## Как продолжить
1. `cd /workspace/sonnaya-stroyka && git checkout main && git pull` (GitHub: Dre1km0ns/sonnaya-stroyka).
2. Импорт: `/home/box/godot/godot --headless --path . --import`.
3. Парс: `godot --headless --path . --script res://tools/parse_check.gd` → `PARSE DONE bad=0`.
4. Смоук: `XDG_DATA_HOME=/tmp/x godot --headless --path . --script res://scripts/smoke_test.gd` → в конце `SMOKE: OK` (код выхода 1 даже при успехе). Проверки v0.24 — `scripts/smoke_v024.gd` (коды 24000+).
5. Сеть двумя процессами: `XDG_DATA_HOME=/tmp/mph godot --headless --path . -s res://tools/mp_smoke.gd -- --role=host` и в другом терминале то же с `--role=client` и `XDG_DATA_HOME=/tmp/mpc` → оба `MP OK`.
6. Кадры: `Xvfb :77 &`, затем `DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v024_screens.gd -- --out=/workspace/shots/v024` (`--only=bow|burger|misc`; `--shot=` у mp_smoke — кадр двух игроков).
7. Баланс боссов: `godot --headless --fixed-fps 60 --path . -s res://tools/v024_balance.gd -- [--only=mother|anaconda|burger]` → benchmarks/v024_balance.json.
8. Бот 40 мин: `godot --headless --path . --fixed-fps 60 -s res://tools/v020_bot.gd -- --minutes=40` → `BOT OK`, отчёт benchmarks/v020_bot.json.
9. Windows: `python3 tools/fetch_win_templates.py`, затем `godot --headless --path . --export-release "Windows Desktop" <путь>.exe`.
10. Лимит владельца: остановка на 95 % недельного расхода (pt133u).

## Что в v0.24 (кратко, где код)
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

- **F. Сеть LAN до 4 игроков** (ENet, порт 24567, поиск игр 24568): `scripts/net_session.gd` (автозагрузка NetSession), `net_avatar.gd` (модель Kenney и табличка «имя · HP»), `net_proxy.gd` (мобы хоста у клиента). Меню: «Создать сетевую игру», «Подключиться» (имя, IP, «Найти игры в сети», user://net.cfg). Чат — Enter (переназначается). Хост ведёт мир, мобов и время суток; клиент шлёт удары и блоки. Старые мобы (призраки, швы, блоклинги, черви) выбирают ближайшего игрока (`CU.nearest_player`). Консоль `net`.
- **п.14 разнообразие**: рощи и поляны (`chunk_manager.forest_kind`), богатые пещеры (`cave_rich`), башни руин (форма 3). Консоль `variety`.
- **п.20 вехи**: `scripts/progress_store.gd` (11 вех, user://progress.cfg), меню «Прогресс», консоль `progress`.
- **п.24–27**: общая тема `preload("res://scripts/ui_theme.gd").shared()` у всех окон; иконки у всех предметов; переназначения; полоса загрузки мира с реальным прогрессом (`main_menu._load_main`; без окна, в ботах — синхронная загрузка).
- **Антон t2x2** (pt138u): толстяк «как Пудж», процедурная модель и анимация (`boss_burger._build_anton`, `_tick_rig`), комбо правой и левой, без таблички.
- Блок в руке при замахе использует клип «place» (`build_controller._play_tool_swing`), дождь гуще (`weather.gd`).

## Баланс (бот tools/v024_balance.gd)

Бот бьётся с настоящими боссами в настоящей сцене настоящим ударом меча (`build._try_sword`), кружит вокруг цели на дистанции удара и не читает телеграфы (урон по нему — верхняя граница). Ниже 35 HP «пьёт зелье». Снаряжение: Мать — каменный меч, Анаконда — факел в руке (её ранит только свет), Бургер — металлический меч + металлический лук (70 % попаданий по слабым точкам).

| Босс | Сложность | HP | Итог | Время боя | Урон по боту, в мин | Зелий |
|---|---|---|---|---|---|---|
| Мать блоков | Нормальный | 560 | победа | 22.8 с | 66 | 0 |
| Мать блоков | Эксперт | 980 | победа | 38.3 с | 176 | 1 |
| Анаконда | Нормальный | 2100 | ушла с рассветом на 680 HP | 421 с | 424 | 35 |
| Анаконда | Эксперт | 3675 | за 10 мин снято ~1260 HP | 600 с | 256 | 30 |
| Бургер Смерти | Нормальный | 4000 | победа | 89.4 с | 199 | 4 |
| Бургер Смерти | Эксперт | 7000 | победа | 207.2 с | 262 | 12 |

Выводы:
- Время боя бота — при 100 % попаданий без уклонений. Живой игрок попадает и уклоняется, бой выходит в 3–4 раза дольше: Мать ~1,5 мин, Бургер ~5 мин на Нормальном и ~10–12 мин на Эксперте. Это ожидаемая кривая (средний босс → финальный).
- Бургер без уклонений наносит ~200–260 урона в минуту — без уворотов от лазера и волн его не пройти, это и задумано для финала.
- Анаконду одним факелом в руке за ночь не убить — нужны поставленные факелы (несколько зон света). На Эксперте это особенно заметно; правило «+75 % HP всем мобам» (pt124u) оставлено как есть.
- Цифры рецептов и урона не менялись.

## Известные недочёты v0.24
1. Мать блоков и Анаконда в сети бьют только хоста (старые мобы уже выбирают ближайшего игрока).
2. Сеть проверена двумя процессами на одной машине (mp_smoke и кадр 15_mp_two_players), настоящей партии по LAN ещё не было.
3. Анаконду на Эксперте одним факелом в руке за ночь не убить — нужны поставленные факелы.
4. В кадровых прогонах в чат сыплются «Новая веха» — в обычной игре вехи приходят по одной.
5. Старые `tools/boss_sim.gd` и `tools/anaconda_sim.gd` не запускаются (нет `set_seed`) — их заменил `tools/v024_balance.gd`.
6. В режиме без окна фоновая загрузка сцены не продвигается, поэтому там мир грузится сразу; полоса загрузки проверена только кадрами с окном.
7. Exe не запускался на настоящей Windows (проверка — запуск в Linux через `--main-pack`).
8. Бот 40 мин (BOT OK, 0 провалов, p99 17,6 мс): два долгих кадра 3,7 и 3,0 с на 29,8 игровой минуте — сразу после переноса башни 5×4×5 (100 блоков) из Сна в Явь. Стоит проверить в 0.25.
9. Недочёты v0.23 ниже (пп. 3–6, 8–9) в силе; блок в руке при замахе исправлен, мёртвый код носильщиков/boss_combat_sm убран.

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
