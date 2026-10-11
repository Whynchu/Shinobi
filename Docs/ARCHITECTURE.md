# Architecture

How this project is put together, and why. The design document is
`SHINOBI_Blade_and_Loop_GDD.md`; this file covers only the technical shape, and
the numbered decisions it records are the ones a future reader would otherwise
have to reverse-engineer.

---

## 1. Engine and language

**Godot 4.7.2, GDScript.** GDD 13.2 left the engine as an open decision gate and
noted that porting to Godot "may improve authoring ergonomics for rooms,
dialogue and visual tooling." That decision is now made.

GDScript's real cost here is not speed, it is that **there is no compile-time
exhaustiveness checking**. An enum misspelled or a wrongly-typed variant field
becomes a runtime null instead of a build failure. In a fixed-step combat
simulation that is a bad trade, because the whole reason for splitting the
simulation from the engine is that it can be verified without running the game.

So the headless tests are load-bearing, not polish. They are what stands in for
the type system:

```
godot --headless --path . --script res://tests/run_tests.gd
```

The runner exits non-zero if any assertion fails, **and also if zero assertions
ran**, because a test file that fails to compile would otherwise report green.
That has already earned its keep: an early run reported "0 assertions passed"
with exit 0 while every suite silently no-opped.

## 2. The simulation is not the game

`src/sim/` holds the entire gameplay simulation. It uses **no engine type beyond
`Vector3`** and holds no node references. It can be stepped with no window, no
renderer and no scene tree.

This buys three things the GDD asks for:

- GDD 13.4's automated coverage of attack windows, guard break and stagger
  immunity, verifiable in about a second rather than by launching a game and
  swinging a sword.
- GDD 8.4's determinism requirement: "procedural randomization must not change
  collision timing or compromise deterministic combat tests."
- GDD 18's telemetry. Because `step` takes a `CombatInput` and returns state,
  a scripted bot can drive thousands of headless matches with nothing drawn.
  That is the balance laboratory, and it is the reason to keep the simulation
  engine-free rather than convenient.

**Decision 1 — player and enemy do not share one state machine.**
They share timing data (`AttackTable`), hit resolution (`HitGeometry`) and the
resource core (`Combatant`). They do not share the machine that drives them.

`PlayerMachine` carries an input buffer and cancel windows. `EnemyMachine` runs
an authored windup script with a group attack budget (GDD 9.4's turn-taking
pressure). Forcing one machine onto both would hand every enemy a phantom combo
system it has no business having. GDD 9.4 describes enemies as authored decision
trees with 2-5 readable actions, which is a different shape of thing entirely.

**Decision 2 — timed guard is layered on dodging, not instead of it.**
GDD 20.2 recommends an occasional high-reward counter over a Sekiro-style
primary defence, to preserve build variety. So the guard window
(`Tuning.TIMED_GUARD_WINDOW_TICKS`, six ticks) converts a hit into posture
damage and opens a counter; dodging stays the default answer.

**Decision 3 — keep the collision *interface*, not the collision *implementation*.**
The simulation asks a level two questions: how high is the ground here, and may
the character move this way from there. `SimLevel` answers them with axis-aligned
columns, which is what the headless tests and a blockout arena need.

It is not the shipped implementation. Act II needs roof bridges and balconies;
Act I needs shallow water that alters movement speed; Act III needs rotating
screens. An axis-aligned column collision system does not survive one act, and
building it as if it would is wasted work. The game will supply a physics-backed
implementation of the same two methods.

Determinism is not the reason for this split, incidentally. `move_and_slide` at
a fixed 60 Hz *is* deterministic for identical inputs and ordering. The reason is
that the tests should not need a scene tree.

---

## The two clocks

This is the single most important thing to understand before editing any timing.

| Clock | Rate | Used for |
|---|---|---|
| **Simulation tick** | 60 Hz, fixed | Every window, i-frame and duration. Integer counts. |
| **Animation frame** | 30 fps | Clip authoring and sampling only. |

Two animation frames span one simulation tick. `Tuning.ticks_to_anim_frames()`
and `anim_frames_to_ticks()` are exact (`x2` and `x0.5`).

GDD 5.2 specifies the simulation at 60 ticks per second and then gives frame
counts, without saying which base those counts are on. **This project resolves
it at 60 Hz**, which reinterprets the authored figures:

