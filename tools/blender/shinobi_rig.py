"""Procedural chibi hero blockout for SHINOBI: Blade & Loop.

Built headless. Run with:

    blender --background --python tools/blender/build_rig.py

GDD 11.2 is the brief this file answers:

    "Heroic chibi: 2.75-3.25 heads tall, oversized hair/hood, blocky forearms
     and gloves, short torso, clearly placed feet and broad readable weapon
     shapes. Avoid fine armor filigree and realistic anatomy."

Nothing here is traced, retargeted or derived from another game's files. Every
vertex is generated from the numbers in `Proportions`, which is the only place
the silhouette is decided. That is the whole point of keeping this a script
rather than a hand-sculpted `.blend`: the provenance of a vertex is a function
call, and a function call can be read.

Deliberately a *blockout*, in the sense GDD 11.1 asks for -- GameCube-era,
chunky, low-poly, and honest about being a proportion test rather than a
finished character. Each body part is a box bound rigidly to one bone. That is
not a simplification to be apologetic about: a chibi silhouette is carried by
proportion and negative space (GDD 11.2), both of which boxes express well, and
the risk GDD 17 names -- "Chibi proportions conflict with inherited motion /
Floating hands, bad blade reach" -- is a *smoothing* problem that does not exist
while every part is one rigid piece on one bone.

Units are metres, matching Godot. The total height is pinned to
`Tuning.CHARACTER_HEIGHT` (1.6 m) so the visual rig and the simulation's body
capsule agree; if one of those numbers moves, the proportions test fails and
says so, which is the intended behaviour.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import bpy
from mathutils import Vector

# GDD 11.2's numeric band. The build targets the middle of it deliberately:
# a rig parked at 2.75 has no room to get chunkier and one at 3.25 has no room
# to get less, so the target is a decision rather than a default.
HEADS_MIN = 2.75
HEADS_MAX = 3.25

# Mirrors Tuning.CHARACTER_HEIGHT in src/sim/tuning.gd. Cross-checked by
# tools/blender/test_proportions.py against the exported glTF.
CHARACTER_HEIGHT = 1.6
BODY_RADIUS = 0.4


@dataclass
class Proportions:
    """The silhouette, in metres. This dataclass *is* the character design.

    Every other module in the lane reads these numbers rather than the mesh, so
    that "why is the head that big" has one answer with one location.
    """

    # GDD 11.2's headline measurement. Measured sole to crown of the skull, the
    # usual convention; the hood sits above the crown and is asserted separately
    # as oversized, because counting it would make "3 heads tall" a way of
    # describing headwear.
    total_height: float = CHARACTER_HEIGHT
    heads_tall: float = 3.0

    # Head block, chin to crown.
    head_height: float = field(init=False)
    # Where the chin sits. 1.0 - head_height puts the whole head above the body.
    chin_y: float = field(init=False)

    # GDD 11.2: "oversized hair/hood". Taller and wider than the skull it covers,
    # which is what makes the silhouette read as chibi at gameplay distance.
    hood_height: float = 0.40
    hood_overhang: float = 0.06

    # GDD 11.2: "short torso". Hips to chest is deliberately less than one head,
    # which is most of what separates chibi from an ordinary 7-head figure.
    torso_height: float = 0.34
    hip_y: float = field(init=False)
    chest_y: float = field(init=False)

    # GDD 11.2: "blocky forearms and gloves". A box whose width is a large
    # fraction of its length is blocky; the ratio is what the test asserts.
    forearm_length: float = 0.22
    forearm_width: float = 0.11
    glove_size: float = 0.14

    # GDD 11.2: "clearly placed feet". Forward of the ankle by enough that the
    # foot is visible in a front-on camera, and low enough that it reads as
    # ground contact rather than a hovering block.
    foot_length: float = 0.20
    foot_height: float = 0.07

    thigh_length: float = 0.30
    shin_length: float = 0.28

    # GDD 11.2: "broad readable weapon shapes". A katana silhouette wide enough
    # to survive being 40 px tall on a 1080p screen. The simulation's hit
    # volume is deliberately wider still -- see Decision 4 in Docs/ARCHITECTURE.md.
    blade_length: float = 0.98
    blade_width: float = 0.056
    blade_thickness: float = 0.018

    def __post_init__(self) -> None:
        self.head_height = self.total_height / self.heads_tall
        self.chin_y = self.total_height - self.head_height
        # Feet, shins and thighs stack up from the sole to the hips.
        leg = self.foot_height + self.shin_length + self.thigh_length
        self.hip_y = leg
        self.chest_y = self.hip_y + self.torso_height


def _clear_scene() -> None:
    """Empty the file so a rebuild is idempotent.

    `bpy.ops.wm.read_factory_settings` rather than deleting objects by hand: a
    stale bone or a leftover vertex group from a previous shape would otherwise
    survive into the export, and the export is what the test measures.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _link(obj: bpy.types.Object, collection: bpy.types.Collection) -> bpy.types.Object:
    collection.objects.link(obj)
    return obj


