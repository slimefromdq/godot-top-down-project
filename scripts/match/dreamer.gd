extends Node2D
class_name Dreamer

# A team's sleeping Dreamer, in its Plaza: the match's goal. One per team
# (`team` &"a" Dawn or &"b" Dusk), placed by the map. It only acts while the
# MatchManager is PLAYING. Every number is in MatchRules (Dreamers, Wake,
# Buffs).
#
#   deposits   a carrier who can_deposit() inside deposit_radius hands over
#              one Mote per tick, highest value first. The first tick of a
#              visit comes after deposit_tick, each next one
#              deposit_tick_speedup times sooner (down to deposit_tick_min).
#              Leaving, dying or a pending jostle ends the visit; what went
#              in stays in.
#     bank     (own Dreamer) the team is paid bank_*_per_value, the depositor
#              a depositor_bonus_pct extra; the value fills Sweet Dreams:
#              every sweet_dreams_threshold, the whole team gets
#              sweet_dreams_status.
#     deliver  (enemy Dreamer) paid deliver_*_per_value; the value fills the
#              wake meter, which never drains on its own.
#   stirring   a full wake meter stirs it for stir_duration. The first
#              stir_grace seconds refuse every deposit. After that, one more
#              delivered Mote wakes it: its attackers win. Defenders inside
#              lullaby_radius fill the Lullaby (paused while a living
#              attacker is inside), banking here adds more. A full Lullaby
#              settles it at lullaby_reset_pct of the meter, running out of
#              time at timeout_reset_pct. Its defenders respawn faster
#              meanwhile.
#
# Signals carry no team (it's this Dreamer's); MatchManager relays them with
# the team. Cues (match profiles): deposit_tick, bank_complete,
# deliver_complete, sweet_dreams, wake_quarter, stir_start, lullaby_tick,
# settle, wake.

signal wake_changed(value: float)
signal stir_started
signal lullaby_changed(pct: float)
## how: &"lullaby" or &"timeout".
signal settled(how: StringName)
signal woke(attackers: StringName)
## One Mote went in. delivered = into the enemy's Dreamer. index counts up
## within a visit (for a rising chime).
signal deposit_ticked(hero: Hero, value: int, delivered: bool, index: int)
## A visit that deposited something ended. total = value deposited.
signal deposit_finished(hero: Hero, total: int, delivered: bool)
signal sweet_changed(value: float)
## The wake meter passed 25 / 50 / 75% (mark 0.25, 0.5, 0.75).
signal wake_milestone(mark: float)
signal sweet_dreams_granted

enum State { SLEEPING, STIRRING }

const GROUP := &"dreamers"
const SETTLE_LULLABY := &"lullaby"
const SETTLE_TIMEOUT := &"timeout"

## Debug overlay (F1 > Match): the look draws both rings strongly.
static var debug_rings: bool = false

@export var team: StringName = &"a"
@export var data: DreamerData

var state: State = State.SLEEPING
var wake: float = 0.0
## This team's banked value toward the next Sweet Dreams.
var sweet: float = 0.0
## 0..1 while stirring.
var lullaby: float = 0.0
var stir_left: float = 0.0
var grace_left: float = 0.0
## Minimap: a bigger diamond in the team's colour (`team`).
var minimap_icon_scale: float = 1.6
## Set when it wakes: the team that woke it (the winners).
var woken_by: StringName = &""

var _visits: Dictionary = {}    # Hero -> {timer, gap, index, total}
var _lullaby_cue_left: float = 0.0
var _body: StaticBody2D


static func find_for(tree: SceneTree, for_team: StringName) -> Dreamer:
	for node in tree.get_nodes_in_group(GROUP):
		if (node as Dreamer).team == for_team:
			return node
	return null


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"minimap_objectives")
	add_to_group(&"offscreen_arrows")
	if data == null:
		data = load("res://resources/match/dreamer.tres")
	_body = StaticBody2D.new()
	_body.name = "Body"
	_body.collision_layer = MapLayers.LOW_COVER
	_body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = data.body_radius
	shape.shape = circle
	_body.add_child(shape)
	add_child(_body)
	if data.look_scene != null:
		var look := data.look_scene.instantiate()
		add_child(look)
		if look.has_method(&"setup_dreamer"):
			look.setup_dreamer(self)
	var manager := get_manager()
	if manager != null:
		manager.register_dreamer(self)


func get_manager() -> MatchManager:
	return MatchManager.find(get_tree()) if is_inside_tree() else null


func get_rules() -> MatchRules:
	var manager := get_manager()
	return manager.get_rules() if manager != null else MatchRules.current()


func get_wake_ratio() -> float:
	return clampf(wake / get_rules().wake_meter_max, 0.0, 1.0)


func is_stirring() -> bool:
	return state == State.STIRRING


## Deposits are refused during the stir's grace.
func accepts_deposits() -> bool:
	return not (is_stirring() and grace_left > 0.0)


func is_depositing(hero: Hero) -> bool:
	return _visits.has(hero)


