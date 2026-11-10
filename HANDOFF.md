# Передача работы — Сонная стройка v0.10

Обновлено: 10 ноября 2026, МСК. Текущий этап: 0 (аудит и baseline) завершён. Релиз v0.10 ЕЩЁ НЕ ГОТОВ.

## Проект и правила владельца
Godot sandbox/survival: игрок добывает в Яви, строит во Сне, якорями snapshot фиксирует существующие блоки и переносит их по тем же координатам в Явь. Не превращать игру в обычный Minecraft; сохранить механики и совместимость v0.9.1.
Репозиторий https://github.com/Dre1km0ns/sonnaya-stroyka, checkout `/workspace/sonnaya-stroyka`. Работа: `wip/v0.10`; исходный main `89cbb0d807041022accddd5a8837c3be90720359`. В main публиковать только после тестов и review.
Владелец разрешил v0.10 словом «работай». Для новых идей сначала список, затем ждать «работай»; сейчас выполнять только согласованный объём. Для каждой новой dev-функции добавлять консоль/help/Tab/тесты. Не трогать видео Drive. Не создавать отчётные Google Docs. HANDOFF обновлять после каждого этапа, commit+push WIP. Не сообщать «готово» для частичного результата.

## Источники и среда
Аудит прочитан полностью: `/workspace/v010/audit.txt`, копия `docs/audit_v0.10.txt` (582 строки). Правила: worker — только pure data, никаких SceneTree/Node/серверов; детерминизм; не ждать все workers в игровом кадре; измерять, не скрывать регрессии. Milestones/blueprints отложены.
Godot `/home/box/godot/godot` (4.7.2), Linux box. Компьютер владельца может быть offline, он не нужен. Все команды ниже запускать в checkout.

## Команды и pipeline
- Импорт: `/home/box/godot/godot --headless --editor --path . --import`
- Parse: `/home/box/godot/godot --headless --path . --script res://tools/parse_check.gd`
- Smoke: `/home/box/godot/godot --headless --path . --script res://scripts/smoke_test.gd`
- Hitch: `/home/box/godot/godot --headless --path . --script res://tools/chunk_hitch_probe.gd`
- Suite: `xvfb-run -a -s '-screen 0 1280x720x24' /home/box/godot/godot --path . --rendering-method gl_compatibility --script res://tools/v010_perf_suite.gd -- after`
- Скриншоты через main.gd: добавить `-- --shots010`; существующий пример `-- --door-shots`. Сохранять `/workspace/shots/v010_*.png`, открыть Read и исправить реальный вид.
- ZIP: Python zipfile всего checkout с префиксом `Сонная стройка v0.10/`, включить `.godot`, исключить каталог `.git`. Проверить testzip, включение cache, отсутствие .git.
- После smoke/preview: commit WIP, merge fast-forward в main, обычный push (не force). ZIP `/workspace/Сонная стройка v0.10.zip`.
- UploadFile: connection `user-Google-drive`, destination.folderId `1YW-aXo6q4BgBnnTx9frlZhIU1tosuMBJ`, name `Сонная стройка v0.10.zip`. Проверить metadata parents/size.
- Только после успешного upload ОДНА попытка trash_file старого ZIP `1HykoH2mUKmMj5fUmnNOzrkg1kJiX7r-U`. Вероятен отказ: общий доступ. Не повторять и не обходить.
- После этапа 0 загрузить HANDOFF как `HANDOFF Сонная стройка v0.10.md`, сохранить ссылку ниже. В конце загрузить актуальную копию и один раз попробовать убрать старую копию. Другие файлы не трогать.

