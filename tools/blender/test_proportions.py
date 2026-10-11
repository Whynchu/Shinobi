"""GDD 11.2 proportions test for the chibi hero, run headless:

    blender --background --python tools/blender/test_proportions.py
    blender --background --python tools/blender/test_proportions.py -- --only=height

Exits non-zero on any failure, and also on running zero assertions, because a
test that silently no-ops is worse than no test: the architECTURE.md lesson this
project already paid for is a headless runner reporting "0 assertions passed"
with exit 0 while every suite quietly did nothing.

**Why this re-imports the glTF instead of measuring the live scene.** Measuring
the Blender scene would only prove `shinobi_rig.py` agrees with itself. The
interesting failures live in the pipeline: a flipped `export_yup`, a scale that
did not survive the exporter, an armature modifier applied in rest pose or not
at all, a part silently dropped because nothing was using it. All of those
produce a perfectly healthy `.blend` and a broken character in the game. So
the only measurement that means anything is one taken of the file the engine
loads.

GDD 11.2, the thing under test:

    "Heroic chibi: 2.75-3.25 heads tall, oversized hair/hood, blocky forearms
     and gloves, short torso, clearly placed feet and broad readable weapon
     shapes."
"""

from __future__ import annotations

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import shinobi_rig as rig  # noqa: E402

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSET_DIR = os.path.join(REPO_ROOT, "assets", "characters")
ASSET_NAME = "hero_chibi"
GLB = os.path.join(ASSET_DIR, f"{ASSET_NAME}.glb")

# Every part `measure_imported` reaches for. Stated in one list so a missing
# part is a named failure rather than a KeyError half way through the suite --
# a dropped glove is exactly the failure mode this pipeline can have, because
# nothing in the build references the gloves and a pipeline that prunes
# unreferenced meshes would remove them without noticing.
EXPECTED_PARTS = [
    "skull", "hood", "torso", "hips",
    "foot_L", "shin_L", "forearm_L", "glove_L", "katana",
]


class Checks:
    """A deliberately tiny assertion counter.

    Same contract as tests/harness.gd on the Godot side: count, report, and
    refuse to pass a run that asserted nothing.
    """

    def __init__(self) -> None:
        self.passed = 0
        self.failed = 0
        self.failures: list[str] = []

    def ok(self, condition: bool, message: str) -> bool:
        if condition:
            self.passed += 1
        else:
            self.failed += 1
            self.failures.append(message)
            print(f"    FAIL  {message}")
        return condition

    def between(self, value: float, low: float, high: float, message: str) -> bool:
        return self.ok(
            low <= value <= high,
            f"{message} (expected {low}..{high}, got {value:.5f})",
        )

    def near(self, value: float, expected: float, message: str, eps: float = 1e-3) -> bool:
        return self.ok(
            abs(value - expected) <= eps,
            f"{message} (expected {expected}, got {value:.5f})",
        )

    def summary(self) -> int:
        print("-" * 60)
        if self.passed == 0:
            print("  NO ASSERTIONS RAN")
            return 2
        if self.failed == 0:
            print(f"  {self.passed} assertions passed")
            return 0
        print(f"  {self.passed} passed, {self.failed} FAILED")
        for failure in self.failures:
            print(f"    - {failure}")
        return 1


