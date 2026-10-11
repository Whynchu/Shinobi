# SHINOBI: BLADE & LOOP

**GAME DESIGN DOCUMENT — V0.1**  
**Status:** Concept approved / preproduction design proposal  
**Date:** October 10, 2026  
**Genre:** Single-player 3D action roguelite  
**Platform target:** PC first, controller-first; other platforms to be evaluated  
**Creative touchstones:** The Wind Waker's readable cel shading; GameCube-era low-poly proportions; Hades-style run structure; Elden Ring's deliberate attack commitment.

![Approved visual direction — concept art generated for this project.](/mnt/data/shinobi_build/hero.png){width=6.8in}

> **North star:** A tiny, expressive ninja becomes a terrifying swordfighter by stealing techniques from a fortress that changes every night.

**Design status key:** **[LOCKED]** agrees with the concept established so far; **[PROPOSED]** is a recommended direction awaiting playtest; **[TEST]** is a numeric tuning target, not a final specification; **[TBD]** requires a production decision.

---

# 1. Executive Summary

**Elevator pitch.** *SHINOBI: Blade & Loop* is a vibrant third-person action roguelite in which miniature ninjas infiltrate a shifting fortress, duel rival clans, and assemble devastating combat styles from stolen scrolls. Each run rearranges handcrafted encounters, rewards precise melee combat and clever tool use, and carries the player closer to mastering the secrets of a magical warlord.

**Promise to the player.** Explore a vivid, delightful world; learn enemy tells; survive tense, physical duels; improvise clever ninja builds; and return from failure with new options rather than simply inflated statistics.

**Signature differentiators.** (1) Cute characters and dramatic combat impact without grim-dark presentation. (2) Weapon hit detection, stamina, guard and dodge commitment designed for readable 3D duels. (3) Three-scroll buildcraft where mechanics interact visibly. (4) Hand-authored rooms rearranged into brisk, replayable routes. (5) Distinctive lightweight geometry, crisp cel bands, graphic impact VFX and restrained effects noise.

| Product parameter | Baseline |
|---|---|
| Genre and camera | Third-person 3D action roguelite, adjustable follow camera and lock-on |
| Core mode | Single-player; no multiplayer dependency |
| Typical completed run | 25–35 minutes **[TEST]** |
| Run layout | Three acts; branching authored room chains |
| Difficulty ethos | Demanding but legible; mistakes are punishable, tells are learnable |
| Combat identity | Ninja agility layered on deliberate attacks and stamina economy |
| Intended player | Players who enjoy mastery-based combat, Hades-style progression and expressive stylized games |
| Business model | Premium complete game; no pay-to-win or live-service systems **[PROPOSED]** |

## 1.1 Design pillars [LOCKED]

1. **Tight ninja combat:** Every action has a purpose. Defensive timing, spacing, attack commitment and enemy knowledge matter more than button volume.
2. **Build a fighting style each run:** Scrolls and tools create new tactics, not merely percentage increases.
3. **Handmade world, changing paths:** Rooms are authored for high-quality combat; run assembly provides uncertainty, choice and replayability.
4. **Charming world, dangerous opponents:** Vivid color and chibi proportions coexist with serious encounters and memorable bosses.

## 1.2 Non-goals [PROPOSED]

No large seamless open world at launch; no procedural generation of untested collision meshes; no loot rarity treadmill; no survival crafting; no multiplayer requirement; no photorealism; no permanent progression that makes early bosses mechanically irrelevant; no reliance on third-party game-extracted assets in a shipping build.

# 2. World, Premise and Narrative

## 2.1 The Shifting Fortress

The village of **Kogarashi** safeguards eight legendary combat scrolls, techniques once shared between peaceful ninja clans. A masked usurper called the **Moon Shogun** steals them and seals himself inside the **Mirage Citadel**, a fortress built over an ancient device called the **Moon Loom**. At dusk the Loom unweaves the citadel's passages and recreates them in a different arrangement. Captured techniques spread through the Shogun's lieutenants and minions.

Our protagonist is an apprentice of the declining **Maple Crane Clan**, equipped with a chipped sword, a stubborn mentor and the ability to remember the citadel's changes. The village functions as the between-run hub; story unfolds through boss rematches, recovered scroll inscriptions, dojo residents and short environmental scenes.

**Tone:** Mythic ninja folklore played straight by small, expressive characters. Humor comes from character and juxtaposition, not constant fourth-wall jokes. Stakes are real, but gore and oppressive despair are not required.

## 2.2 Narrative beats [PROPOSED]

| Beat | Trigger | Payoff |
|---|---|---|
| Arrival | Tutorial completion | Mentor reveals the stolen scrolls and citadel curse |
| First victory | First Act I boss defeat | A clan seal restores a new dojo workstation |
| Midpoint | Act II first clear | A rival claims the Shogun is repairing, not simply exploiting, the Loom |
| Revelation | First reach of Act III | Recover a scroll that reveals the fortress is also imprisoning something |
| First ending | Defeat Moon Shogun | Loom quiets temporarily; the village celebrates |
| Longer arc | Additional clears and character quests | Alternate remixes and a final choice **[TBD]** |