def _add_box(
    name: str,
    collection: bpy.types.Collection,
    centre: tuple[float, float, float],
    size: tuple[float, float, float],
) -> bpy.types.Object:
    """An axis-aligned box, applied so the object carries no leftover scale.

    Applying the transform matters for more than tidiness: the glTF exporter
    bakes object scale into the exported mesh, and an unapplied scale is one of
    the ways a rig comes out of the pipeline subtly non-uniform. Applying it
    here means the exporter has nothing left to get wrong.
    """
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _link(obj, collection)


def _add_tapered_box(
    name: str,
    collection: bpy.types.Collection,
    centre: tuple[float, float, float],
    size_bottom: tuple[float, float, float],
    size_top: tuple[float, float, float],
) -> bpy.types.Object:
    """A box whose top face is a different size from its bottom.

    GDD 11.2 asks for "strong negative spaces" and bans "realistic anatomy".
    A pure cube with every face the same size has none of either -- it reads as
    a placeholder. Tapering the torso and the hood is the cheapest way to get a
    silhouette that reads as a character rather than as a blockout that failed.
    """
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=centre)
    obj = bpy.context.active_object
    obj.name = name
    sx, sy, sz = size_bottom
    tx, ty, _ = size_top
    # Move the top ring of the unit cube first, while the top verts are still
    # the ones at co.z > 0, then scale the whole thing. The taper is expressed
    # as a ratio against the bottom size so the caller can state the top ring in
    # the same units as the bottom and not have to compute a factor.
    for vert in obj.data.vertices:
        if vert.co.z > 0.0:
            vert.co.x *= tx / sx
            vert.co.y *= ty / sy
    obj.scale = (sx, sy, sz)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _link(obj, collection)


