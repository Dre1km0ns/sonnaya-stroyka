extends RefCounted
## v0.12: общая боевая машина боссов + контроль эффектов (SLOW / EXPOSED / STUN).
## Фазы: IDLE → TELEGRAPH → ATTACK → RECOVERY → VULNERABILITY → TRANSITION.
## Допускаются индивидуальные состояния; эта оболочка даёт:
##   — конечные таймеры и failsafe (состояние не может длиться бесконечно);
##   — защиту от повторного запуска той же атаки;
##   — идентификаторы ударов, чтобы один удар не наносил урон каждый кадр;
##   — стан ТОЛЬКО от именованных событий, с иммунитетом. Свет не обновляет стан.

enum Phase { IDLE, TELEGRAPH, ATTACK, RECOVERY, VULNERABILITY, TRANSITION, CUSTOM }

const STUN_DEFAULT := 0.75
const STUN_IMMUNITY_DEFAULT := 2.5
const SLOW_DEFAULT := 0.65          # 35% замедление
const EXPOSED_DEFAULT := 3.0
const MAX_STATE_DEFAULT := 12.0

var phase: int = Phase.IDLE
var state_name: String = "IDLE"
var state_time: float = 0.0
var state_max: float = MAX_STATE_DEFAULT
var attack_id: String = ""
var last_attack_id: String = ""
var attack_cd: Dictionary = {}       # id -> remaining
var hits_done: Dictionary = {}       # hit_id -> true (на время атаки)
var reentry_guard: bool = false

var stun_t: float = 0.0
var stun_immune_t: float = 0.0
var stun_source: String = ""
var stun_events: int = 0
var stun_blocked: int = 0
var slow_t: float = 0.0
var slow_factor: float = 1.0
var exposed_t: float = 0.0
var light_stun_attempts: int = 0     # диагностика: сколько раз свет пытался станить (должно быть 0)

func tick(delta: float) -> void:
	state_time += delta
	stun_t = maxf(0.0, stun_t - delta)
	# Иммунитет тикает и во время стана: окно 2–3 с от момента ПРИМЕНЕНИЯ, а не от конца стана.
	stun_immune_t = maxf(0.0, stun_immune_t - delta)
	if stun_t <= 0.0 and stun_source != "" and stun_immune_t <= 0.0:
		stun_source = ""
	# SLOW: если не обновлять (duration-based) — просто истекает. Refresh через apply_slow.
	slow_t = maxf(0.0, slow_t - delta)
	if slow_t <= 0.0:
		slow_factor = 1.0
	exposed_t = maxf(0.0, exposed_t - delta)
	var expired: Array = []
	for k in attack_cd.keys():
		attack_cd[k] = float(attack_cd[k]) - delta
		if float(attack_cd[k]) <= 0.0:
			expired.append(k)
	for k in expired:
		attack_cd.erase(k)


func enter(name: String, shared_phase: int, max_time: float = MAX_STATE_DEFAULT) -> void:
	state_name = name
	phase = shared_phase
	state_time = 0.0
	state_max = maxf(0.2, max_time)
	reentry_guard = true
	hits_done.clear()
	if shared_phase != Phase.ATTACK:
		attack_id = ""


func timed_out() -> bool:
	return state_time >= state_max


func begin_attack(id: String, cooldown: float = 0.0) -> bool:
	## Защита от повторного запуска той же атаки, пока она уже идёт или на КД.
	if attack_id == id and phase == Phase.ATTACK:
		return false
	if float(attack_cd.get(id, 0.0)) > 0.0:
		return false
	attack_id = id
	last_attack_id = id
	if cooldown > 0.0:
		attack_cd[id] = cooldown
	return true


func end_attack() -> void:
	attack_id = ""


func can_hit(hit_id: String) -> bool:
	## Один удар — один раз. Повторный вызов в том же состоянии возвращает false.
	if hits_done.get(hit_id, false):
		return false
	hits_done[hit_id] = true
	return true


func apply_slow(factor: float, duration: float) -> void:
	slow_factor = clampf(factor, 0.2, 1.0)
	slow_t = maxf(slow_t, duration)


func clear_slow() -> void:
	slow_t = 0.0
	slow_factor = 1.0


func apply_exposed(duration: float) -> void:
	exposed_t = maxf(exposed_t, duration)


func is_slowed() -> bool:
	return slow_t > 0.0 and slow_factor < 0.999


func is_exposed() -> bool:
	return exposed_t > 0.0


func is_stunned() -> bool:
	return stun_t > 0.0


func is_stun_immune() -> bool:
	return stun_immune_t > 0.0


func speed_scale() -> float:
	if is_stunned():
		return 0.0
	return slow_factor if is_slowed() else 1.0


func try_stun(duration: float, source: String, immunity: float = STUN_IMMUNITY_DEFAULT) -> bool:
	## Стан только от конкретного события. Не продлевается повторным вызовом.
	## source "light" / "crossfire" / "torch_field" отвергается всегда — это и была причина вечного стана.
	if source in ["light", "crossfire", "crossfire2", "crossfire3", "torch_field", "held"]:
		light_stun_attempts += 1
		stun_blocked += 1
		return false
	if is_stunned() or is_stun_immune():
		stun_blocked += 1
		return false
	stun_t = clampf(duration, 0.15, 1.5)
	stun_immune_t = maxf(immunity, stun_t)
	stun_source = source
	stun_events += 1
	return true


func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"state": state_name,
		"state_time": snappedf(state_time, 0.01),
		"attack": attack_id,
		"stun_active": is_stunned(),
		"stun_t": snappedf(stun_t, 0.01),
		"stun_immune": is_stun_immune(),
		"stun_immune_t": snappedf(stun_immune_t, 0.01),
		"stun_source": stun_source,
		"stun_events": stun_events,
		"stun_blocked": stun_blocked,
		"light_stun_attempts": light_stun_attempts,
		"slow": is_slowed(),
		"slow_factor": slow_factor,
		"exposed": is_exposed(),
		"exposed_t": snappedf(exposed_t, 0.01),
	}