Story should never interrupt action for long. Mid-run dialogue is short, skippable and contextual. The design supports a satisfying first victory and optional deeper mastery rather than forcing dozens of runs for the base ending.

# 3. Player Experience and Session Structure

## 3.1 Core loop [LOCKED with proposed specifics]

**At dojo:** select a starting weapon, a basic ninja tool and one starting perk; speak to NPCs, buy permanent horizontal unlocks and choose optional objectives. **Enter fortress:** traverse a branch of combat rooms, take rewards, choose routes and encounter elites. **Build:** fill three scroll slots and create synergies while conserving healing resources. **Challenge:** defeat the act boss, collect a seal and descend to the next region. **Return:** on death or victory, bank Moon Ink and unlock new options for future runs.

## 3.2 Run outline [TEST]

| Act | Encounters before boss | Primary learning | Typical play time |
|---|---:|---|---:|
| I — Bamboo Grove | 5–7 | Spacing, basic defense, terrain | 6–9 min |
| II — Lantern Village | 6–8 | Flanking, elevation and build synergies | 8–11 min |
| III — Crimson Castle | 7–9 | Advanced tells, elites and resource decisions | 10–15 min |

Total: roughly **18–24 regular rooms**, three bosses, and 25–35 minutes for a proficient completed run. Early failed attempts should be much shorter. These targets depend on measured room clear times and loading times.

## 3.3 Room pacing

A typical act alternates: standard fight → route choice → standard fight or event → elite/forge → recovery → boss. Avoid two forced elites consecutively; place recovery opportunities before a boss; guarantee useful choices before a build-specific challenge. Short traversal beats and environmental reveals prevent the sequence from feeling like an arena playlist.

## 3.4 Failure, victory and restart

On defeat, the current three-scroll build, temporary currency, and consumable tool charges vanish. Earned **Moon Ink**, unlocked starting gear, discovered scrolls in the permanent offer pool, dojo improvements and recorded boss knowledge persist. Death immediately reveals cause, collected rewards and progress, then returns to a fast dojo restart. No mandatory long death cutscene.

# 4. Controls, Camera and Traversal

## 4.1 Gamepad mapping [PROPOSED]

| Input | Action |
|---|---|
| Left stick / right stick | Move / camera |
| RB / RT (hold) | Light attack / heavy or charged heavy |
| LB | Guard; timed guard when pressed just before impact |
| LT | Equipped active scroll art |
| B tap / hold | Dodge/backstep / sprint |
| A | Jump; contextual wall-hop near valid geometry |
| X | Interact / open route door / pick up |
| Y | Use equipped ninja tool |
| L3 / R3 | Crouch / lock target |
| D-pad right/left | Cycle consumable tools / weapons where unlocked |
| D-pad up | Use healing flask |
| D-pad down | Quick inspection of current build |

Keyboard/mouse remapping and controller remapping are requirements. Do not require simultaneously awkward multi-button gestures for common defensive reactions.

## 4.2 Movement character

The player accelerates quickly but still has weight. Walk, run, sprint, directional dodge, backstep, crouch, hop, directional jump attacks and ledge drops work from day one. Locked-on locomotion faces the target and enables strafing. **Wall-hop** is deliberately restricted to authored traversal surfaces and short combat repositioning; an unrestricted parkour engine is a later feature gate. No room's only critical path may depend on a consumable ninja tool.

## 4.3 Camera

Default camera: third-person, slightly elevated to protect the small character's silhouette; smooth follow, collision avoidance, adjustable sensitivity and invert options. Lock-on targets one enemy, softens lateral facing penalties, and allows cycling. Prefer a fixed comfortable framing at base combat distance to dramatic cinematic zooms that conceal incoming attacks. Tall environments must be authored around the camera: overhang fades, foreground occluders fade out, and narrow corridors get tested with paired enemies.

# 5. Combat System

## 5.1 Combat principles [LOCKED]

A weapon only hits when its collision volume reaches the target; standing outside range or beside a thrust must miss. Every offensive action has anticipation, active contact and recovery. Stamina prevents perpetual attack/dodge spam; weapon hit-stop and short pose exaggeration make successful contact legible. Defensive skill is rewarded with counterattack opportunities and posture pressure. Clear tells take priority over surprise damage.

## 5.2 Prototype timing and resource baseline [TEST]

**All figures below are first-pass values for instrumentation, not promises of final balance.** Simulation runs at 60 ticks per second. Visual rendering and animation sampling can run independently so long as attack windows remain deterministic.

| Parameter | Initial test value | Design intent |
|---|---:|---|
| Player HP | 100 | Convenient baseline for hit readability |
| Player stamina | 100 | Approximately 5 basic dodges or 6–8 lights before depletion |
| Stamina regen | 24/sec | Recovery window matters |
| Regen delay after stamina use | 0.65 sec | Prevent immediate full uptime |
| Light attack cost | 12–16 | Chainable, range-dependent |
| Heavy attack cost | 24 | Deliberate posture pressure |
| Fully charged heavy cost | 32 | High commitment |
| Standard dodge cost | 20 | Defensive budget |
| Standard dodge invulnerability | 12 frames | Tune against visible attack arcs |
| Timed guard input window | 6 frames before contact | Reward precision, avoid frame-perfect exclusion |
| Healing flask | 2 charges, +35 HP | Resource for multi-room routes |
| Base active-art recharge | 10–16 sec | Strong but not spammable |
| Player posture threshold | 100 | Repeated unsuccessful guarding can break stance |

