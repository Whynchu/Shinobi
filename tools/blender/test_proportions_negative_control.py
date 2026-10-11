"""Negative control for tools/blender/test_proportions.py.

    blender --background --python tools/blender/test_proportions_negative_control.py

A green proportions run means nothing on its own. The proprotions test asserts
the rig is 2.75-3.25 heads tall, upright, and roughly a metre and a half over
all; every one of those passes just as happily on an empty file if nothing else
is wrong with the measurement code. tests/test_art.gd already learned this
lesson for the shader checker -- `test_shader_checker` exists because a checker
that passes on broken input is worse than no checker at all -- and the same
argument applies here.

This script is that argument for the Blender lane. It takes the real exported
glTF, corrupts it the way the failure modes this pipeline can actually have
corrupt it, and runs the real suites. It exits non-zero if the real suite
*acepted* the corrupted mesh.

Corruptions, and why these and not others:

- **Geometry lying on its side.** `export_yup` flipped, or a unit conversion
  that quietly mapped Z-up onto Y. In the engine this is a character lying on
  their front, not an error, so nothing else would catch it.
- **Total height collapsed.** Non-uniform object scale applied on the way out
  of Blender, the classic un-applied-scale bug.
- **A dropped part.** Nothing is referencing the gloves, so a pipeline that
  culls unreferenced meshes removes them and the character comes out fine
  except for having no hands.

Exit code 0 means the negative control *confirmed the checker can fail*, which
is the opposite of what it sounds like: it is what makes the positive run mean
something.
"""

from __future__ import annotations

import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import test_proportions as suite  # noqa: E402


def _lay_flat() -> None:
    """Rotate every mesh's data so the character is lying face-down.

    Rotation applied to vertex coordinates rather than to the object transform,
    because an object transform is exactly the case a stale depsgraph would
    hide. Making the geometry itself wrong is what a real exporter bug produces.
    """
    for obj in suite.bpy.context.scene.collection.all_objects:
        if obj.type != "MESH":
            continue
        for vert in obj.data.vertices:
            x, y, z = vert.co
            vert.co[0], vert.co[1], vert.co[2] = x, -z, y
    bpy.context.view_layer.update()


def _collapse_y() -> None:
    """Squash the figure to a third of its height along Y."""
    for obj in suite.bpy.context.scene.collection.all_objects:
        if obj.type != "MESH":
            continue
        for vert in obj.data.vertices:
            vert.co.y *= 0.34
    bpy.context.view_layer.update()


def _drop_gloves() -> None:
    """Delete both gloves, silently, the way an unused-mesh prune would."""
    for obj in list(suite.bpy.data.objects):
        if obj.name.startswith("hero_chibi_glove_"):
            bpy.data.objects.remove(obj)


CASES: list[tuple[str, object]] = [
    ("laid_flat", _lay_flat),
    ("height_collapsed", _collapse_y),
    ("gloves_dropped", _drop_gloves),
]


def main() -> int:
    results: list[tuple[str, bool]] = []

    for label, corrupt in CASES:
        # Re-import fresh each time. A corruption applied to an already
        # corrupted file would compound, and the later cases would then pass
        # for reasons the first one caused rather than for anything they are
        # supposed to detect.
        suite.import_glb(suite.GLB)

        corrupt()

        # Parts are looked up *after* the corruption, not before. Blender frees
        # a datablock you delete, and any handle taken first then fails later
        # with "StructRNA of type Object has been removed" -- the lesson this
        # lane already paid for when the suite imported the file twice.
        parts = suite.find_parts(bpy.context.scene.collection)
        h = suite.Checks()
        suite.suite_presence(h, parts)
        suite.suite_pipeline(h, parts)

        # Same guard main() uses: proportions are only measured when every part
        # they read is present. Goes into the spreadsheet the same way the real
        # runner does, so that the suite for a dropped glove reads as "rejected"
        # rather than as a crash.
        missing = [p for p in suite.EXPECTED_PARTS if p not in parts]
        if not missing:
            suite.suite_gdd_11_2(h, suite.measure_imported(parts))

        rejected = h.failed > 0 and h.summary() != 0
        results.append((label, rejected))
        print(f"    {label:18s} {'rejected (good)' if rejected else 'ACCEPTED (bad)'}")

    print("")
    print("-" * 60)
    bad = [label for label, rejected in results if not rejected]
    if bad:
        print(f"  NEGATIVE CONTROL FAILED: unchanged suite accepted {bad}")
        return 1
    print(f"  all {len(results)} corruptions rejected; the checker can fail")
    return 0


if __name__ == "__main__":
    sys.exit(main())