# Передача работы — Сонная стройка v0.21 (в работе)

Обновлено: 19.11.2026, МСК. Циклы 1–2 из 4 закончены, дальше цикл 3 («багфикс → промежуточная аналитика → бета-анализ»). Публикация на Drive будет только после цикла 4: ZIP «Сонная стройка v0.21.zip» в папку 1YW-aXo6q4BgBnnTx9frlZhIU1tosuMBJ. В циклах 1–3 на Drive ничего не загружать, видео владельца не трогать, отчётных документов на Drive не создавать.

## Репозиторий
- https://github.com/Dre1km0ns/sonnaya-stroyka, checkout `/workspace/sonnaya-stroyka`.
- `main` = v0.20 (e0823fe) плюс `export_presets.cfg` (cc69fe4). Ветки v0.x были линейными, поэтому main продвинут фаст-форвардом; PR #1–#2 влились сами, #3–#10 закрыты с комментарием.
- Работа идёт в `wip/v0.21`, push после каждого этапа. В main попадёт после цикла 4.

## Правила владельца
- Каждой новой функции нужна консольная команда DevSeed (6767676767) с русской справкой, примерами и Tab.
- Отчётных документов не создавать, если владелец не попросил.
- Новый большой список идей: сначала изложить понимание и ждать «работай».
- Фиксы не имитировать: каждый подтверждать смоуком, ботом или кадрами.

## Что сделано (цикл 1)
См. CHANGELOG_V0.21.md. Главное:
- фокус HUD на обучении;
- строгий порядок шагов с ранним зачётом;
- верстак в слоте 5;
- подсказка добычи только в Яви;
- табличка лагеря как табличка в мире;
- HP-полоски без раздувания и без дубля у боссов;
- оболочка Матери блоков (слой 64);
- защита music_controller вне дерева;
- уникальные UID;
- непрозрачные настройки;
- читаемый заголовок мира;
- утечка аудио при выходе устранена (было 8 ресурсов, стало 0; `GameSettings.safe_quit`);
- 14 консольных команд Сна;
- небо, острова и пылинки Сна.

## Где код
- Обучение: `scripts/game_state.gd`. Блок «v0.20: обучение во Сне»: `TUTORIAL`, `tutorial_event`, `tutorial_focus`, `tutorial_step_id`, `tutorial_early`.
- HUD: `scripts/hud.gd` (заголовок, осознанность, полоса босса), `scripts/objective_panel.gd`, `scripts/context_hints.gd`, `scripts/anchor_system.gd` (якорная панель), `scripts/dream_tools.gd` (отмена/возврат).
- Табличка лагеря и подключение декора Сна: `scripts/main.gd` (`CampSign`, `DreamScenery`).
- Декор Сна: `scripts/dream_scenery.gd`, `shaders/dream_sky.gdshader`. Небо переключает `scripts/world_switcher.gd`.
- Оболочка Матери: `scripts/block_mother.gd` (`_add_shell`, `shell_radius`). Маска игрока — `scripts/player_controller.gd`.
- HP-полоски: `scripts/enemy_visuals.gd`.
- Аудио при выходе: `scripts/game_settings.gd` (`safe_quit`, `_track_audio`, `_release_audio`). Выход из меню, закрытие окна и бот идут через `safe_quit`.
- Консоль: `scripts/dev_console.gd` (`COMMAND_HELP`, `_v010_command` → `_dream_cmd`).
- Смоук: `scripts/smoke_test.gd`, функция `_v021_checks` (21000–21022).