**Animation targets:** sword light startup 11–17 frames, active 3–6, recovery 16–24; heavier attacks lengthen commitment rather than merely multiplying damage. Exact values must be reconciled with authored animation timing and the chosen collision rig. Avoid negative-feeling buffers: permit one queued attack near the end of recovery but never a dozen prebuffered inputs.

## 5.3 Offense, defense and stagger

- **Light chains:** three-hit baseline katana string with distinct reach and orientation; repetition is safe against weak enemies but punishable by elites.
- **Heavy / charged heavy:** slower commitment with larger posture damage and stronger stagger category. Charge modifies both tell and impact.
- **Running, jumping, backstep and dodge attacks:** tactical bridge between movement and melee. These are remapped to original ninja motions, not copied game animations.
- **Guard:** absorbs or mitigates incoming contact while draining stamina/posture according to impact. Incorrect repeated guarding leads to guard break.
- **Timed guard:** pressing guard in the late incoming window reduces stamina loss and contributes enemy posture damage; follow-up counter is conditional, not automatic. This is a *new* system requiring implementation.
- **Dodge:** short committed directional escape; perfect dodge means successfully evading a hit during a smaller subset of invulnerability and can trigger scroll effects. Do not grant automatic omnidirectional teleportation on every roll.
- **Posture:** certain attacks, timed guards and specific scrolls fill an enemy posture meter. Break creates a brief, clearly signposted finisher opening. Big bosses can stagger without trivializing their full phase.
- **Hit reactions:** small flinch, medium stagger, heavy stagger and knockdown; immunity rules prevent stun-lock loops on elites and bosses.

## 5.4 Combat readability contract

Enemy attacks must communicate **origin, direction, timing and counterplay** through windup pose, sound and slash arc. Color may reinforce a tell but must never be the sole cue. Each major attack has at least one consistent answer (space, jump, dodge, guard or interrupt), with risk/reward different by weapon. Hitboxes follow visual sweeps closely; attacks cannot secretly reach far beyond their visible blade. Camera cannot hide lethal telegraphs in default framing.

## 5.5 Suggested balance targets [TEST]

Weak enemy: 2–4 clean katana hits to defeat; routine standard room: 30–65 seconds after learning; elite fight: 45–100 seconds; boss fight: 90–180 seconds for a competent player. New players may take substantially longer. Balance across styles using time-to-kill, incoming damage rate, stamina pressure, dodge reliability and completion rate rather than raw DPS alone.

# 6. Ninja Tools and Scroll Buildcraft

## 6.1 Two distinct layers

**Ninja tools** are limited-charge gadgets used with Y: shuriken, smoke bombs and caltrops. Charges refresh at specified room rewards or rest nodes. They are readable utility options, not full extra ability bars.

**Scrolls** are the build engine: the player can carry **one active art** (LT) and **two passive scrolls**. This makes three meaningful slots without a UI jungle. At a scroll reward, choose one of three options, with a swap or upgrade prompt once slots are full. Scrolls found in a run expire at its end. New scroll *types* permanently join the future reward pool when discovered or unlocked.

## 6.2 Starter scroll catalog [PROPOSED]

| Scroll | Type | Effect | Counterplay / limit |
|---|---|---|---|
| Shadow Substitution | Active | Timed evade places decoy and performs short angled reposition | Cooldown; not allowed across invalid gaps |
| Thunder Step | Active | Short burst step; next connected melee hit adds lightning stagger | Limited distance; consumes stamina |
| Smoke Veil | Active | Brief smoke cloud disrupts targeting on vulnerable enemies | Bosses lose aim briefly, not entire phase |
| Crimson Edge | Passive | Successful guard counter builds bleed on target | Boss bleed resistance, no infinite stacks |
| Ricochet Stars | Passive | Shuriken may ricochet to an additional target | Maximum number of bounces |
| Afterimage | Passive | Perfect dodge produces a harmless silhouette that attracts a brief attack | Cooldown on trigger |
| Crane's Reach | Passive | Last hit of a light chain extends blade arc and posture pressure | Requires finishing the chain |
| Iron Resolve | Passive | Timed guards restore a small amount of stamina | Internal trigger cooldown |
| Foxfire Mark | Passive | Tool hits mark enemies for a follow-up melee bonus | Single mark consumed on hit |
| Rising Gale | Passive | Jump attacks gain a small controlled knock-up vs light targets | Bosses convert to posture only |
| Lotus Bloom | Passive | Defeating a marked enemy produces a tiny healing bloom | Per-room cap |
| Moon Thread | Passive | Finisher briefly reduces remaining active-art cooldown | Cannot self-chain repeatedly |

## 6.3 Example build recipes

