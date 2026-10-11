## Scroll reward offers (GDD 6.4).
##
## GDD 6.4 is unusually specific, and this file exists to implement it exactly:
##
##     "Present exactly three intelligible scroll choices. Favor one option
##      relevant to the player's current active art, one cross-archetype option
##      and one wildcard; avoid deceptive rewards unusable with the equipped
##      weapon. Repeated acquisition upgrades a scroll along a discrete track
##      (I / II) rather than stacking arbitrary multipliers."
##
## So an offer is three slots with three different jobs, always the same three
## jobs, in the same order, every time - and `RunTuning.OFFER_SIZE` is 3 rather
## than a tunable because the sentence says "exactly three".
##
## ## What this file deliberately does not own
##
## **The scroll catalogue.** Another lane implements the scrolls and owns their
## ids. Nothing here names a scroll, defines one, or knows what any of them do.
## Scroll ids are opaque `StringName` keys and the selection logic never looks
## inside one - not even to guess whether two ids are related.
##
## That constraint is what forces the design below, and the design is better for
## it. Relevance and cross-archetype membership are *semantic* judgements about
## a scroll, so they cannot honestly be computed by a module that is forbidden
## from knowing what a scroll is. The caller states them, as data, on a
## `Loadout`, and this file does the part that is genuinely mechanical and
## genuinely a rule: filter out what cannot work, then pick one of each kind of
## option, deterministically, without repeats.
##
## GDD 6.3's recipes (Ghost Counter, Storm Merchant, Iron Crane) are what a
## `Loadout.affinity` list looks like when someone has done the reading; the
## Scrollkeeper lane owns that mapping. If it never arrives, the RELEVANT slot
## degrades to a wildcard and the offer is still three intelligible choices,
## which is the floor GDD 6.4 actually sets.
class_name RewardOffer
extends RefCounted


## The three jobs an offer always fills. GDD 6.4's "Favor one option relevant
## to the player's current active art, one cross-archetype option and one
## wildcard."
enum Role { RELEVANT, CROSS_ARCHETYPE, WILDCARD }


## One presented option.
class Choice extends RefCounted:
	## An opaque key owned by the scroll lane.
	var scroll_id: StringName = &""
	var role: RewardOffer.Role = RewardOffer.Role.WILDCARD
	## GDD 6.4: "Repeated acquisition upgrades a scroll along a discrete track
	## (I / II)". Owning a scroll never removes it from the pool - it changes
	## what taking it means - so this flag is what the UI needs to render "I ->
	## II" rather than a second copy.
	var is_upgrade := false


## Everything the offer logic is allowed to know about the player.
##
## Deliberately a bag of lists rather than a scroll object. Each list is an
## assertion made by a caller that *does* know what scrolls are, and every one is
## optional: a missing list degrades that slot rather than breaking the offer.
class Loadout extends RefCounted:
	## GDD 7.1's weapon roster. Scrolling is not in it, but "avoid deceptive
	## rewards unusable with the equipped weapon" is, so the weapon is what the
	## caller filters `blocked` against.
	var weapon: StringName = &""

	## GDD 6.1: the player carries one active art and two passive scrolls.
	var active_art: StringName = &""
	var passives: Array[StringName] = []

	## Scrolls already carried this run. GDD 3.4 wipes these on death.
	var owned: Array[StringName] = []

	## Scroll ids that play off `active_art`. Empty when there is no active art,
	## which is a real state rather than a broken one - a player who has not
	## taken an art has nothing for an option to be relevant *to*, and the
	## RELEVANT slot degrades honestly instead of inventing a relationship.
	var affinity: Array[StringName] = []

	## Scroll ids that work regardless of what the player is running. These are
	## the cross-archetype options: useful to a build that is not the one being
	## assembled, which is GDD 6.4's "one cross-archetype option".
	var universal: Array[StringName] = []

	## Scroll ids that cannot work with `weapon`. GDD 6.4 calls these deceptive
	## and they are removed before anything is drawn, so an offer can never
	## contain one.
	var blocked: Array[StringName] = []

	## GDD 18 links every result to "a run seed and ability loadout", so the
	## loadout needs an identity that is a function of what is equipped and not
	## of object addresses. Used to salt the reward stream.
	func fingerprint() -> String:
		return "%s|%s|%s|%s|%s" % [
			weapon,
			active_art,
			Array(passives).map(func(v: StringName) -> String: return String(v)),
			Array(owned).map(func(v: StringName) -> String: return String(v)),
			Array(blocked).map(func(v: StringName) -> String: return String(v)),
		]

	## GDD 3.4: on death the build vanishes and the player restarts from the
	## dojo with nothing carried in.
	func reset_for_run() -> void:
		active_art = &""
		var none: Array[StringName] = []
		passives = none.duplicate()
		owned = none.duplicate()