def _build_armature(collection: bpy.types.Collection, p: Proportions) -> bpy.types.Object:
    """A jointed skeleton whose rest pose is the measured pose.

    Bone tails are placed at the *joint* rather than at a constant offset, so
    the skeleton's proportions and the mesh's proportions cannot drift apart:
    they are the same numbers.
    """
    arm_data = bpy.data.armatures.new("hero_rig")
    arm_obj = bpy.data.objects.new("hero_rig", arm_data)
    collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    # (name, head_y, tail_y) along the spine/limb chain. Z is a small forward
    # offset for the spine so the chest is not a perfectly straight stack;
    # GDD 11.2's "short torso" is easier to read with a little S-curve.
    spine: list[tuple[str, float, float, float]] = [
        ("hips", p.hip_y, p.hip_y + 0.04, 0.0),
        ("spine", p.hip_y, p.hip_y + 0.16, -0.02),
        ("chest", p.hip_y + 0.16, p.chest_y, -0.03),
        ("neck", p.chest_y, p.chin_y, -0.01),
        ("head", p.chin_y, p.total_height, 0.0),
    ]
    for name, y0, y1, z in spine:
        bone = arm_data.edit_bones.new(name)
        bone.head = (0.0, y0, z)
        bone.tail = (0.0, y1, z)

    for parent, child in zip(
        ["hips", "spine", "chest", "neck"], ["spine", "chest", "neck", "head"]
    ):
        arm_data.edit_bones[child].parent = arm_data.edit_bones[parent]
        arm_data.edit_bones[child].use_connect = True

    for side, sx in (("L", 1.0), ("R", -1.0)):
        shoulder_y = p.chest_y - 0.04
        for suffix, y0, y1, x0 in (
            ("upper_arm", shoulder_y, shoulder_y - 0.20, 0.06),
            ("forearm", shoulder_y - 0.20, shoulder_y - 0.20 - p.forearm_length, 0.09),
        ):
            bone = arm_data.edit_bones.new(f"{suffix}.{side}")
            bone.head = (sx * x0, y0, 0.0)
            bone.tail = (sx * x0, y1, 0.0)
            bone.parent = arm_data.edit_bones[
                "chest" if suffix == "upper_arm" else f"upper_arm.{side}"
            ]

        hand_bone = arm_data.edit_bones.new(f"hand.{side}")
        hand_bone.head = (sx * 0.09, shoulder_y - 0.20 - p.forearm_length, 0.0)
        hand_bone.tail = (sx * 0.09, shoulder_y - 0.20 - p.forearm_length - 0.08, 0.0)
        hand_bone.parent = arm_data.edit_bones[f"forearm.{side}"]

        hip_y = p.hip_y - 0.02
        thigh = arm_data.edit_bones.new(f"thigh.{side}")
        thigh.head = (sx * 0.09, hip_y, 0.0)
        thigh.tail = (sx * 0.09, hip_y - p.thigh_length, 0.0)
        thigh.parent = arm_data.edit_bones["hips"]

        shin = arm_data.edit_bones.new(f"shin.{side}")
        shin.head = (sx * 0.09, hip_y - p.thigh_length, 0.0)
        shin.tail = (sx * 0.09, p.foot_height, 0.0)
        shin.parent = thigh

        foot = arm_data.edit_bones.new(f"foot.{side}")
        foot.head = (sx * 0.09, p.foot_height, 0.0)
        foot.tail = (sx * 0.09, p.foot_height, p.foot_length)
        foot.parent = shin

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def _skin(obj: bpy.types.Object, arm_obj: bpy.types.Object, bone: str) -> None:
    """Bind an object rigidly to one bone.

    Single-group, weight 1.0. That is a blockout decision, not a shortcut: one
    rigid piece per bone cannot stretch, so a proportion test on the exported
    mesh is measuring the design rather than a smoothed approximation of it.
    """
    vg = obj.vertex_groups.new(name=bone)
    vg.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    mod = obj.modifiers.new(name="Armature", type="ARMATURE")
    mod.object = arm_obj
    obj.parent = arm_obj


