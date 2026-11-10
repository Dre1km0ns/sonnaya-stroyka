# Передача работы — Сонная стройка v0.10

Обновлено: 10 ноября 2026, МСК. Текущий этап: 4 (entities/pickup/AI) завершён, extended smoke зелёный; большой suite запущен. Релиз v0.10 ЕЩЁ НЕ ГОТОВ.

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
| 1 | F3 debug (FPS, XYZ, направление, чанк); убрать toggle в настройках | Готово: F3, XYZ/направление/чанк, пункт настроек удалён |
| 2 | Дверь: grid alignment, lightweight mesh/material sharing, single box, направление/петля по игроку; измерить | Готово: сетка/поворот/шарнир, 12 треугольников и общие mesh/material/shape, тест 4 направлений |
| 3 | Полная русская консоль всех систем, описания/примеры/help/Tab | Основные системы готовы, help по-русски с примерами/Tab; новые transfer/water/chunks команды дополнять дальше |
| 4 | Terraria quick heal: первый подходящий слот по номеру, оба уровня в hotbar/quick slot | Готово: H первое зелье по индексу; оба уровня в хотбаре/quick-alias, ЛКМ выбранным зельем |
| 5 | Мечи 7/13/23 dmg; sword3 = sword2+5 scales на Станке, 700 durability, иконка/текстура; HP flag перенос на sword3, миграция старого sword2 | Готово: 7/13/23 урона, 700 прочности, рецепт sword2+5 scales на станке, флаг sword3 + alias sword2; старый флаг очищен |
| 6 | Инкрементальные блоки + dirty cells/chunks; обычные объединить в mesh/коллизии, интерактивы отдельно | Готово (smoke 10001–10006): dirty signals, batching, hidden-face mesh, X-merged collision, локальная замена интерактивов; smoke/метрики добавлены. Трансфер/ChunkManager отдельно впереди. |
| 7 | Единственная sync при переходе; симметричный sleep миров; lazy Dream | Готово: один signal sync, parent process-mode sleep обоих миров, lazy async Dream, parallel/legacy mapping |
| 8 | Per-chunk revisions, соседи, локальные snapshot, near/forward priority, adaptive insert budget | Готово: session epoch + chunk revisions, ближайшие/вперёд, adaptive 0.5–4ms insertion, bounded indexed snapshots, immutable caches, retired jobs |
| 9 | Вода только при изменении, coalesced/capped rebuild, inactive sleep, границы | Готово: только changed levels, coalesced dirty, ≤2 meshes/frame +1.5ms soft budget, indexed sources, save/reload flow, inactive sleep |
| 10 | Reagent без пустого process; local pickup, culling process/physics (не боссы), AI budget/stagger, local adjacent search | Готово: cached bounds/no process, local mask8 sphere query ≤64/1.5ms, batch inventory signals, full process+physics cull except bosses, cooperative A*/2ms and stagger, local125 nearest-block |
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
HANDOFF Drive: https://drive.google.com/file/d/19ID5k4BLkUQOg6GsxKgrMFj3I0NgmYtZ/view (этап 0; обновить в конце).
Релиз ZIP v0.10: ещё не создан.