| GDD 5.2 target | Value | At 60 Hz |
|---|---:|---:|
| Light attack startup | 11-17 frames | 0.183 - 0.283 s |
| Light active contact | 3-6 frames | 0.050 - 0.100 s |
| Light recovery | 16-24 frames | 0.267 - 0.400 s |
| Dodge invulnerability | 12 frames | 0.200 s |
| Timed guard window | 6 frames | 0.100 s |

Read as 30 fps those figures would give a 0.37-0.57 s startup, which is slow for
the "ninja agility" the GDD's combat identity asks for.

**Integer ticks, not accumulated floats.** Because the step is fixed, window
tests are exact integer comparisons (`tick >= active_from and tick < active_to`)
with no drift. The test suite asserts on exact tick counts for exactly this
reason.

---

## Hit detection

GDD 5.1: "A weapon only hits when its collision volume reaches the target;
standing outside range or beside a thrust must miss."

A hit is a geometric question, not a physics one: does the blade segment,
swept across this tick, come within `blade_radius` of the target's body capsule?

`HitGeometry.sweep_touches` samples the blade **five times per tick**
(`Tuning.SWEEP_SUBSTEPS`). This is not optional. A fast swing covers a third of a
metre of blade travel in one tick; a single sample at the tick boundary would let
the blade pass straight through a target and the attack would silently whiff.
GDD 18 tracks whiffs as a balance metric, so a tunnelling bug would surface there
as suspicious data rather than as a bug.

No physics bodies are involved, so the answer is identical whether the game is
running or the tests are running with nothing on screen.

**Decision 5 — blade sweeps are hand-authored, not baked from animation.**
`AttackTable.sweep` is an ordered list of `BladePose` resources: where the hilt
is and where the tip is, in the character's own space (X is the character's
left, Y up, Z forward). Two poses describe a straight swing, three or more a
compound arc, interpolated across the active window.

Baking from an animation clip was rejected. It ties reach rigidly to the motion,
which does not obviously suit an original chibi rig whose proportions are still
moving, and it makes changing a number mean re-exporting an animation. Authored
poses keep the simulation independent of playback, recalibrate the moment
proportions change, and let a weapon deliberately reach further than it looks -
a normal action-game tool, and arguably necessary for GDD 5.4's "hitboxes follow
visual sweeps closely."

That rejection was provisional. It is now **reversible, and the reason it is
reversible is the rig**, which the Blender lane exists to provide. Two things
were true then and are not now: there is a skeleton, and its proportions are
measured rather than guessed. A clip can be baked once there is something to
bake from and something to check it against.

The shape of the revisit, decided now so it is not re-argued:

- Where a move is authored to match its own animation, the sweep is derived
  from the clip on export and `AttackTable.sweep` becomes a cache rather than
  the source of truth. That is the one-field change.
- Where a move deliberately reaches further than it looks - the normal
  action-game tool above - it stays authored, and the divergence is recorded.
  The proportions test is what makes "deliberate" a claim that can be checked
  rather than a word somebody typed.
- The two mechanisms do not need to agree globally. Both are per-move, and a
  mixed state is honest: it says "some swings follow their clip, and this one
  does not, on purpose."

`tools/blender/build_rig.py` and the GDD 11.2 proportions test are what make
this a plan rather than a wish. They are also why the earlier objection no
longer bites: "proportions are still moving" is a property of a rig nobody has
measured, and the rig is now measured.

**Supporting the authoring.** Hand-authored data is only better than baked data
if it is pleasant to author and hard to get wrong, so:

- `BladePose` presets (`horizontal_slash`, `overhead_chop`, `low_sweep`,
  `thrust`, `rising_slash`) and an **Apply sweep preset** tool button in the
  Inspector. Authoring starts from a known arc rather than from six zeros.
- Presets take a **blade length**, not a reach. Reach is the consequential number
  and is printed by the report; blade length is physically bounded, so making it
  the input makes a two-metre katana structurally impossible. An earlier
  reach-parameterised version silently produced exactly that.
- `AttackTable.validate()` and `Moveset.validate()` report data faults in prose:
  an empty active window, a window that runs past the end of the move, a cancel
  window that opens before the blade lands, a missing sweep, a loop in the light
  chain, and a blade whose length varies across a swing.
- `tools/moveset_report.gd` prints the balancing sheet GDD 16 asks to be shared,
  from the same data the simulation runs, and `--check` exits non-zero on any
  problem. This is the CI-facing half of Gate A's "animations/hitboxes disagree".