# --- Ticking ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var manager := get_manager()
	if manager == null or not manager.is_playing():
		return
	_tick_deposits(manager, delta)
	if is_stirring():
		_tick_stir(manager, delta)


func _tick_deposits(manager: MatchManager, delta: float) -> void:
	var rules := get_rules()
	for hero in manager.get_roster():
		var carrier := MoteCarrier.find_on(hero)
		var inside := hero.global_position.distance_to(global_position) <= rules.deposit_radius
		var can := inside and carrier != null and carrier.get_mote_count() > 0 and carrier.can_deposit() \
			and not carrier.is_jostle_pending() and accepts_deposits()
		if not can:
			_end_visit(hero)
			continue
		if not _visits.has(hero):
			_visits[hero] = {"timer": rules.deposit_tick, "gap": rules.deposit_tick, "index": 0, "total": 0}
		var visit: Dictionary = _visits[hero]
		visit.timer -= delta
		while visit.timer <= 0.0 and _visits.has(hero) and carrier.get_mote_count() > 0 and accepts_deposits():
			visit.gap = maxf(visit.gap * rules.deposit_tick_speedup, rules.deposit_tick_min)
			visit.timer += visit.gap
			_deposit_one(manager, hero, carrier, visit)
			if manager.state == MatchManager.State.ENDED:
				return
	for hero in _visits.keys():
		if not is_instance_valid(hero) or not manager.has_hero(hero):
			_visits.erase(hero)


func _end_visit(hero: Hero) -> void:
	var visit: Dictionary = _visits.get(hero, {})
	_visits.erase(hero)
	if visit.is_empty() or int(visit.total) <= 0 or not is_instance_valid(hero):
		return
	var delivered := hero.team != team
	deposit_finished.emit(hero, int(visit.total), delivered)
	var rules := get_rules()
	MatchManager.play_world_cue(self, &"deliver_complete" if delivered else &"bank_complete",
		{"position": global_position, "source": hero, "total": int(visit.total),
		"chord": rules.deliver_chord if delivered else rules.bank_chord})


func _deposit_one(manager: MatchManager, hero: Hero, carrier: MoteCarrier, visit: Dictionary) -> void:
	var taken := carrier.take_highest()
	if taken.is_empty():
		return
	var value: int = taken.value
	var rules := get_rules()
	var delivered := hero.team != team
	visit.index += 1
	visit.total += value
	var gold := value * (rules.deliver_gold_per_value if delivered else rules.bank_gold_per_value)
	var xp := value * (rules.deliver_xp_per_value if delivered else rules.bank_xp_per_value)
	manager.grant_team(hero.team, gold, xp, &"deliver" if delivered else &"bank")
	manager.grant_actor(hero, gold * rules.depositor_bonus_pct, xp * rules.depositor_bonus_pct, &"depositor_bonus")
	deposit_ticked.emit(hero, value, delivered, int(visit.index))
	MatchManager.play_world_cue(self, &"deposit_tick", {"position": hero.global_position, "source": hero,
		"index": visit.index, "pitch": rules.chime_pitch(int(visit.index)), "delivered": delivered,
		"target_position": global_position, "team": hero.team})
	if delivered:
		_on_delivered(manager, hero, value)
	else:
		_on_banked(manager, value)


func _on_delivered(manager: MatchManager, hero: Hero, value: int) -> void:
	if is_stirring():
		# Past the grace (deposits are refused during it): it wakes.
		state = State.SLEEPING
		woken_by = hero.team
		woke.emit(hero.team)
		MatchManager.play_world_cue(self, &"wake", {"position": global_position})
		manager.set_respawn_multiplier(team, 1.0)
		manager.end_match(hero.team)
		return
	set_wake(wake + value)


func _on_banked(manager: MatchManager, value: int) -> void:
	var rules := get_rules()
	# Banked value always counts toward Sweet Dreams, and at your own stirring
	# Dreamer it sings the Lullaby too.
	if is_stirring():
		_add_lullaby(value * rules.lullaby_per_banked_value)
	sweet += value
	while rules.sweet_dreams_threshold > 0.0 and sweet >= rules.sweet_dreams_threshold:
		sweet -= rules.sweet_dreams_threshold
		grant_sweet_dreams(manager)
	sweet_changed.emit(sweet)


## The whole team gets the Sweet Dreams buff.
func grant_sweet_dreams(manager: MatchManager = null) -> void:
	if manager == null:
		manager = get_manager()
	var rules := get_rules()
	if manager != null and rules.sweet_dreams_status != null:
		for hero in manager.get_roster(team):
			if not hero.health_component.is_dead():
				hero.status_component.apply(rules.sweet_dreams_status, hero, Vector2.ZERO, 1.0,
					rules.sweet_dreams_duration)
	sweet_dreams_granted.emit()
	MatchManager.play_world_cue(self, &"sweet_dreams", {"position": global_position})