## Как собрать и проверить (Godot 4.7.2: /home/box/godot/godot)
- Импорт: `godot --headless --editor --path . --import`
- Parse: `godot --headless --path . --script res://tools/parse_check.gd` (ожидается `PARSE DONE bad=0`)
- Смоук: `godot --headless --path . --script res://scripts/smoke_test.gd`. Для чистых сейвов ставить `XDG_DATA_HOME=/tmp/...`. Последняя строка `SMOKE: OK …`.
- Бот-прогон: `godot --headless --path . --fixed-fps 60 -s res://tools/v020_bot.gd -- --minutes=40` (около 10 минут реального времени). Бот перезаписывает `benchmarks/v020_bot.json`, поэтому результат цикла копировать в `benchmarks/v021c1_bot.json`, а v0.20 восстанавливать. Если `--minutes` меньше 6, вех «рассвет» бот честно не дождётся: это ограничение бота, не баг.
- Кадры: `DISPLAY=:77 godot --path . --rendering-method gl_compatibility -s res://tools/v021_screens.gd` пишет в `/workspace/shots/v021c1/`. Xvfb :77 1280×720.
- Windows .exe: `godot --headless --export-release "Windows Desktop" build/windows/SonnayaStroyka.exe`. Проверка: `godot --headless --main-pack build/windows/SonnayaStroyka.exe --script res://scripts/smoke_test.gd`.
- ZIP (только цикл 4): весь checkout с префиксом `Сонная стройка v0.21/`, `.godot` включить, `.git` исключить. Проверить testzip.

## Цикл 2: сделано
См. CHANGELOG_V0.21.md, раздел «Цикл 2». Где код:
- Фокус HUD: `hud.gd` — `tutorial_hides_wake_tools`, `_update_tutorial_focus`, подложка подписи в `_style_clarity`.
- Подсказка якоря: `anchor_system.gd` (`tut_anchor`).
- Цели Сна в Яви: `objectives.gd` (флаг `"dream":true`) и `objective_panel.gd`.
- Флора Сна: `dream_scenery.gd` — `_build_flora`, `rebuild_flora`, `flora_counts`.
- Мать: `block_mother.gd` — `MELEE_RANGE` 2.9, `_add_shell` r ≤ MELEE_RANGE−0.5.
- Экран загрузки: `main_menu.gd` (`_show_loading`).
- Иконка: `assets/icon/`, `tools/gen_icon.py`, `export_presets.cfg` (`application/icon`, `modify_resources=true`).
- Консоль: команды `dreamdecor` и `hudfocus` в `dev_console.gd`.
- Шаблоны экспорта Windows 4.7.2 лежат в `~/.local/share/godot/export_templates/4.7.2.stable/`. Если их нет, скачать из tpz только два windows-файла, через HTTP Range (скрипт /tmp/rz.py, логика описана в отчёте цикла 2).

## Что осталось
- Цикл 3: исправить список ниже, затем снова провести бета-анализ.
- Цикл 4: финальные фиксы, перевод v0.21 в main, exe, ZIP на Drive.

## Бета-анализ после цикла 2 (план цикла 3)
1. Вплотную к Матери (2,8 м) её тело по-прежнему закрывает большую часть экрана. Нужна камера боя: немного отодвинуть её или расширить FOV рядом с боссом. Это решение по дизайну.
2. После обучения слева четыре блока подряд: осознанность, цель, карточка-шпаргалка клавиш Сна и чат. Шпаргалка дублирует цель — показывать её один раз и коротко.
3. Во время обучения в чат сыплются «✓ Построй во Сне 5+ блоков» и прочие уведомления целей, которые дублируют прогресс обучения.
4. Острова Сна следуют за камерой, долететь до них нельзя. Для летающего игрока это странно. Нужны дальние неподвижные острова или честная подпись «мираж».
5. У земли Сна прежняя текстура и нет рельефа. Флора помогает, но рельефа по-прежнему нет.
6. Экран «Загрузка мира» не снят кадром: кадры делаются после смены сцены.
7. Exe не запускался на Windows, FPS на реальной видеокарте не замерен — это проверка для владельца.
8. В сцене Сна висит неиспользуемая скрытая надпись «Hint», это мусор.
9. p99 кадра в бот-прогоне 20 мс (было 18). Пересборка флоры занимает 3 мс; проверить, не она ли причина.
