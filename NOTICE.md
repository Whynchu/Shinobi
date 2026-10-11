# Notices

## Third-party material

### Funny-Bones / ELDEN-RING-Combat-Rewrite

The MIT-licensed combat study referenced in GDD 13.1 was consulted during
pre-production as a **structural reference only**. Its README, `src/sim/data.rs`,
`src/sim/player.rs`, `src/sim/mod.rs`, `src/sim/level.rs`, `src/sim/dummy.rs` and
`src/sim/tests.rs` were read.

No code from that project has been copied into this repository, and no Elden Ring
data, animation, sound or parameter table appears anywhere in it. That project
generates its own data from the game files of players who own a copy, and none
of that is present, derivable, or required here. This project is independently
runnable with no Elden Ring installation and no third-party game assets.

What was taken was architectural shape, which is not copyrightable expression:
the idea of a pure fixed-tick simulation separated from presentation, the
analytic swept-capsule hit test, per-hit stamina accounting, hit-stop, and a
behaviour test suite runnable without a window. The implementation is written
against GDD 4.2 and 5.3, and differs substantially - separate player and enemy
state machines, integer 60 Hz tick windows rather than accumulated floats,
authored blade sweeps rather than baked animation samples, and a posture and
timed-guard system the GDD requires and that project does not implement.

## Asset provenance

GDD 13.2 and 17 require rights-cleared original content and documented
provenance. Supporting that:

- Every authored move in `AttackTable` carries a `Provenance` field,
  `ORIGINAL` or `ESTIMATE`, so a tuning number nobody measured cannot be
  mistaken for one somebody did.
- All art, animation, audio and level content is to be produced for this project.
  No assets derived from another game's files may be committed. The `.gitignore`
  excludes `external/` for checkouts kept purely for study.
- GDD 18.8: *SHINOBI: Blade & Loop* is a working title only and requires
  trademark clearance before any public branding.

## Engine

Godot Engine is MIT licensed. Copyright (c) 2014-present Godot Engine
contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
See https://godotengine.org/license.

## Title

*SHINOBI: Blade & Loop* is a working title. SHINOBI is a trademark of Sega
Enterprises Co., Ltd. in certain territories. Clear the name before it appears on
anything public.