**Provenance is tracked.** Every `AttackTable` carries
`Provenance.ORIGINAL` or `Provenance.ESTIMATE`. GDD 13.2 requires the prototype
to be independently runnable with rights-cleared content, and GDD 17 lists
documented provenance as the mitigation for asset/legal dependency. A number
nobody measured should not look like a number somebody did.

The validator earned its place immediately. On its first run it found a real bug
in a preset (the overhead chop's blade varied from 0.39 m to 1.40 m - the weapon
was stretching across the swing) and a real balance bug in a fixture (an enemy
attack that could be cancelled before its blade landed).

---

## Layering

```
src/sim/          Node-free. Runs headless. The whole gameplay simulation.
  tuning.gd         every GDD constant, one place, each citing its source
  attack_table.gd   one authored move (a Resource, editable in the Inspector)
  blade_pose.gd     one blade position in local space, plus the arc presets
  moveset.gd        the full move family for one weapon (GDD 7.1)
  hit_geometry.gd   segment/capsule distance and the per-tick sweep
  combatant.gd      hp, stamina, posture, hit-stop, guard, reactions
  player_machine.gd the player's action state machine
  enemy_machine.gd  authored enemy behaviour over the same data
  level.gd          collision as the simulation sees it
  sim_world.gd      the 60 Hz tick; the only place a hit is resolved
  sim_math.gd       the yaw convention, in one place

src/run/          RunDirector: seeded route graph (GDD 8) - not yet written
src/telemetry/    event aggregation (GDD 18) - not yet written

assets/           exported, for the engine. Each binary carries a checked
                  provenance manifest (see the provenance policy below)
tools/blender/    the Blender lane: rig source, exporter, and its checks
  shinobi_rig.py       the character, as a function of its proportions
  build_rig.py         builds, exports .glb, writes the manifest
  test_proportions.py  GDD 11.2 measured on the *exported* file
  test_proportions_negative_control.py
  Setup-BlenderLane.ps1

scripts/          presentation. Reads simulation state, never writes it.
shaders/          cel shading (GDD 11)
tests/            headless runner, fixtures, combat suites
tools/            moveset_report.gd: the balancing sheet, printable and checkable
```

## The Blender lane

```
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tools/moveset_report.gd --check
godot --headless --path . --quit-after 4000 res://scenes/main.tscn --selftest
godot --path .                                    # play it
```

Each lane owns a runner of its own, on the same contract - non-zero on failure,
and non-zero on *silence*:

```
godot --headless --path . --script res://tests/run_art_tests.gd        # Gate B
godot --headless --path . --script res://tests/run_run_tests.gd        # Gate D
godot --headless --path . --script res://tests/run_scroll_tests.gd     # GDD 6
godot --headless --path . --script res://tests/run_enemy_tests.gd      # Gate C
godot --headless --path . --script res://tests/run_provenance_tests.gd  # GDD 17
```

The Blender lane is separate again, because it is not GDScript:

```
blender --background --python tools/blender/build_rig.py
blender --background --python tools/blender/test_proportions.py
blender --background --python tools/blender/test_proportions_negative_control.py
```

`moveset_report.gd --check` remains the only checkable sheet, and the
provenance runner is the only one that hashes binaries - which is why it is the
one a CI job cannot shortcut by skipping the Blender setup.

The self-test boots the real scene, steps it against scripted input with no
window, and reports the outcome. It is how the blockout gets checked in CI at
all, and it earns its keep: it is what caught the bug below.

Three operational notes, all learned the hard way:

- **A script that fails to compile hangs instead of exiting.** `--script` with a
  broken file prints the parse error and then sits in the SceneTree forever,
  because the entry point that would have called `quit()` never ran. Any CI
  invocation needs an external timeout.
- **The test runner exits 2 when no assertions ran.** Without that, a test file
  that does not compile reports "0 assertions passed" and exits 0.
- **Proximity tracing beats a debugger.** When the blockout player was not
  landing hits, printing the closest approach, the blade reach at that moment
  and the per-tick blade pose found it at once. "Closest 0.80 m, reach 1.35 m,
  connects within 1.75 m" says more in one line than an hour of stepping.

---

## The control surface