**Ghost Counter:** Shadow Substitution + Afterimage + Crimson Edge. Dodge to bait retaliation, then punish the misdirected enemy with a bleed-building counter.

**Storm Merchant:** Thunder Step + Ricochet Stars + Foxfire Mark. Shuriken spread marks targets, then a lightning-empowered dash-in converts marks into burst damage.

**Iron Crane:** Smoke Veil + Iron Resolve + Crane's Reach. Control space, recover stamina through timed guard, and finish an extended reach chain to break posture.

Every synergy must have a visual tell and a bounded proc rate. No combination can freeze bosses indefinitely, produce unbounded ricochets or guarantee fully free healing.

## 6.4 Reward rules

Present exactly three intelligible scroll choices. Favor one option relevant to the player's current active art, one cross-archetype option and one wildcard; avoid deceptive rewards unusable with the equipped weapon. Repeated acquisition upgrades a scroll along a discrete track (I / II) rather than stacking arbitrary multipliers. Offer a modest reroll resource later, but not in the first prototype.

# 7. Weapons and Playable Archetypes

## 7.1 Weapon roster [PROPOSED]

| Weapon | Range / speed | Identity | Risk |
|---|---|---|---|
| Katana | Mid / balanced | Bread-and-butter chains, clean counters | No extreme specialty |
| Dual kunai | Short / fast | Agile flanks, status and multiple contacts | Exposed at close range |
| Odachi | Long / slow | Heavy posture pressure and broad arcs | Vulnerable recoveries |
| Spear / naginata | Long / measured | Distance control, line attacks | Weak at cramped angles; stretch goal |

The *vertical slice* uses only the katana. Each added weapon requires an original move family, collision profile, cancel rules, sound set, hit reactions and boss coverage, not just a different mesh.

## 7.2 Archetypes without scope explosion

**Wanderer:** Katana / shuriken; reliable, balanced. **Kunoichi:** Dual kunai / smoke; mobility. **Ronin:** Odachi / guard pressure; heavy stagger. **Shinobi:** Katana or short blades / caltrops; gadget control. Initially these are **starting loadout templates sharing one player rig**, not four separate animation controllers. Their visual costumes, starting unlocks and initial scroll offer create identity. Distinct characters or bespoke traversal can come after the core combat is proved.

# 8. Roguelite Run Generation

## 8.1 Authoring strategy [PROPOSED]

Generate a **run graph**, not arbitrary geometry. Rooms are handmade prefabs labeled with region, difficulty budget, doorway connectors, traversal tags, arena size, hazards, camera safety and encounter sockets. The route graph picks compatible rooms, populates them from curated enemy budgets and provides occasional diverging choices. This protects hitbox consistency and avoids impossible collisions.

## 8.2 Node distribution [TEST]

| Node | Initial frequency | Function |
|---|---:|---|
| Standard combat | 55% | Primary mastery loop and currency |
| Elite challenge | 12% | Higher stakes; valuable scroll reward |
| Narrative or mystery event | 10% | Lore, choices, traversal variation |
| Forge / scroll shrine | 8% | Swap/upgrade abilities |
| Healing shrine | 8% | Resource relief with tradeoff |
| Tool merchant | 7% | Gadgets and utility services |

These are generation weights, not rigid room counts. Boss, entrance and tutorial nodes are injected separately. First room of each act is fixed; each act guarantees at least one build reward and one recovery opportunity before its boss; no two consecutive mandatory high-difficulty nodes; branch choices must preview risk and reward.

## 8.3 Content templates

Each authored room has: entry framing; one main combat silhouette; 1–3 enemy spawn patterns; optional traversal or hazard variation; two camera-tested fighting zones; door exit markers; a difficulty budget. Avoid arena layouts where enemy crowds force constant offscreen damage. Boss arenas are fully handcrafted, not randomized geometry.

## 8.4 Seeds and repeatability

Each run has a reproducible seed controlling route, room selection, encounters and reward offers. Record seed plus build and room-clear logs for bug reproduction. Procedural randomization must not change collision timing or compromise deterministic combat tests.

# 9. Regions, Enemies and Bosses

![Three visual biomes — an art-direction reference, not in-game screenshots.](/mnt/data/shinobi_build/biomes.png){width=6.8in}

## 9.1 Act I — Bamboo Grove

**Palette:** emerald, jade, warm wood, sky cyan and vermilion. **Spaces:** mossy bridges, bamboo clearings, shallow water, shrines, cliff paths. **Lesson:** spacing and obvious attack telegraphs. **Hazards:** temporary falling bamboo, shallow streams that mildly alter movement speed (never random slips).

**Enemies:** Foot Soldier (short 2-hit chain); Spear Sentry (linear poke with long reach); Paper Archer (visible aimed shot); Bamboo Monk (slow heavy overhead with a jumpable sweep). **Boss: The Boar.** Huge lacquered armor, oversized club and readable overhead attacks. Phase 2 introduces a wide sweep and a short forward rush; a correctly timed counter creates a posture break. Teaches that big enemies are dangerous but fair.

## 9.2 Act II — Lantern Village