## Set the wake meter (clamped); a full one starts a stir. Quarter marks
## play wake_quarter.
func set_wake(value: float) -> void:
	var rules := get_rules()
	var before := get_wake_ratio()
	wake = clampf(value, 0.0, rules.wake_meter_max)
	var after := get_wake_ratio()
	for mark in [0.25, 0.5, 0.75]:
		if before < mark and after >= mark:
			MatchManager.play_world_cue(self, &"wake_quarter", {"position": global_position, "mark": mark})
			wake_milestone.emit(mark)
	wake_changed.emit(wake)
	if wake >= rules.wake_meter_max and not is_stirring():
		start_stir()


func start_stir() -> void:
	var rules := get_rules()
	wake = rules.wake_meter_max
	state = State.STIRRING
	stir_left = rules.stir_duration
	grace_left = rules.stir_grace
	lullaby = 0.0
	_lullaby_cue_left = 0.0
	# The deposit that filled it stops here, like every other.
	for hero in _visits.keys():
		_end_visit(hero)
	var manager := get_manager()
	if manager != null:
		manager.set_respawn_multiplier(team, rules.stir_defender_respawn_mult)
	stir_started.emit()
	lullaby_changed.emit(lullaby)
	MatchManager.play_world_cue(self, &"stir_start", {"position": global_position, "duration": rules.stir_duration})


func _tick_stir(manager: MatchManager, delta: float) -> void:
	var rules := get_rules()
	stir_left -= delta
	grace_left = maxf(grace_left - delta, 0.0)
	var defenders := 0
	var contested := false
	for hero in manager.get_roster():
		if hero.health_component.is_dead() or hero.global_position.distance_to(global_position) > rules.lullaby_radius:
			continue
		if hero.team == team:
			defenders += 1
		else:
			contested = true
	if defenders > 0 and not contested:
		_add_lullaby(defenders * rules.lullaby_rate_per_defender * delta)
		_lullaby_cue_left -= delta
		if _lullaby_cue_left <= 0.0 and is_stirring():
			_lullaby_cue_left = 1.0
			MatchManager.play_world_cue(self, &"lullaby_tick", {"position": global_position, "pct": lullaby})
	if is_stirring() and stir_left <= 0.0:
		settle(SETTLE_TIMEOUT)


func is_lullaby_contested() -> bool:
	var manager := get_manager()
	if manager == null:
		return false
	for hero in manager.get_roster():
		if hero.team != team and not hero.health_component.is_dead() \
				and hero.global_position.distance_to(global_position) <= get_rules().lullaby_radius:
			return true
	return false


func _add_lullaby(amount: float) -> void:
	lullaby = clampf(lullaby + amount, 0.0, 1.0)
	lullaby_changed.emit(lullaby)
	if lullaby >= 1.0:
		settle(SETTLE_LULLABY)


## End the stir: back to sleep, the meter dropped to the matching share.
func settle(how: StringName) -> void:
	if not is_stirring():
		return
	var rules := get_rules()
	state = State.SLEEPING
	stir_left = 0.0
	grace_left = 0.0
	var pct := rules.lullaby_reset_pct if how == SETTLE_LULLABY else rules.timeout_reset_pct
	wake = rules.wake_meter_max * pct
	var manager := get_manager()
	if manager != null:
		manager.set_respawn_multiplier(team, 1.0)
	settled.emit(how)
	wake_changed.emit(wake)
	MatchManager.play_world_cue(self, &"settle", {"position": global_position, "how": how})


# --- HUD -------------------------------------------------------------------------

## The match HUD's off-screen arrow, for `viewer`: only while they carry
## Motes; bold for the enemy's Dreamer, soft for their own. {} = no arrow.
func offscreen_arrow_for(viewer: Node) -> Dictionary:
	var carrier := MoteCarrier.find_on(viewer)
	if carrier == null or carrier.get_mote_count() == 0:
		return {}
	var color := MatchManager.team_color(team)
	var own := CombatQueries.team_of(viewer) == team
	return {"color": Color(color, 0.55) if own else color, "scale": 0.8 if own else 1.25}


## The minimap's icon: a ring in the team's colour that fills with the wake
## meter, with a sun (Dawn) or moon (Dusk) inside, flashing while stirring.
func draw_minimap_icon(canvas: CanvasItem, at: Vector2, _viewer_team: StringName) -> void:
	var color := MatchManager.team_color(team)
	var flash := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0) if is_stirring() else 0.0
	canvas.draw_circle(at, 10.0, Color.BLACK)
	canvas.draw_circle(at, 8.5, Color(0.1, 0.1, 0.12).lerp(Color.WHITE, flash * 0.6))
	canvas.draw_arc(at, 7.0, -PI / 2, -PI / 2 + TAU * get_wake_ratio(), 20, color, 3.0)
	if team == &"a":
		canvas.draw_circle(at, 2.5, color)
	else:
		canvas.draw_circle(at, 3.0, color)
		canvas.draw_circle(at + Vector2(1.3, -1.0), 2.4, Color(0.1, 0.1, 0.12))