## Этап 1: фактические изменения и результат
- `placed_cells_changed` обновляет только dirty cells; обычные блоки по чанкам (16×16), скрытые внутренние грани, коллизии объединены горизонтальными полосами; интерактивы отдельно. Удалены production full-rebuild из BuildController/дверей/уничтожения мобами/пробуждения.
- Picking/добыча BuildController распознают `placed_chunk`, рассчитывают клетку из точки+нормали. Мобы уже использовали этот алгоритм.
- Parse bad=0; первый smoke выявил нестабильность проверок физики открытой двери, повторный smoke зелёный (debug оставлен на случай повтора). Нужны повторные прогоны после двери/миров.
- 1000 последовательных размещений: CPU avg **7.429→2.612 ms**, p95 **14.156→4.940 ms**, max **22.162→9.029 ms**. Mesh/body **1000/1000→3/3**, nodes **3004→13**. Удаление p95 **13.320→5.215 ms**. Это этап 1, не финальная производительность.
- Walking software-renderer avg 39.919→47.760 ms (регрессия/шум; не утверждать оптимизацию FPS). Остальные этапы ещё не внедрены.
- Новые строки измерений в benchmarks/v0.10.json, лог /workspace/v010/suite_stage1.log. Extended suite всё ещё требует настоящую water fixture (старая water_cells=0 невалидна).
- Дальше: лёгкие двери + F3 + potion/sword3/миграция + русская консоль; затем ChunkManager/вода/AI/pickup/TransferPlan; в конце полный verification/pipeline.

## Этап 2: проверено
- Расширенный smoke `/workspace/v010/stage2_final_smoke.log`: все assertions зелёные, **0 ObjectDB leaks / 0 resources in use**, без engine/script errors. Короткие SFX реально воспроизводятся как PCM WAV; исходные Ogg сохранены, журнал/test IDs прежние. Устранили OggPacketSequencePlayback, не заглушали аудио и не скрывали warnings.
- Дверь: исходные bounds (-0.527778,-1,-0.133333), size (1.027778,2,0.266667) → ровно (-0.5,-1,-0.0625), size (1,2,0.125). Треугольники **240→12**, vertices **292→36**, первый mesh build **21.724→11.449 ms** (headless CPU, это не FPS-замер). 1 shared mesh/material/box, положение на грани сетки, шарнир в её углу; collision/4-facing/open-leaf/picking проверены.
- Quick-heal UI — alias первого potion-слота, не отдельное дублирующее хранилище; оба зелья можно положить мышью. H всегда наименьший индекс, выбранное ЛКМ использует выбранный тип. 20/40 HP, общий cooldown15s.
- Меч3: оригинальный jade/scales pixel icon и extruded mesh, recipe/durability/миграция в smoke10018–10020. В старом сейве `sword2_crafted` больше не включает усиление; новое поле `sword3_crafted` сохраняет факт крафта. Legacy console alias работает.
- Превью `/workspace/shots/v010_{f3,door_closed,door_open,scale_sword,inventory,console_help}.png` просмотрены: дверь/слоты/текст без наложений. Меч в руке показался крупным, после review уменьшены scale/поправлен grip; переснять на финальном проходе.
- Сгенерированная графика воспроизводится `python3 tools/make_v010_art.py`. Кредиты/PCM adaptation в assets/LICENSE.txt.
- Дальше этап 3: per-chunk revision + bounded snapshots + adaptive insertion + симметричный sleep/lazy Dream + coalesced/persistent water; затем AI/pickup и TransferPlan.