**Palette:** amber lanterns, terracotta, violet roof tiles, cerulean shadows. **Spaces:** tight alleys, roof bridges, balconies, courtyards and market stalls. **Lesson:** lateral repositioning and tool use under ranged pressure. **Hazards:** telegraphed collapsing awnings, firework pots that both player and enemies can detonate.

**Enemies:** Rooftop Runner (fast flank); Shield Ashigaru (guard stance vulnerable to heavy or flank); Firecracker Adept (placed area denial); Kunoichi Duelist (feint into punish). **Boss: The Fox Twins.** Paired sisters with different tempos: one pressures with dual blades, one uses range and smoke. Their synchronized special is highly telegraphed; killing one changes the other's pattern, not an immediate arbitrary difficulty spike.

## 9.3 Act III — Crimson Castle

**Palette:** moonlight indigo, crimson leaves, charcoal roofs and gold highlights. **Spaces:** echoing halls, elevated causeways, banner-lined stairs, moonlit gardens. **Lesson:** late-run mastery and resource discipline. **Hazards:** visible rotating defensive screens, periodic lantern beams that reveal camouflage, limited-footprint platforms.

**Enemies:** Crimson Guard (delayed heavy); Tengu Priest (airborne reposition and wind arc); Mirror Shinobi (copies one active-art category, not the whole build); Elite Captain (mixed counters). **Boss: The Moon Shogun.** A calm master whose three phases express precision, deception and mastery. He can demonstrate modified versions of previously encountered techniques, but the set is deterministic per encounter so players can learn it. Defeating him resolves the base story.

## 9.4 Enemy archetype contract

Each enemy needs a distinctive silhouette, 2–5 readable actions, approach/retreat behavior, a response to guard pressure, a clear stagger rule, audio cues and at least one contextual weakness. AI can operate with simple authored decision trees or utility scoring and must respect turn-taking pressure: swarms may threaten from different positions, but lethal offscreen overlap needs limits.

## 9.5 Boss format

Bosses should be approximately 90–180 seconds for a competent player **[TEST]**, with 2–3 phases or moveset enrichments, not long invulnerability cinematics. Each boss has: five learnable signature attacks, at least one tool interaction, one posture-break opportunity, a distinctive arena and an audio motif. Retries skip preamble; victory delivers a clan seal and meaningful unlock.

# 10. Permanent Progression, Economy and Hub

## 10.1 Two-track progression [LOCKED]

Run rewards are temporary; village rewards persist. The hub must make failure worth returning to without replacing skill with permanent raw power.

## 10.2 Currency and unlocks [PROPOSED / TEST]

**Moon Ink:** persistent currency awarded for elites, new room feats and bosses, banked automatically upon defeat. First-time achievement bonuses accelerate early onboarding. Initial target: failed early run yields 4–7 Ink; Act II run 9–15 Ink; first full clear 18–25 Ink. Unlock costs: basic new tool or scroll offering 8–12; alternate starting weapon 15–25; dojo cosmetic 5–20. Economy to be adjusted via simulated 20-run progression histories.

**Clan Seals:** boss milestones, used to unlock new NPC services and starting categories; never purchased. **Temporary Coin:** in-run merchant currency that vanishes after the run. Three currencies are the maximum for first release.

## 10.3 Dojo workstations

**Armory:** starting weapon selection. **Scrollkeeper:** expands discovered scroll pool and displays the collection. **Toolmaker:** unlocks gadget variants. **Training Circle:** dummy, attack telegraph practice and optional defensive drills. **Memory Wall:** defeated enemies, boss moves and discovered lore. **Wardrobe:** cosmetic scarves, masks and silhouettes. Each workstation needs a concise functional loop, not a burdensome crafting tree.

## 10.4 Avoiding power creep

Do not sell unconditional +50% damage or +100 maximum health as the main progression incentive. Reward unlocked options, contextual conveniences, new scroll pools and alternate playstyles. An optional small flask-charge unlock is possible, but permanent health boosts must be tightly capped and tested for undermining boss learning.

# 11. Visual Art Bible

![Original concept sheet: playable ninja and opponents, establishing approved proportions and chunky shape language.](/mnt/data/shinobi_build/characters.png){width=6.8in}

## 11.1 Approved target [LOCKED]

**Bright GameCube-era stylization**: The Wind Waker-inspired color design and readable cel shading; intentionally chunky silhouettes; chibi ninja proportions; hand-authored low-poly architecture; vivid foliage; clear warm/cool light separation. Final art must be original rather than tracing specific Nintendo assets. The illustration above is a concept direction, **not** an existing game screenshot or production-ready mesh.

## 11.2 Shape and materials [PROPOSED]

Heroic chibi: 2.75–3.25 heads tall, oversized hair/hood, blocky forearms and gloves, short torso, clearly placed feet and broad readable weapon shapes. Avoid fine armor filigree and realistic anatomy. Buildings use layered rectangular forms, tapered roofs, strong negative spaces, blocky cliffs and simplified foliage clusters. Textures, where used, emphasize purposeful painted accents rather than noisy photorealistic detail.