## Build one offer. Returns `RunTuning.OFFER_SIZE` choices whenever the pool can
## supply that many usable scrolls, which is the caller's responsibility to
## guarantee - `RunDirector` refuses to open a reward on a thinner pool, so the
## failure is reported as a content fault rather than shipped as a two-button
## prompt in front of a player.
##
## Deterministic in `rng`: same seed stream plus same loadout gives the same
## three ids in the same order (GDD 8.4 lists reward offers under the seed).
static func build(rng: RandomNumberGenerator, pool: Array[StringName], loadout: Loadout) -> Array:
	var usable := usable_pool(pool, loadout)
	_shuffle(rng, usable)

	var out: Array = []
	var taken_ids: Array[StringName] = []
	var any: Array[StringName] = []

	# Slot 1: relevant to the active art.
	_take(usable, taken_ids, loadout.affinity, out, Role.RELEVANT, loadout)
	# Slot 2: cross-archetype, so the offer can seed a *different* build as well
	# as finish this one. GDD 6.4 asks for it precisely so an offer is not three
	# variations on the plan the player already has.
	_take(usable, taken_ids, loadout.universal, out, Role.CROSS_ARCHETYPE, loadout)
	# Slot 3: wildcard.
	_take(_unowned_first(usable, loadout), taken_ids, any, out, Role.WILDCARD, loadout)

	# Backfill. Only reached when a pool is thin or the caller's affinity and
	# universal lists are narrower than the offer; the slot is labelled WILDCARD
	# because that is what it honestly is.
	while out.size() < RunTuning.OFFER_SIZE:
		if not _take(usable, taken_ids, any, out, Role.WILDCARD, loadout):
			break
	return out


## The scrolls a player could legitimately be offered: the pool minus the
## deceptive ones, de-duplicated, in authored order.
##
## De-duplication matters more than it looks. GDD 6.1 says new scroll *types*
## join the pool when discovered, and a pool assembled by appending to a save can
## easily contain the same id twice; showing a player the same scroll in two
## slots of a three-scroll offer is a bug that looks like a design.
static func usable_pool(pool: Array[StringName], loadout: Loadout) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in pool:
		if id.is_empty() or out.has(id):
			continue
		if loadout.blocked.has(id):
			continue
		out.append(id)
	return out


## Fisher-Yates on a copy of the pool. `Array.shuffle()` would be shorter and
## wrong: it draws from the *global* RNG, which would make a reward offer depend
## on whatever else in the process ran first (GDD 8.4).
static func _shuffle(rng: RandomNumberGenerator, ids: Array[StringName]) -> void:
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := ids[i]
		ids[i] = ids[j]
		ids[j] = tmp


## GDD 6.4's discrete upgrade track means an owned scroll stays eligible, but an
## offer made entirely of upgrades has no decisions in it. Unowned first,
## stable within each group so the authored pool order still breaks ties.
static func _unowned_first(ids: Array[StringName], loadout: Loadout) -> Array[StringName]:
	if not RunTuning.PREFER_UNOWNED_WILDCARD:
		return ids
	var fresh: Array[StringName] = []
	var owned: Array[StringName] = []
	for id in ids:
		if loadout.owned.has(id):
			owned.append(id)
		else:
			fresh.append(id)
	fresh.append_array(owned)
	return fresh


static func _take(
	candidates: Array[StringName],
	taken: Array[StringName],
	preferred: Array[StringName],
	out: Array,
	role: Role,
	loadout: Loadout
) -> bool:
	for id in candidates:
		if taken.has(id):
			continue
		if not preferred.is_empty() and not preferred.has(id):
			continue
		var c := Choice.new()
		c.scroll_id = id
		c.role = role
		c.is_upgrade = loadout.owned.has(id)
		out.append(c)
		taken.append(id)
		return true
	return false


static func role_name(role: Role) -> String:
	match role:
		Role.RELEVANT: return "relevant"
		Role.CROSS_ARCHETYPE: return "cross-archetype"
		_: return "wildcard"


## Ids only, for a test or a log line.
static func ids(offer: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for c in offer:
		out.append((c as Choice).scroll_id)
	return out