## Этап 3: проверено
- Новые smoke10025–10041: Dream до входа=0 чанков; один visibility/sync sequence на переход; inactive clock/loaded/water не меняются. World parent process_mode DISABLED, коллизии переключаются один раз. SaveSystem убрал повторы rebuild/visibility.
- Переход в новых мирах — parallel world coordinates; существующий сейв с незавершёнными dream_blocks без нового поля остаётся `legacy_workshop` у нуля, чтобы не потерять доступ. Console `mapping parallel|legacy_workshop`. Во время входа Dream больше нет 9 синхронных генераций, начальные чанки идут workers.
- `_generation_epoch` теперь только reset/session. Редактирование меняет revision своего чанка и граничных соседей, не отменяет дальний job. В smoke параллельно запущенные c1/c3: c1 отброшен, c3 вставлен.
- Пакеты snapshot: collected/eggs/dream removals индексированы по чанкам; 10001 collected IDs => **1 локально скопированная запись, 198–205µs**. Published procedural cache values помечены read-only рекурсивно в worker; каждый job владеет top-level maps и новым результатом, нет SceneTree/Node/RenderingServer/PhysicsServer в workers.
- `clear_all` перемещает in-flight jobs в retired без глобального join игрового кадра. Глобальный join остался только в teardown/явном тестовом load_all; ensure spawn chunk — единственная приоритетная sync safety операция. Terrain rebuilds асинхронны, старый mesh/collider живёт до готовности; logical removed проверяется сразу. Распад листвы стартует сразу независимо от готовности mesh.
- Вода: 30 активных клеток в новой fixture, граница x15/16 level6; idle rebuilds=0; повтор того же level не dirty; cap1/кадр, unload/reload и save проверены. `flowing_water` — optional save field, старые v0.9.1 сейвы читаются. Air geometry передаётся из worker, второй main-thread underground_air_cells устранён. Console `water stats|step`, `chunks revisions` и расширенные `chunks stats`.
- Hitch49 chunks (headless, 60fps cap): startup **93.033→28.045ms**, frame p95 **16.790→16.803ms**, max **16.818→16.960ms**, >33ms **0→0**, work p95 **1.398→1.633ms** (пока +17%, честно, не объявлять всё ускоренным), total **782.232→850.491ms**. Первичная версия с deep-copy кешей дала p95 2.885ms; замена на immutable sharing снизила до1.633ms. Финальный замер после entity cache ещё впереди.
- Последний лог `/workspace/v010/stage3_immutable_smoke.log`: asserts OK, engine/script errors и ObjectDB/resource leak warnings отсутствуют.
- Дальше этап4: ReagentNode bounds-cache/no process, локальный pickup с бюджетом, culler обоих process + исключить всех боссов, AI budget/stagger и локальный nearest block. Затем stage5 atomic TransferPlan/preview/results/3% mutation, полный performance suite/screenshots/version/release.

## Этап 4: проверено
- `/workspace/v010/stage4_extended.log`: полный smoke assertions OK, engine errors/ObjectDB leaks/resource-in-use отсутствуют.
- ReagentNode больше не создаёт Tag и не имеет `_process`; размер GLB кешируется один раз на тип. Pickup: Physics broadphase mask8 вместо перебора всех групп; могила получила лёгкий pickup proxy. Sphere radius1.7, ≤128 кандидатов / ≤64 попыток, soft budget1.5ms.
- 200 настоящих dropped stacks: **4 ticks / 4 inventory signals / max1.536ms**. Ничего не потеряно, pickup proxy могилы возвращает3 stone. В тестах добавлен physics-frame sync перед запросом новых коллайдеров (не ослабляли assert).
- Culler сохраняет и восстанавливает visible/process/physics; Мать и Анаконда исключены из distance-cull, но inactive-world sleep всё ещё действует. Проверены fake far entity + boss исключение + возврат близко.
- Runtime A* кооперативный: ≤32 nodes или500µs на порцию, фаза из3 кадров, общий soft budget2ms; движение/гравитация каждый physics frame, obstruction probe10Hz. Старый synchronous `find_path` только для явных tool/unit запросов, gameplay `follow_target` его не вызывает. nearest_adjacent_block проверяет125 локальных клеток вместо всей базы.
- Console: `pickup stats|collect`, `ai stats|budget`; Russian help/Tab.
- Полный обновлённый benchmark запущен в `/workspace/v010/suite_stage4.log` (взять результат/добавить JSON после завершения). Mass pickup теперь содержит и first-tick, и CPU sum / wall latency для всех300; не сравнивать64 с300 как одинаковые операции. Water row теперь содержит настоящую воду через границу, не water_cells=0.
- Дальше stage5: atomic TransferPlan + terrain-aware preflight + reserve/refund, anchor preview/highlight/cost/conflicts, wake result UI,7% rolls capped floor(3% structure), beacon+5dust. Затем финальные тесты/замеры/скрины/версия/README/CHANGELOG/main push/ZIP/Drive/one old ZIP trash.