Shading: 2–3 discrete diffuse bands, broad shadow shapes, minimal roughness detail, subtle ambient fill and selective rim lights for silhouettes. Outlines should be thin and distance-stable or omitted where environmental edges already read. No heavy PBR reflections or high-frequency terrain detail. Faces use a small expressive library (eyes, brows, mouth) readable during gameplay.

## 11.3 Core palette [PROPOSED]

| Role | Color | Hex |
|---|---|---|
| Forest jade | Large nature masses | `#58BDA0` |
| Festival coral | Banners, scarves, target accents | `#E85E50` |
| Paper gold | Lanterns, reward highlights | `#F6C86C` |
| Sky blue | Atmospheric depth and water | `#79C7DD` |
| Deep indigo | Roofs, night and shadow anchor | `#283B57` |
| Mystic plum | Late-game night magic | `#624D91` |
| Warm paper | UI base, dialogue and pale surfaces | `#F5EFDF` |

Strong primary colors are reserved for navigation, factions, major abilities and impact. Keep backgrounds slightly lower contrast than the actor/target pair. Screenshot checks must include daylight, dusk and moonlight plus color-vision-simulation passes.

## 11.4 FX design rules

Impacts use graphic starbursts, slash crescents, brief hit-stop, limited particles and one readable accent color per ability family. **Avoid enormous bloom plumes that conceal enemy windups.** Substitution uses a sharp silhouette pop and a short rice-paper smoke puff; Thunder Step uses a zigzag gold-white stroke; Crimson Edge uses a limited coral ribbon; shuriken produce crisp spinning silhouettes. Make effects parameterized by world scale and duration, with per-ability readability caps.

## 11.5 UI and typography

A small health/stamina HUD, two-scroll passive icons, one prominent art icon/cooldown, gadget count, flask charges and optional boss posture. Use parchment/ink motifs sparingly; never cover combat with large decorations. Menus resemble hand-painted dojo plaques, but text is modern, high-contrast and legible. Telegraphs use shape and animation in addition to color. One-click inspection explains every scroll in a concrete sentence.

# 12. Audio and Music

**Score direction:** Plucked strings, shakuhachi-like winds, light taiko, hand percussion and melodic woodwind over a playful adventure foundation; layered percussion increases in boss combat. Do not reduce the setting to a generic "Asian" sound-library collage: source-specific instrumentation should be considered intentionally and respectfully. Distinct clan leitmotifs help encounters feel memorable.

**Sound language:** Footsteps by broad material class; strong but short blade contacts; dry parry/timed-guard tick; fluttering cloth; shuriken metallic flutter; immediate dodge air movement; restrained UI page turns. Audio must clearly indicate guard break, target loss and active-art readiness. Vary pitch subtly without masking attack identity. Audio mix prioritizes dangerous enemy windups over decoration.

# 13. Technical Architecture and Source Reference

## 13.1 Referenced starting point — verified repository facts

The public project **Funny-Bones/ELDEN-RING-Combat-Rewrite** is a *Rust / Bevy 0.19* study sandbox recreating Elden Ring player movement and combat. It describes a pure **60 Hz** simulation with locomotion, directional rolls, lock-on, weapon chains, dual-wielding, guarding, hit-stop and weapon-following contact checks. The repository also states that timing tables, animations and optional sound assets are **generated from a user's owned Elden Ring game files** and are not included in the repository. Its README explicitly says **weapon skills, parrying and stat scaling** are not implemented; hostile dummy behavior is test-only. Source: https://github.com/Funny-Bones/ELDEN-RING-Combat-Rewrite (README, reviewed 10 Oct 2026).

**Critical distinction:** This project is a useful combat simulation reference, **not a drop-in, copyright-clear ninja game engine**. Its MIT code license does not grant permission to redistribute third-party game animations, sounds or parameter assets. A shipping implementation must replace extracted dependencies with rights-cleared original content and should seek qualified IP/legal review before distribution.

## 13.2 Recommended approach [PROPOSED]

For the proof of combat feel, use the existing Bevy sandbox as a technical experiment on a properly licensed local game install. In parallel, define a clean data model for original character animation state, input buffers, attack timings, hit geometry, stance, VFX events and enemy AI. Make the **production prototype independently runnable without generated Elden Ring assets** before committing to a release architecture.

**Engine decision gate:** Staying in Rust/Bevy preserves the existing simulation and avoids port complexity. Porting concepts to Godot may improve authoring ergonomics for rooms, dialogue and visual tooling, but requires substantial recreation of combat state, hit detection and animation integration. Choose based on vertical-slice editing speed, asset pipeline and measured gameplay results, not engine preference alone.

## 13.3 Proposed code modules

- **FixedSimulation:** 60 Hz deterministic movement, attacks, hit registration, status and combat tests.
- **ActionData:** source-agnostic original move records with startup/active/recovery, cancel windows, stamina, reach and movement curves.
- **AnimationBridge:** imported skeletons, root-motion mapping, pose events and original attack clips; supports chibi proportions.
- **EnemyAI:** perception, positioning, tell selection, commitment, recovery, group attack budgeting.
- **RunDirector:** seeded route graph, eligible room pools, rewards, persistence and unlock checks.
- **Presentation:** cel shader, particles, impact effects, camera framing, UI and spatial sound.
- **Telemetry / Replay:** seed, events, move timing, hitbox snapshots, combat deaths and balance data.

