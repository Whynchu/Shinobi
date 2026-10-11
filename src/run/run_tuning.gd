## Generation constants for the run layer (GDD 8).
##
## Everything that decides *what* a run contains lives here rather than inside
## the generator, for the same reason `src/sim/tuning.gd` exists: balance work
## needs one home, and a value that traces to a numbered GDD table is a value
## somebody can check rather than guess at.
##
## Two groups of numbers live here and they are deliberately not the same kind
## of thing:
##
##   * GENERATION WEIGHTS - how often a node type is *rolled*. GDD 8.2 is
##     explicit that its percentages "are generation weights, not rigid room
##     counts", so nothing in this group is a promise about a finished run.
##   * GUARANTEES - the hard constraints of the same section, which override a
##     roll. An act that reaches its boss with no healing shrine and no build
##     reward is a broken act, and no amount of statistical correctness
##     compensates. A constraint that can be outvoted by a dice roll is not a
##     constraint.
##
## The layer is node-free and holds no engine type at all, exactly like
## `src/sim/` (Docs/ARCHITECTURE.md, section 2). That is what lets a thousand
## seeded runs be generated and checked in a headless process with no window,
## no renderer and no scene tree.
class_name RunTuning
extends RefCounted


# --- Act shape (GDD 3.2, [TEST]) -----------------------------------------------

## Three acts, one boss each. GDD 3.2's run outline.
const ACT_COUNT := 3

## GDD 3.2, "Encounters before boss": I 5-7, II 6-8, III 7-9. Indexed by act.
## These bound the number of encounters on *every* path through an act, not the
## number of encounter rooms that exist in it: a fork the player can take the
## long way round must not push a short act below the band, and a second branch
## must not push it above.
const ACT_ENCOUNTER_MIN := [5, 6, 7]
const ACT_ENCOUNTER_MAX := [7, 8, 9]

## GDD 8.2: "Boss, entrance and tutorial nodes are injected separately." Only
## Act I gets a tutorial node; GDD 14 lists the tutorial lessons and GDD 3.2
## opens Act I on them, so Acts II and III injecting one would be padding the
## start of two acts whose problem is depth rather than instruction.
const TUTORIAL_ACTS := [true, false, false]

## GDD 3.2's "Primary learning" per act, carried on the run so telemetry and the
## death readout (GDD 3.4) can say what the act was trying to teach.
const ACT_THEME := [
	"spacing, basic defense, terrain",
	"flanking, elevation and build synergies",
	"advanced tells, elites and resource decisions",
]


# --- Acts with authored room content (GDD 9) ----------------------------------

## Regions per act, most-used first. GDD 8.1: rooms are labelled with a region,
## and the route graph picks compatible rooms.
##
## Act I carries two sub-regions because GDD 9.1 describes the Bamboo Grove as
## distinct spaces - bamboo clearings and shallow water behave differently and
## are not the same room with a different prop. Acts II and III are empty
## because their room catalogues are not written: their *graphs* still generate
## correctly and still satisfy every guarantee below, but their nodes carry no
## room id and `RoomCatalog.assigns_rooms_for(act)` reports false. Filling them
## in is content work, not a code change to this file.
const ACT_REGIONS := [
	[&"bamboo_grove", &"stream_shallows"],
	[],
	[],
]

## Relative pull of each region within its act, parallel to ACT_REGIONS. The
## grove is the act's body; the shallows are the texture change that stops a
## seven-room act reading as one room seven times.
const ACT_REGION_WEIGHTS := [
	[3, 1],
	[],
	[],
]


# --- Difficulty budgets (GDD 8.1 / 8.3) ---------------------------------------

## GDD 8.1 calls difficulty a budget and GDD 8.3 gives every authored room one.
## The scale here is 1 (a corridor with one Foot Soldier) to 5 (an elite
## challenge or a boss arena). It is deliberately coarse: it is an authoring
## label for "how much is in here", not a simulation quantity, and a finer scale
## would imply precision the designers have not authored.
const BUDGET_MIN := 1
const BUDGET_MAX := 5

## Budget band for an early encounter in an act. Kept separate from the middle
## band because GDD 3.3 opens with a standard fight: an act that opens on its
## hardest room teaches spacing by ambush.
const BAND_EARLY := [1, 2]
const BAND_MIDDLE := [2, 3]
const BAND_LATE := [3, 4]
## An elite challenge is always the top of the scale - that is what makes it
## read as an elite on the map without needing a separate difficulty channel.
const BAND_ELITE := [5, 5]