## Согласованный объём и статус
| № | Задача | Статус |
|---|---|---|
| 0 | Аудит/измерения до изменений | Готово базово; нужны отдельные flowing-water / большая база / дверные замеры |
| 1 | F3 debug (FPS, XYZ, направление, чанк); убрать toggle в настройках | TODO |
| 2 | Дверь: grid alignment, lightweight mesh/material sharing, single box, направление/петля по игроку; измерить | TODO |
| 3 | Полная русская консоль всех систем, описания/примеры/help/Tab | TODO |
| 4 | Terraria quick heal: первый подходящий слот по номеру, оба уровня в hotbar/quick slot | TODO |
| 5 | Мечи 7/13/23 dmg; sword3 = sword2+5 scales на Станке, 700 durability, иконка/текстура; HP flag перенос на sword3, миграция старого sword2 | TODO |
| 6 | Инкрементальные блоки + dirty cells/chunks; обычные объединить в mesh/коллизии, интерактивы отдельно | В работе: заготовка `/workspace/v010/vox_header.gd`, НЕ ПРИМЕНЕНА |
| 7 | Единственная sync при переходе; симметричный sleep миров; lazy Dream | TODO |
| 8 | Per-chunk revisions, соседи, локальные snapshot, near/forward priority, adaptive insert budget | TODO |
| 9 | Вода только при изменении, coalesced/capped rebuild, inactive sleep, границы | TODO |
| 10 | Reagent без пустого process; local pickup, culling process/physics (не боссы), AI budget/stagger, local adjacent search | TODO |
| 11 | Preview якоря, подсветка/счётчик/стоимость/конфликты; atomic TransferPlan; wake result UI | TODO |
| 12 | Шанс мутации 7% на блок, cap около 3% структуры, маяк, instability | TODO |
| 13 | Полный набор регрессии/измерений, old save, leaks, screenshots, changelog, доставка | TODO |

## Baseline / обнаружено
Сырые логи `/workspace/v010/baseline_*.log`, `/workspace/v010/suite_before.log`; числа в `benchmarks/v0.10.json`.
- 100/500/1000 блоков: sum CPU 87.587 / 1803.805 / 7429.141 мс; per-op p95 1.536 / 6.689 / 14.156 мс. 1000 блоков = 1000 meshes, 1000 bodies, 3004 nodes.
- Walking с физикой: avg39.919, p95 45.035, max50.167 мс (llvmpipe).
- 7 врагов: p95 53.176, единичный max786.512 мс; boss p95 48.656, max76.542.
- Первый вход в Dream28.144 мс, второй3.685; wake4.341/3.286.
- 300 pickups:29.065 мс. Water suite water_cells=0, НЕ СЧИТАТЬ доказательством активной воды.
- Smoke asserts OK, но при выходе нестабильные Ogg playback leaks (последний baseline28 Objects/6 resources). Обязательно исправить, не скрывать warning.
- Vox rebuild вызывается из BuildController, GameState door/destroy, world_changed, wake_resolved и WorldSwitcher напрямую: O(N) создание Node на действие и 3 sync на wake.
- ChunkManager глобальный epoch на каждый edit, Wake продолжает process в Dream, `_water_on_chunk_loaded` заново считает underground air на main, `_water_src` unload глобальный.
- Door уже был 240 triangles + shared cached mesh, главный подозреваемый slowdown — rebuild мира, не обязательно glTF. Измерить и честно описать.
- Heal2 разрешён общим slot UI, но нет use action для выбранной хилки; use_heal выбирает heal1 прежде heal2 независимо от низшего слота. Нужны тесты обоих.

## Точные следующие шаги
1. Применить инкрементальную VoxelWorld заготовку, добавить GameState placed_cells_changed и адаптировать targeting merged collider. Убрать production rebuild на действие.
2. Parse + smoke, исправлять реальные регрессии, обновить этот файл, commit/push WIP.
3. Последовательно пункты7–10 с отдельными тестами; затем gameplay1–5 и TransferPlan/UX11–12. Не переписывать весь проект одним махом.
4. Добавить suite реальные water borders, 1000-block base render, doors, fast streaming/cancel, 7 mobs/boss/pickup, old save. Before fixture ещё доступен на git main.
5. Финальные screenshots review, зелёный smoke без leaks, changelog, main push, ZIP/upload/trash one attempt; в результате все цифры/ограничения и ссылки.

## Внешние артефакты
HANDOFF Drive: первая загрузка ожидается сразу после коммита этапа 0.
Релиз ZIP v0.10: ещё не создан.