## 13.4 Performance and verification

Target **60 FPS** on a modest PC configuration **[TBD hardware floor]**, with locked 60 Hz gameplay simulation and bounded AI/particle work. Automate tests for attack windows, guard break, stagger immunity, status caps, seeded routes, no-softlock traversal, deterministic reward selections and save-data migration. Profile the busiest combat room before art complexity scales. A smooth frame rate is part of combat design, not a final optimization pass.

# 14. Accessibility and UX Requirements

Remappable controller and keyboard inputs; hold/toggle sprint and crouch options; camera sensitivity and inversion; independently configurable screenshake and flashes; subtitle sizing and combat cue captions; optional higher-contrast telegraphs with shape cues; color-vision-conscious scroll rarity and attack indicators; scalable HUD; controller reconnect handling; pause in single-player; prompt remapping in menus; low-distraction VFX option. Aim to let players adjust presentation and repetitive inputs without changing encounter fundamentals. Challenge assists such as extended timed-guard window or reduced incoming damage may be evaluated separately and labeled clearly.

Tutorial should teach move → lock-on → light attack → dodge → timed guard → use tool → select scroll in short interactive lessons. Advanced technique discoveries belong in optional training, not unskippable explanation pages. Input response needs to be consistent even when running through custom interfaces or cinematics.

# 15. Content Scope and Production Strategy

## 15.1 Prototype: prove fun before content

**Goal:** Is controlling a low-poly chibi ninja with deliberate timing actually enjoyable? Scope: one ninja rig, katana, flat dojo arena, one sparring dummy, one attacking basic enemy, locomotion, jump, basic attacks, dodge, guard, lock-on, hit-stop, stamina, simple UI and target 60 FPS. **Exit test:** player can consistently read enemy attacks, time a dodge and land deliberate counterattacks in a fully original, standalone executable.

## 15.2 Vertical slice: prove one roguelite cycle

**Goal:** One replayable act. Scope: Bamboo Grove, six authored rooms and varied room ordering, three common enemy types, one elite variant, Boar boss, three functional scrolls, shuriken and smoke tools, basic Moon Ink persistence, dojo restart, one first-time boss unlock, original sound/VFX/shader. **Exit test:** a new player can complete or fail a 7–12 minute first-act run, understands why they died, returns and makes a materially different scroll choice. This is not yet the full 25–35 minute product.

## 15.3 Early-access / release candidate target [PROPOSED]

Three acts, approximately **25–35 authored regular room templates** reused through curated encounter variations, three unique bosses, 10–12 standard enemy archetypes and elite variants, three launch weapons, approximately 18–24 balanced scrolls, five or fewer tool types, playable archetype loadouts, dojo progression, accessible controls and music/FX coverage. Numbers are recommendations, not locked promises. Expand only after room repetition, boss mastery and balance tests support the growth.

## 15.4 Explicit deferrals

Multiplayer, fully open-world traversal, unrestricted wall-running, dozens of weapon classes, large skill trees, procedural architecture mesh synthesis, four fully unique character animation sets, cinematic cutscenes for every boss and complex stealth simulation are post-launch or cut candidates. Avoid multiplying enemy/weapon animation requirements before confirming the pipeline.

# 16. Development Milestones and Acceptance Gates

| Gate | Must demonstrate | Stop / revise when |
|---|---|---|
| A — Combat foundation | Responsive original character, correct range and contact, readable dodge and guard | Animations/hitboxes disagree, or source-game dependency remains required |
| B — Art prototype | Cel shading, chibi silhouette, stable lighting and readable effects in one arena | Combat readability drops or asset creation cost is excessive |
| C — Enemy loop | Three enemies, group positioning, reliable tell/counter loop | Offscreen hits or stun-lock dominate |
| D — Roguelite loop | Seeded six-room route, scroll choice, defeat/restart/save | No meaningful route/build variety after repeated sessions |
| E — Vertical slice | Boar boss, one complete biome, player onboarding and telemetry | Players cannot identify why they died or camera obstructs fights |
| F — Content expansion | Second and third acts, tested scroll pool and progression | New content degrades frame pacing or balance regression rate grows |
| G — Release readiness | Accessibility, saves, control remaps, QA, legal asset review | Crashes, inaccessible routes, missing asset rights, unstable performance |

Design and engineering should maintain one shared balancing sheet for action timings, damage types, stagger thresholds and scroll triggers. Every new scroll gets automated proc tests and a combat readability review before being approved.