## Normalised positions at which an act moves from one band to the next.
const EARLY_UNTIL := 0.34
const MIDDLE_UNTIL := 0.70

## A room at or above this budget counts as *high difficulty* even when it is an
## ordinary combat room. GDD 8.2's "no two consecutive mandatory high-difficulty
## nodes" is about the player's experience, not about node-type labels: a
## hand-authored budget-4 room full of Spear Sentries is a high-difficulty room
## even though the generator rolled STANDARD_COMBAT for it. If the rule were
## implemented as "no two elites in a row" it would pass on runs that violate
## the thing the rule is for.
const HIGH_DIFFICULTY_BUDGET := 4

## Non-combat rooms: a shrine, a merchant or a story beat. Their budget is
## whatever incidental resistance the art needs, never a fight's worth.
const BAND_SERVICE := [1, 2]
const BAND_STORY := [1, 3]


# --- Node distribution (GDD 8.2, [TEST]) --------------------------------------

## GDD 8.2's table, verbatim. Keyed by the `RunGraph.Kind` *ordinal* rather than
## the enum name, because a `const` table cannot safely reference another file's
## enum and a magic ordinal is worse than an honest comment:
##
##     2 STANDARD_COMBAT 55    Primary mastery loop and currency
##     3 ELITE           12    Higher stakes; valuable scroll reward
##     4 NARRATIVE       10    Lore, choices, traversal variation
##     5 FORGE            8    Swap/upgrade abilities
##     6 HEALING          8    Resource relief with tradeoff
##     7 MERCHANT         7    Gadgets and utility services
##
## Ordinals 0, 1, 8 and 9 - entrance, tutorial, choice, boss - are injected
## structurally and never rolled, which is GDD 8.2's own sentence: "Boss,
## entrance and tutorial nodes are injected separately."
const NODE_WEIGHT_PERCENT := {2: 55, 3: 12, 4: 10, 5: 8, 6: 8, 7: 7}

## The rollable ordinals, in a fixed order. The weight table is a Dictionary
## and this is the array that says which entries participate and in what
## sequence the cumulative roll walks them, so the roll never depends on
## dictionary iteration order.
const ROLLABLE_KINDS := [2, 3, 4, 5, 6, 7]


# --- Guarantees (GDD 8.2, hard) -----------------------------------------------

## GDD 8.2: "branch choices must preview risk and reward", and GDD 3.3's pacing
## beat is "standard fight -> route choice -> standard fight or event". One
## real choice per act is the floor; two is allowed where the act has the room
## for it.
const MIN_BRANCHES_PER_ACT := 1
const MAX_BRANCHES_PER_ACT := 2

## Options presented at a fork. Two is the minimum that makes a choice a choice;
## three is reserved for a later slice rather than used here.
const BRANCH_OPTIONS := 2

## GDD 8.2: "each act guarantees at least one build reward and one recovery
## opportunity before its boss." Both are unconditional. GDD 3.3's cadence ends
## "recovery -> boss", so the recovery is the last thing before the boss rather
## than a chance of one; and a second healing shrine is then left to the weight
## roll, which is what makes finding one a gift rather than a rule.
const BUILD_REWARD_AND_RECOVERY_ARE_GUARANTEED := true

## GDD 3.3: "Avoid two forced elites consecutively". Subsumed by the mandatory
## high-difficulty rule below, which is stricter - it also catches two authored
## budget-4 rooms. Checked anyway, as its own assertion with its own message,
## because GDD 3.3 and GDD 8.2 asked for two different things.
const AVOID_BACK_TO_BACK_ELITES := true

## Chance that a branch pocket carries an extra *non-encounter* node - a shrine,
## a merchant, a traversal beat. GDD 3.3 asks for "short traversal beats and
## environmental reveals" so a run does not read as an arena playlist. It cannot
## be an extra encounter: the encounter budget is exact on every path, and a
## pocket that added one would push the long path past GDD 3.2's band.
const POCKET_SERVICE_CHANCE := 0.5


# --- Reward offers (GDD 6.4) --------------------------------------------------

## GDD 6.4: "Present exactly three intelligible scroll choices." Not two, not a
## shop page: three, every time.
const OFFER_SIZE := 3

## A pool that cannot supply three usable scrolls is a content fault, not a
## design statement. The director refuses to open a reward with less than this
## so the failure surfaces at the content layer rather than as a two-button
## prompt in front of a player.
const MIN_SCROLL_POOL := 3