Every control the HUD advertises must produce an observable change in the world.
`test_verbs` exists because the first playable blockout shipped with four dead
bindings - flask, tool, interact and walk were bound to keys and read by nothing,
and `walk_held` was declared and never assigned. The game felt uncontrollable
because most of its buttons did not do anything at all.

| Control | Effect | GDD |
|---|---|---|
| Left stick / WASD | Move; light tilt walks, full tilt runs | 4.1, 4.2 |
| RB / LMB | Light attack, chains into the next swing | 5.3 |
| RT / RMB | Heavy; held past `CHARGE_TICKS` becomes charged heavy | 5.2, 5.3 |
| LB / MMB / V | Guard; pressing opens the timed-guard window | 5.3 |
| B / Space | Dodge on release; held past 10 ticks is sprint | 4.1 |
| A / Shift | Jump | 4.2 |
| Y / Q | Shuriken, thrown along the camera yaw | 6.1 |
| D-pad up / R | Healing flask | 5.2 |
| R3 / Tab | Lock-on, cycles targets | 4.3 |
| L3 / C | Crouch | 4.2 |
| F1 | Toggle the sweep overlay | - |
| Esc | Quit | 3.4 |

**Decision 6 — held inputs are levels, not toggles.**
Crouch follows its button rather than flipping on it. GDD 14 asks for hold/toggle
options, but a toggle fed a *level* signal flips once per tick while held, so
holding crouch makes the character crouch and stand sixty times a second.
Toggling belongs in the input layer, where the press edge lives -
`InputReader.walk_as_toggle` is where that option would go.

**Death is not terminal.** GDD 3.4 asks for the cause named and a fast return,
with no mandatory cutscene. The readout appears after a dozen ticks, any attack
or movement input restarts, and `SimWorld.restart()` clears the run's temporaries
- health, flasks, tool charges, tools in flight, lock-on - while putting every
enemy back where it started, so a retry is the same fight rather than a new one.

**Shuriken is a real projectile.** `Projectile` is a swept segment tested
against body capsules by the same primitive that tests a blade, because at
22 m/s a tool covers over a third of a metre per tick and would otherwise pass
through a thin target. Its damage is delivered as an `AttackTable`, so enemies,
reactions, hit-stop and telemetry all work exactly as they do for a swing.

Interact is bound but has nothing to interact with in the blockout - there are no
doors, shrines or pickups yet.

---

## Current state

The simulation layer, the authored-move tooling and a playable blockout exist
and are green: **161 assertions across 13 suites**, zero data problems, and a
self-test that plays the scene headless without throwing.

### What the blockout is

`scenes/main.tscn` builds a flat duelling floor with the arena's traversal
features around the edges, a capsule ninja with one enemy in front and one off to
the side, a follow camera with lock-on framing, a HUD, and the sweep overlay.
Rig is primitives, per GDD 11.2's chibi proportions. Controls are listed on
screen; `F1` toggles the sweep overlay; `Esc` quits.

The camera deliberately does not dolly, punch in on attacks, or change framing
during a swing. GDD 4.3 makes "camera cannot hide lethal telegraphs in default
framing" a hard constraint, and GDD 18 measures camera failures, so anything
that tightens the frame during combat has to be earned later.

### The bug the smoke test caught

An attack's active window spans several ticks, and the blade stays inside the
target across them. With no per-swing guard, **every tick of the window
registered as another hit** - so a six-tick heavy dealt six swings' worth of
damage, and a stand-in enemy lost 100 HP in half a second to an 18-damage
attack.

The fix is `swing_hit` on both machines, cleared when a move begins and set when
a hit lands. It is now pinned by `test_one_hit_per_swing`, which asserts total
damage equals one move's worth per registered event rather than a fixed count,
so it stays correct as swing counts change.

Neither the unit tests nor the moveset report would have caught this. It took
the blockout actually playing to surface it, which is a fair argument for
building the thing you can play before the thing you can assert about.

### What is still missing

No animation, no audio. Cel shading exists (Gate B); the character rig does not
follow it yet, and no move is currently driven by a clip. The blade is placed
from data, which is now a reversible decision with a stated path (Decision 5)
rather than a state of "once a skeleton exists".

Interact has nothing to interact with. Smoke bombs and caltrops (GDD 6.1's other
two ninja tools) are not implemented - they need status effects and area logic,
which is separate work rather than extra parameters.

`player_machine.gd` is well over 600 lines and now carries locomotion, charge
resolution, the air state and consumables. It wants splitting before it grows
further.