def build_hero(
    name: str = "hero_chibi",
    p: Proportions | None = None,
) -> tuple[bpy.types.Collection, bpy.types.Object, Proportions]:
    """Build the whole character into a fresh collection. Returns the collection,
    the armature, and the proportions actually used."""
    p = p or Proportions()
    _clear_scene()

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    collection = bpy.data.collections.new(name)
    scene.collection.children.link(collection)

    rig = _build_armature(collection, p)

    head_mid = (p.chin_y + p.total_height) * 0.5

    # Head and hood. The hood is built around the skull, not on top of it, so
    # it is genuinely oversized in all three axes rather than only in height.
    _skin(
        _add_box(
            f"{name}_skull",
            collection,
            (0.0, head_mid, 0.0),
            (p.head_height * 0.86, p.head_height, p.head_height * 0.80),
        ),
        rig,
        "head",
    )
    _skin(
        _add_tapered_box(
            f"{name}_hood",
            collection,
            (0.0, head_mid + p.hood_height * 0.18, -0.01),
            (
                p.head_height * 1.10 + p.hood_overhang,
                p.head_height + p.hood_height,
                p.head_height * 1.00 + p.hood_overhang,
            ),
            (p.head_height * 0.72, p.head_height * 0.34, p.head_height * 0.72),
        ),
        rig,
        "head",
    )

    # Short torso, tapered wider at the shoulders than the waist.
    _skin(
        _add_tapered_box(
            f"{name}_torso",
            collection,
            (0.0, (p.hip_y + p.chest_y) * 0.5, 0.0),
            (p.head_height * 0.78, p.torso_height, p.head_height * 0.52),
            (p.head_height * 1.02, p.torso_height, p.head_height * 0.62),
        ),
        rig,
        "chest",
    )
    _skin(
        _add_box(
            f"{name}_hips",
            collection,
            (0.0, p.hip_y, 0.0),
            (p.head_height * 0.82, 0.12, p.head_height * 0.56),
        ),
        rig,
        "hips",
    )

    for side, sx in (("L", 1.0), ("R", -1.0)):
        shoulder_y = p.chest_y - 0.04
        elbow_y = shoulder_y - 0.20
        wrist_y = elbow_y - p.forearm_length

        _skin(
            _add_box(
                f"{name}_upper_arm_{side}",
                collection,
                (sx * 0.07, (shoulder_y + elbow_y) * 0.5, 0.0),
                (0.085, 0.20, 0.085),
            ),
            rig,
            f"upper_arm.{side}",
        )
        # GDD 11.2's "blocky forearms": a near-square cross-section, which is
        # also what stops the arm disappearing at gameplay distance.
        _skin(
            _add_box(
                f"{name}_forearm_{side}",
                collection,
                (sx * 0.09, (elbow_y + wrist_y) * 0.5, 0.0),
                (p.forearm_width, p.forearm_length, p.forearm_width),
            ),
            rig,
            f"forearm.{side}",
        )
        _skin(
            _add_box(
                f"{name}_glove_{side}",
                collection,
                (sx * 0.09, wrist_y - p.glove_size * 0.4, 0.0),
                (p.glove_size, p.glove_size * 0.8, p.glove_size),
            ),
            rig,
            f"hand.{side}",
        )

        hip_y = p.hip_y - 0.02
        knee_y = hip_y - p.thigh_length
        _skin(
            _add_box(
                f"{name}_thigh_{side}",
                collection,
                (sx * 0.09, (hip_y + knee_y) * 0.5, 0.0),
                (0.10, p.thigh_length, 0.10),
            ),
            rig,
            f"thigh.{side}",
        )
        _skin(
            _add_box(
                f"{name}_shin_{side}",
                collection,
                (sx * 0.09, (knee_y + p.foot_height) * 0.5, 0.0),
                (0.09, p.shin_length, 0.09),
            ),
            rig,
            f"shin.{side}",
        )
        # Centred forward of the ankle, so the foot is a shape the camera sees
        # rather than a stub behind the shin.
        _skin(
            _add_box(
                f"{name}_foot_{side}",
                collection,
                (sx * 0.09, p.foot_height * 0.5, p.foot_length * 0.5 - 0.03),
                (0.11, p.foot_height, p.foot_length),
            ),
            rig,
            f"foot.{side}",
        )

    # The katana, held in the right hand: hilt at the hand, blade running along
    # the hand bone's -Y, which is where a two-handed grip puts it.
    hilt_y = wrist_y - p.glove_size * 0.8
    blade = _add_box(
        f"{name}_katana",
        collection,
        (0.0, hilt_y - 0.10 - p.blade_length * 0.5, 0.0),
        (p.blade_width, p.blade_length, p.blade_thickness),
    )
    _skin(blade, rig, "hand.R")
    _skin(
        _add_box(
            f"{name}_tsuba",
            collection,
            (0.0, hilt_y - 0.10, 0.0),
            (0.085, 0.018, 0.085),
        ),
        rig,
        "hand.R",
    )

    return collection, rig, p


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    """World-space AABB of an object, evaluated through any modifiers."""
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    corners = [obj.matrix_world @ Vector(c) for c in evaluated.bound_box]
    lo = Vector((min(c[i] for c in corners) for i in range(3)))
    hi = Vector((max(c[i] for c in corners) for i in range(3)))
    return lo, hi