## GDD 6.4: "Repeated acquisition upgrades a scroll along a discrete track
## (I / II) rather than stacking arbitrary multipliers." Owning a scroll never
## removes it from the pool - it changes what taking it means - but an unowned
## scroll is preferred for the wildcard slot, because an offer that is all
## upgrades is an offer with no decisions in it.
const PREFER_UNOWNED_WILDCARD := true


# --- Run economy (GDD 10.2) ---------------------------------------------------

## Moon Ink is awarded per node and *banked when the run ends*, not per room:
## GDD 10.2 says persistent currency is "banked automatically upon defeat", and
## GDD 3.4 wipes run-scoped value on death.
##
## There is deliberately no per-standard-room figure. GDD 10.2 awards Moon Ink
## "for elites, new room feats and bosses", so an ordinary cleared room pays
## Temporary Coin and nothing else - which is also what keeps the persistent
## currency for the moments GDD 10.2 wants it to mark.
##
## Figures are ESTIMATE - GDD 10.2 asks for these to be settled by "simulated
## 20-run progression histories", which needs measured clear times this layer
## does not have.
const INK_ELITE := 1
const INK_BOSS := 1

## Temporary Coin is the in-run merchant currency that "vanishes after the run"
## (GDD 10.2). Three currencies is the stated maximum for first release.
const COIN_STANDARD := 3
const COIN_ELITE := 6
const COIN_STORY := 2


# --- Determinism plumbing (GDD 8.4) ------------------------------------------

## GDD 8.4: "Each run has a reproducible seed controlling route, room selection,
## encounters and reward offers."
##
## The four decision classes get *separate* RNG streams rather than sharing one
## generator. Sharing one would be shorter and wrong: a change to the room
## catalogue - one more room, one difficulty budget retuned - would shift every
## subsequent roll and silently reshuffle the route shape of a run whose seed a
## tester had recorded. Separating them means content can move without the
## structure moving underneath a bug report.
const STREAM_STRUCTURE := 1
const STREAM_ROOM := 2
const STREAM_ENCOUNTER := 3
const STREAM_REWARD := 4


# --- Helpers ------------------------------------------------------------------

## Weight-band for the encounter at `position` of `total` in an act. Bands rise
## across the act, which is how GDD 3.3's "standard fight -> route choice ->
## standard fight or event -> elite/forge -> recovery -> boss" gets steeper
## without any of that being hand-placed per act.
static func band_for(position: int, total: int, kind_ordinal: int) -> Array:
	match kind_ordinal:
		3:
			return BAND_ELITE
		5, 6, 7:
			return BAND_SERVICE
		4:
			return BAND_STORY
		_:
			var t := 0.0 if total <= 1 else float(position) / float(total - 1)
			if t < EARLY_UNTIL:
				return BAND_EARLY
			if t < MIDDLE_UNTIL:
				return BAND_MIDDLE
			return BAND_LATE


## Roll a node ordinal from GDD 8.2's weight table. Returns one of
## ROLLABLE_KINDS; structural kinds are never produced by this.
##
## `exclude_elite` drops ELITE's weight and renormalises the rest. It exists for
## GDD 8.2's "no two consecutive mandatory high-difficulty nodes": an elite is
## high whatever room it is given, so the only way to honour the rule against an
## elite roll is not to take that roll. Renormalising rather than re-rolling is
## deliberate - re-rolling until something light comes up would bias the whole
## distribution the table describes, and the relative weights of the six
## remaining types are exactly the GDD's.
static func roll_kind(rng: RandomNumberGenerator, exclude_elite := false) -> int:
	var kinds: Array[int] = []
	for k in ROLLABLE_KINDS:
		if exclude_elite and k == 3:
			continue
		kinds.append(k)
	var total := 0
	for k in kinds:
		total += int(NODE_WEIGHT_PERCENT[k])
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for k in kinds:
		acc += int(NODE_WEIGHT_PERCENT[k])
		if roll < acc:
			return k
	return kinds[kinds.size() - 1]


## Pick a region for an act, weighted by ACT_REGION_WEIGHTS. Deterministic in
## the seed and, importantly, in the *order* of ACT_REGIONS rather than in
## dictionary order.
static func roll_region(rng: RandomNumberGenerator, act: int) -> StringName:
	var regions: Array = ACT_REGIONS[act]
	if regions.is_empty():
		return &""
	var weights: Array = ACT_REGION_WEIGHTS[act]
	var total := 0
	for w in weights:
		total += int(w)
	var roll := rng.randi_range(0, maxi(total, 1) - 1)
	var acc := 0
	for i in regions.size():
		acc += int(weights[i])
		if roll < acc:
			return regions[i]
	return regions[regions.size() - 1]