def import_glb(path: str) -> bpy.types.Collection:
    """Import the exported glTF into an empty file and return its collection."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)

    collection = bpy.data.collections.get(ASSET_NAME)
    if collection is None:
        # Some importer versions drop the name and rebuild collections from the
        # glTF scene. Fall back to the scene's own root collection rather than
        # guessing, so a rename is a visible failure and not a silent pass over
        # an empty scene.
        collection = bpy.context.scene.collection
    return collection


def find_parts(collection: bpy.types.Collection) -> dict[str, bpy.types.Object]:
    prefix = f"{ASSET_NAME}_"
    return {
        obj.name[len(prefix) :]: obj
        for obj in collection.all_objects
        if obj.type == "MESH" and obj.name.startswith(prefix)
    }


def bounds(obj: bpy.types.Object) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    # Force the view layer to settle before reading matrix_world. Without this,
    # a transform changed since the last update is reported from the old one --
    # and a stale depsgraph hides a rotation, which would make an
    # "the rig is upright" assertion pass on a character lying on the floor.
    bpy.context.view_layer.update()

    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    corners = [obj.matrix_world @ rig.Vector(c) for c in evaluated.bound_box]
    lo = tuple(min(c[i] for c in corners) for i in range(3))
    hi = tuple(max(c[i] for c in corners) for i in range(3))
    return lo, hi


def suite_presence(h: Checks, parts: dict[str, bpy.types.Object]) -> None:
    """Every part the measurements need actually arrived.

    Its own suite rather than a guard inside `measure_imported`, because "the
    blockout has the parts of a blockout" is a claim worth seeing as a checked
    line. If a part is missing, none of the proportion measurements can run, and
    a suite that cannot run must not be counted as a suite that passed.
    """
    print("\n  every part survived the export")
    for part in EXPECTED_PARTS:
        h.ok(part in parts, f"{ASSET_NAME}_{part} is present in the exported glTF")


def measure_imported(parts: dict[str, bpy.types.Object]) -> dict[str, float]:
    """Same measurements as `shinobi_rig.measure`, read off the imported file.

    Duplicated rather than reused because the whole point is to measure the
    exported artefact. Calling the builder's own helper would reintroduce
    exactly the self-agreement this test exists to avoid.

    Raises KeyError if a required part is missing; `suite_presence` is what
    keeps that from being what a reader sees.
    """
    skull_lo, skull_hi = bounds(parts["skull"])
    hood_lo, hood_hi = bounds(parts["hood"])
    foot_lo, foot_hi = bounds(parts["foot_L"])
    shin_lo, shin_hi = bounds(parts["shin_L"])
    hip_lo, hip_hi = bounds(parts["hips"])
    torso_lo, torso_hi = bounds(parts["torso"])
    blade_lo, blade_hi = bounds(parts["katana"])
    fore_lo, fore_hi = bounds(parts["forearm_L"])
    glove_lo, glove_hi = bounds(parts["glove_L"])

    head_height = skull_hi[1] - skull_lo[1]
    sole_y = min(foot_lo[1], foot_hi[1])
    total_height = skull_hi[1] - sole_y

    fore = (fore_hi[0] - fore_lo[0], fore_hi[1] - fore_lo[1], fore_hi[2] - fore_lo[2])
    glove = (glove_hi[0] - glove_lo[0], glove_hi[1] - glove_lo[1], glove_hi[2] - glove_lo[2])

    body_lo = min(hip_lo[1], torso_lo[1])
    body_hi = max(hip_hi[1], torso_hi[1])

    return {
        "head_height": head_height,
        "total_height": total_height,
        "heads_tall": total_height / head_height if head_height else 0.0,
        "sole_y": sole_y,
        "hood_to_head": (hood_hi[1] - hood_lo[1]) / head_height,
        "hood_width_over_head": max(hood_hi[0] - hood_lo[0], hood_hi[2] - hood_lo[2])
        / max(skull_hi[0] - skull_lo[0], skull_hi[2] - skull_lo[2]),
        "forearm_block_ratio": max(fore[0], fore[2]) / max(fore[1], 1e-9),
        "glove_over_forearm": max(glove[0], glove[2]) / max(fore[0], fore[2], 1e-9),
        "torso_heads": (body_hi - body_lo) / head_height if head_height else 0.0,
        "foot_forward": foot_hi[2] - max(shin_lo[2], shin_hi[2]),
        "blade_width_over_length": max(blade_hi[0] - blade_lo[0], blade_hi[2] - blade_lo[2])
        / max(blade_hi[1] - blade_lo[1], 1e-9),
        "tri_count": float(
            sum(len(o.data.loop_triangles) for o in parts.values())
        ),
    }


# --- The suites -----------------------------------------------------------------


def suite_pipeline(h: Checks, parts: dict[str, bpy.types.Object]) -> None:
    """The export has to survive the round trip before proportions mean anything."""
    print("\n  the export survives the round trip")

    # Bail out rather than read an empty measurement. A missing part is
    # reported by `suite_presence`, where the missing name is visible; here it
    # would only show up as a KeyError on a dictionary key, which says nothing
    # about which of nine parts has gone.
    if not h.ok(
        all(p in parts for p in EXPECTED_PARTS),
        "the glTF imports into the parts this suite measures",
    ):
        return

    collection = bpy.context.scene.collection
    m = measure_imported(parts)

    # A Y-up export that was not converted back would leave the character lying
    # along Z with a total height near zero, and would be the single most likely
    # way for this whole pipeline to produce something broken.
    h.near(m["sole_y"], 0.0, "the sole sits on the floor plane, so the rig is upright")
    h.near(m["total_height"], rig.CHARACTER_HEIGHT, "height survives the exporter",
           eps=0.01)

    # The simulation's body capsule is 1.6 m and the game never scales the
    # visual rig to fit it, so a rig that exports at a different size is a real
    # gameplay bug and not a cosmetic one.
    h.near(m["total_height"], rig.CHARACTER_HEIGHT,
           "total height matches Tuning.CHARACTER_HEIGHT, which the sim capsule uses")

    armatures = [o for o in collection.all_objects if o.type == "ARMATURE"]
    h.ok(len(armatures) >= 1, "the skeleton survives the export, so clips can be attached later")

    skinned = [o for o in parts.values() if o.type == "MESH" and len(o.vertex_groups) > 0]
    h.ok(len(skinned) >= len(parts),
         "every mesh part keeps a skin, so none of them is left rigid in world space")


def suite_gdd_11_2(h: Checks, m: dict[str, float]) -> None:
    """The proportions GDD 11.2 actually names, measured on the exported file."""
    print("\n  GDD 11.2: heroic chibi proportions")

    # "2.75-3.25 heads tall" -- the headline number, and the one a reviewer will
    # check by eye before reading anything else.
    h.between(m["heads_tall"], rig.HEADS_MIN, rig.HEADS_MAX,
              "2.75-3.25 heads tall")

    # "oversized hair/hood". Taller than the skull it covers is the silhouette
    # doing the work; wider than it in at least one horizontal axis is what
    # makes it read from behind, which is where the camera usually is.
    h.ok(m["hood_to_head"] > 1.25,
         "oversized hair/hood: the hood is taller than the skull it covers "
         f"(ratio {m['hood_to_head']:.3f})")
    h.ok(m["hood_width_over_head"] > 1.10,
         "oversized hair/hood: and wider than the skull in at least one axis "
         f"(ratio {m['hood_width_over_head']:.3f})")

    # "short torso". Under one head is the line between chibi and merely small.
    h.ok(m["torso_heads"] < 1.0,
         f"short torso: hips to chest is under one head ({m['torso_heads']:.3f} heads)")

    # "blocky forearms and gloves". A forearm whose cross-section is a decent
    # fraction of its length does not vanish when it is 30 px tall.
    h.ok(m["forearm_block_ratio"] >= 0.40,
         f"blocky forearms: cross-section/length is at least 0.40 "
         f"({m['forearm_block_ratio']:.3f})")
    h.ok(m["glove_over_forearm"] > 1.0,
         "blocky gloves: the glove is bigger across than the forearm it caps "
         f"({m['glove_over_forearm']:.3f})")

    # "clearly placed feet". Forward of the shin by enough to be visible in a
    # front-on camera, which is a camera question, not a modelling one.
    h.ok(m["foot_forward"] > 0.05,
         f"clearly placed feet: the foot projects forward of the shin "
         f"({m['foot_forward']:.3f} m)")

    # "broad readable weapon shapes". Below ~0.045 of its length a blade stops
    # reading as a blade once it is small on screen, and GDD 16 Gate B stops
    # when "combat readability drops".
    h.ok(m["blade_width_over_length"] >= 0.045,
         f"broad readable weapon shapes: the blade is at least 0.045 of its "
         f"length wide ({m['blade_width_over_length']:.4f})")

    # GDD 11.2 also bans "fine armor filigree". A blockout that cannot express
    # filigree cannot grow it by accident, so the budget is the triangle count.
    h.ok(m["tri_count"] > 0, f"the rig has geometry ({int(m['tri_count'])} triangles)")
    h.ok(m["tri_count"] <= 2000,
         f"low-poly blockout, well inside a cel-shaded budget "
         f"({int(m['tri_count'])} <= 2000 triangles)")


def main() -> int:
    only = ""
    argv = sys.argv
    if "--" in argv:
        for arg in argv[argv.index("--") + 1 :]:
            if arg.startswith("--only="):
                only = arg[7:]

    print("")
    print("SHINOBI: Blade & Loop -- chibi hero proportions (GDD 11.2)")
    print(f"  Blender {bpy.app.version_string}, measuring the exported glTF")

    h = Checks()

    if not os.path.exists(GLB):
        h.ok(False, f"{ASSET_NAME}.glb exists (run tools/blender/build_rig.py first)")
        print("")
        return h.summary()

    # Imported exactly once. Re-reading the file inside a suite would invalidate
    # every object handle taken before it -- Blender frees the old datablocks,
    # and a stale handle fails later with "StructRNA of type Object has been
    # removed", which is a confusing way to learn you called read_factory twice.
    collection = import_glb(GLB)
    parts = find_parts(collection)

    if only in ("", "presence"):
        suite_presence(h, parts)

    if only in ("", "pipeline"):
        suite_pipeline(h, parts)

    # Proportions can only be measured when every part the measurement reaches
    # for is there. Running them anyway would turn a missing glove into a
    # KeyError half way down the output, which is a bad way to report a design
    # problem that this suite exists to name cleanly.
    missing = [p for p in EXPECTED_PARTS if p not in parts]
    if missing:
        print("")
        for part in missing:
            print(f"    missing part: {ASSET_NAME}_{part}")
    else:
        m = measure_imported(parts)
        if only in ("", "proportions"):
            suite_gdd_11_2(h, m)
        print("")
        for key in sorted(m):
            print(f"    {key:26s} {m[key]:.5f}")

    print("")
    return h.summary()


if __name__ == "__main__":
    # `sys.exit` is what carries the status back to the shell. Blender's own
    # `--python` entry point ignores a non-zero return from main(), so the exit
    # code has to come from the interpreter, not from the function.
    sys.exit(main())