# 17. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Source-game asset/legal dependency | Blocks independent distribution | Replace all derived assets and tables; documented provenance and legal review |
| Chibi proportions conflict with inherited motion | Floating hands, bad blade reach | Original rig, retarget review, sweep hitbox calibration and attack authoring |
| Heavy combat pacing fights ninja mobility | Controls feel sluggish or inconsistent | Prototype with 2–3 dodge/attack cadence targets, test recovery and acceleration |
| Large 3D content cost | Slow production, inconsistent rooms | Modular prop kit, limited launch enemies, six-room slice first |
| Boss and scroll exploit loops | Trivializes challenge | Hard proc caps, diminishing stagger, effect cooldowns, replay tests |
| Camera / verticality failures | Unfair damage and disorientation | Limited authored wall-hops, occlusion fades and fight-zone checks |
| Art FX hides attacks | Player cannot diagnose defeat | VFX budgets and background/enemy contrast checks |
| Overly stingy economy | Failed attempts feel wasted | First-time unlock pacing simulation and rewarding early runs |
| Too much permanent power | Skill mastery loses significance | Horizontal unlocks, limited statistical progression |
| Uncontrolled feature accretion | Prototype never becomes a game | Written acceptance gates and explicit deferral list |

# 18. Playtesting, Metrics and Balance

**Observe, do not just survey.** Record room clear times, damage sources, attack whiffs, successful dodges and timed guards, boss attempts, scroll pick rates, scroll synergy frequency, tool usage, crashes and frame times. Link each result to a run seed and ability loadout.

**Vertical-slice research goals [TEST]:** (1) Most participants understand light/heavy/guard/dodge within first ten minutes, without sustained tutorial text. (2) At least 80% of reported lethal hits can be recognized in replay as having an available readable tell. (3) Players can explain what their chosen scroll changed. (4) Participants intentionally vary their approach on a second run. (5) Median combat camera failures and hitbox complaints trend downward across playtest builds. These are evaluation heuristics, not claims about expected actual player results.

Test expert and novice players separately. High-level players will identify overpowered dodge-cancel chains and boss abuse; novice players reveal input ambiguity, camera problems and unclear failures. Never tune only to developer skill.

# 19. Example Run — “The First Night”

**00:00 — Dojo.** Wanderer equips katana and shuriken. Mentor gives a one-sentence reminder about the stolen scrolls. Player enters the citadel gate.

**02:00 — First fight.** A Foot Soldier and Spear Sentry teach positioning. Reward offers Crimson Edge, Iron Resolve or Foxfire Mark. The player selects Crimson Edge.

**04:00 — Fork.** A lantern sign points left to an elite trial and right to a merchant. Player takes the elite. A heavy enemy pressures guard stamina, rewarding a timed counter.

**06:00 — Build choice.** Reward reveals Shadow Substitution. The player now has a dodge-and-counter plan; a later passive offers Afterimage as the third scroll, completing Ghost Counter.

**08:30 — The Boar.** Player watches an overhead slam, rolls through the active hit, triggers an afterimage and counters. A heavy attack breaks posture; finisher ends phase one. Player survives with one flask.

**10:00 — Victory.** The Boar drops a clan seal; the route to Lantern Village opens. The demo vertical slice stops here, with the mentor offering a new starting tool. In the full game the run continues through Acts II and III.

# 20. Decisions to Lock in Preproduction

1. **Engine:** Use Bevy all the way, or validate core simulation then implement in another engine? Recommend making the first stand-alone combat slice in Bevy before a port decision.
2. **Timed guard:** Use a Sekiro-like primary defense, or an occasional high-reward counter layered on Souls-like dodging? Recommend the latter to preserve build variety.
3. **Traversability:** Limit wall-hop to tagged surfaces at launch. Revisit full parkour only if it does not compromise encounter quality.
4. **Starter roster:** Four archetype *loadouts* versus four bespoke characters. Recommend shared rig and loadout templates.
5. **Run-length reality:** Confirm 25–35 minutes from measured pace after six-room prototype. Do not force encounter count to reach a number.
6. **Meta upgrades:** Keep most permanent progression horizontal; avoid mandatory damage grinding.
7. **Release plan:** PC controller-first, premium single-player; storefront and platform scope TBD.
8. **Title/IP:** *SHINOBI: Blade & Loop* is a **working title only**; perform trademark/name clearance before public branding.

# 21. One-Page Production Brief

**Make first:** a standalone ninja controller with original katana attack animations; a gorgeous, readable bamboo arena; one smart enemy; one defensible boss; three technique scrolls; a six-room randomized route; a dojo restart. **Playtest immediately.** If the sword feels wrong, don't build the castle. If the camera can't handle rooftops, don't add wall-running. If the techniques don't create distinct decisions, don't add twenty more scrolls.

**What must remain constant:** chunky GameCube-era forms, vibrant cel shading, expressive chibi proportions, lethal-but-readable combat, a short repeatable loop and techniques that transform fighting style. Everything else serves those qualities.

---

**Document note:** V0.1 is a comprehensive *design proposal*, not an implemented feature inventory. Specific combat values, economy pacing, narrative details, naming, procedural weights and content counts require prototype validation. Original concept artwork reflects an approved visual direction but should not be mistaken for playable game capture.

**Source reference:** Funny-Bones, *ELDEN-RING-Combat-Rewrite* (GitHub README; accessed 2026-10-10), https://github.com/Funny-Bones/ELDEN-RING-Combat-Rewrite. Copyright and trademark rights in Elden Ring assets are separate from the source repository's code license.