def measure(collection: bpy.types.Collection, name: str = "hero_chibi") -> dict[str, object]:
    """Measure the built character.

    Reads geometry rather than `Proportions`, on purpose. The test's job is to
    catch the case where the design and the mesh disagree, and a test that
    re-reads the dataclass would report the intent instead of the result.

    Parts are keyed by stripping the rig's own name prefix, not by splitting on
    the first underscore -- the default name is `hero_chibi`, and splitting on
    "_" turns every part into `chibi_skull`.
    """
    by_part: dict[str, bpy.types.Object] = {}
    prefix = f"{name}_"
    for obj in collection.objects:
        if obj.type != "MESH":
            continue
        if not obj.name.startswith(prefix):
            raise KeyError(
                f"mesh {obj.name!r} is not part of rig {name!r}; "
                "measure() would be reading a collection it does not understand"
            )
        by_part[obj.name[len(prefix) :]] = obj

    missing = {"skull", "hood", "torso", "hips", "katana"} - set(by_part)
    if missing:
        raise KeyError(f"rig is missing expected parts: {sorted(missing)}")

    def bounds(part: str) -> tuple[Vector, Vector]:
        return world_bounds(by_part[part])

    def size(part: str) -> Vector:
        lo, hi = bounds(part)
        return hi - lo

    skull_lo, skull_hi = bounds("skull")
    foot_lo, foot_hi = bounds("foot_L")
    hood_lo, hood_hi = bounds("hood")
    blade_lo, blade_hi = bounds("katana")
    forearm = size("forearm_L")
    glove = size("glove_L")
    hip_lo, hip_hi = bounds("hips")
    torso_lo, torso_hi = bounds("torso")

    head_height = skull_hi.y - skull_lo.y
    total_height = skull_hi.y - min(foot_lo.y, foot_hi.y)
    blade_length = blade_hi.y - blade_lo.y
    blade_width = max(blade_hi.x - blade_lo.x, blade_hi.z - blade_lo.z)

    # The foot's forward extent past the shin, in world Z.
    shin_lo, shin_hi = bounds("shin_L")
    foot_forward = foot_hi.z - max(shin_lo.z, shin_hi.z)

    # The whole torso as the eye sees it: hips through chest. Comparing it to
    # one head is the direct reading of GDD 11.2's "short torso", and a figure
    # whose torso is under one head long is chibi rather than merely small.
    body_lo = min(hip_lo.y, torso_lo.y)
    body_hi = max(hip_hi.y, torso_hi.y)

    return {
        "head_height": head_height,
        "total_height": total_height,
        "heads_tall": total_height / head_height if head_height else 0.0,
        "hood_height": hood_hi.y - hood_lo.y,
        "hood_to_head": (hood_hi.y - hood_lo.y) / head_height,
        "hood_width_over_head": max(hood_hi.x - hood_lo.x, hood_hi.z - hood_lo.z)
        / max(skull_hi.x - skull_lo.x, skull_hi.z - skull_lo.z),
        "forearm_block_ratio": max(forearm.x, forearm.z) / max(forearm.y, 1e-9),
        "glove_over_forearm": max(glove.x, glove.z)
        / max(forearm.x, forearm.z, 1e-9),
        "torso_height": body_hi - body_lo,
        "torso_heads": (body_hi - body_lo) / head_height if head_height else 0.0,
        "foot_forward": foot_forward,
        "foot_height": foot_hi.y - foot_lo.y,
        "blade_width_over_length": blade_width / max(blade_length, 1e-9),
        "blade_length": blade_length,
        "sole_y": min(foot_lo.y, foot_hi.y),
        "crown_y": skull_hi.y,
        "hood_crown_y": hood_hi.y,
        "tri_count": sum(
            len(o.data.loop_triangles)
            for o in collection.objects
            if o.type == "MESH"
        ),
    }


def _triangulate(collection: bpy.types.Collection) -> None:
    """Cache loop_triangles so `measure` can read them without an explicit call."""
    for obj in collection.objects:
        if obj.type == "MESH":
            obj.data.calc_loop_triangles()


__all__ = [
    "Proportions",
    "build_hero",
    "measure",
    "HEADS_MIN",
    "HEADS_MAX",
    "CHARACTER_HEIGHT",
    "BODY_RADIUS",
]