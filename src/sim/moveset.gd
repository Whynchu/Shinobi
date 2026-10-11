## The complete set of moves one weapon character can perform.
##
## GDD 7.1 is explicit that a weapon is a move family and not a mesh: "Each
## added weapon requires an original move family, collision profile, cancel
## rules, sound set, hit reactions and boss coverage, not just a different
## mesh." This is that family, held in one place so that adding the odachi later
## is authoring a new moveset rather than editing the state machine.
##
## Every field may be null. The state machine asks a moveset what it has and
## falls back to a sensible simpler move rather than failing, so a half-authored
## weapon is playable while it is being built - which matters, because GDD 15.2
## wants the vertical slice out of the door early.
class_name Moveset
extends RefCounted

## Katana light chain: three hits (GDD 5.3). The last entry's `chain_next` is
## normally null, which ends the chain.
var light_chain: Array[AttackTable] = []

## Uncharged heavy. Pressed and released.
var heavy: AttackTable = null

## Released heavy after a full charge (GDD 5.2: charged heavy costs 32 and has
## high commitment).
var charged_heavy: AttackTable = null

## The wind-up that plays while the heavy button is held. If null, holding the
## button simply plays `heavy` and waits out its full duration.
var heavy_charge: AttackTable = null

## Directional dodge and the no-direction backstep.
var dodge: AttackTable = null
var backstep: AttackTable = null

## Movement-derived attacks. GDD 4.2 requires these to work from day one.
var running_attack: AttackTable = null
var dodge_attack: AttackTable = null
var backstep_attack: AttackTable = null
var crouch_attack: AttackTable = null
var jump_attack: AttackTable = null

## Landing.
var land_light: AttackTable = null
var land_heavy: AttackTable = null

## Standing up after a guard break.
var guard_break: AttackTable = null

## Reactions, indexed by Tuning.HurtLevel. These are how a hit *feels*, so they
## are authored per weapon family rather than shared globally (GDD 5.3).
var hurt: Dictionary = {}

## Dodge-attack follow-through after a successful timed guard.
var guard_counter: AttackTable = null


## The move that starts a light chain, or null if this weapon has no light.
func first_light() -> AttackTable:
	return light_chain[0] if not light_chain.is_empty() else null


## Walk a chain to its end, wrapping if the author chose to close the loop.
func next_light(current: AttackTable) -> AttackTable:
	if current != null and current.chain_next != null:
		return current.chain_next
	return first_light()


func reaction_for(level: Tuning.HurtLevel) -> AttackTable:
	return hurt.get(level, null) as AttackTable


## Every non-null move in this set. Used by a data test that asserts a weapon
## family is complete, and by telemetry to confirm a move was reachable.
func all_moves() -> Array[AttackTable]:
	var out: Array[AttackTable] = []
	for t in light_chain:
		if t:
			out.append(t)
	for t in [heavy, charged_heavy, heavy_charge, dodge, backstep, running_attack,
			dodge_attack, backstep_attack, crouch_attack, jump_attack,
			land_light, land_heavy, guard_break, guard_counter]:
		if t:
			out.append(t)
	for v in hurt.values():
		if v:
			out.append(v)
	return out


## Data problems across the whole family, each prefixed with the move it came
## from so a designer is told which asset to open.
##
## GDD 16's Gate A fails on "animations/hitboxes disagree". This is the cheap,
## headless half of that check: it catches a move whose windows are inconsistent
## or whose sweep is missing, which would otherwise surface as a combatant
## inexplicably taking no damage and take an afternoon to find.
func validate() -> Array[String]:
	var problems: Array[String] = []
	for move in all_moves():
		for p in move.validate():
			problems.append("%s: %s" % [move.id, p])

	# The light chain must terminate. A cycle in `chain_next` would let a player
	# hold the attack button forever without ever returning to neutral, and it
	# is not obvious from looking at any single move.
	var seen := {}
	var node := first_light()
	var guard := 0
	while node != null and guard < 64:
		if seen.has(node.id):
			problems.append("light chain loops back to '%s'" % node.id)
			break
		seen[node.id] = true
		node = node.chain_next
		guard += 1
	if guard >= 64:
		problems.append("light chain does not terminate")

	return problems


## One line per move: timings in ticks and seconds, reach, cost. This is the
## balancing sheet GDD 16 asks to be shared, printed from the same data the
## simulation runs, so the two cannot drift apart.
func report() -> Array[String]:
	var lines: Array[String] = []
	var width := 18
	for move in all_moves():
		lines.append(
			("%-" + str(width) + "s  total %3d  active %3d..%3d (%2d)  recover %3d  "
			+ "cancel %3d  cost %3d  dmg %3d  post %3d  fwd %.2f  arc %.2f")
			% [
				str(move.id),
				move.total_ticks,
				move.active_from, move.active_to, move.active_ticks,
				move.recovery_ticks,
				move.cancel_from,
				move.stamina_cost, move.damage, move.posture_damage,
				move.forward_reach(), move.sweep_arc_length(),
			]
		)
	return lines