"""
render_sprites.py — render a 3D animated model into a game sprite sheet
with Blender, headless. Replaces the old Unity render pipeline.

Output matches what tools/pack_atlas.py and characterAnimator expect:

    8 columns = 8 facing directions, 1 row per animation frame,
    each cell CELL x CELL px (default 128), transparent background.

    column 1 faces the camera (down on screen), then counter-clockwise on
    screen in 45 degree steps: 2 down-right, 3 right, 4 up-right, 5 away
    (up), 6 up-left, 7 left, 8 down-left. This is the order
    Enemy:getDirectionToPlayer / player.getHeading pick with
    atan2(dx, dy) split into 45 degree sectors.

Usage (Blender 2.93+; everything after `--` goes to this script):

    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/render_sprites.py -- \\
        --model path/to/character.fbx --action Walk \\
        --out src/gfx/3d/mychar/walk.png --frames 16 --normals

    # list the actions a model contains
    ... -P tools/render_sprites.py -- --model character.glb --list

    # self-test without any asset (renders a procedural walker)
    ... -P tools/render_sprites.py -- --demo --out /tmp/demo.png --normals

Models: .fbx (e.g. Mixamo "FBX Binary, with skin"), .glb/.gltf, or .blend.
The model should face -Y (Blender "front") in its rest pose; if it doesn't,
use --yaw 90/180/-90. Keep one --ortho-scale for every animation of the same
character so they all render at the same size (the auto-fit value is printed
on each run; reuse it for the rest).
"""
import argparse
import math
import os
import sys
import tempfile

import bpy
import numpy as np
from mathutils import Vector

DIRECTIONS = 8


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser(prog="render_sprites.py", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--model", help=".fbx, .glb/.gltf or .blend file")
    p.add_argument("--demo", action="store_true", help="render a procedural test character instead of --model")
    p.add_argument("--list", action="store_true", help="list the model's actions and exit")
    p.add_argument("--action", help="action (animation) name; default: the first/active one")
    p.add_argument("--out", help="output sheet PNG path")
    p.add_argument("--cell", type=int, default=128, help="cell size in px (atlas uniform size is 128)")
    p.add_argument("--frames", type=int, default=0, help="resample the action to N frames (default: native frame count)")
    p.add_argument("--elevation", type=float, default=30.0, help="camera pitch above the horizon, degrees")
    p.add_argument("--yaw", type=float, default=0.0, help="extra model rotation (deg) if it does not face -Y at rest")
    p.add_argument("--ortho-scale", type=float, default=0.0, help="fixed camera ortho scale (default: auto-fit)")
    p.add_argument("--margin", type=float, default=1.1, help="auto-fit padding factor")
    p.add_argument("--normals", action="store_true",
                   help="also write <out>_normals.png: screen-space normals encoded n*0.5+0.5 "
                        "(x right, y down, z toward viewer), same layout")
    p.add_argument("--samples", type=int, default=16, help="Eevee render samples")
    args = p.parse_args(argv)
    if not args.list and not args.out:
        p.error("--out is required")
    if not args.model and not args.demo:
        p.error("--model or --demo is required")
    return args


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
        for cam in [o for o in bpy.data.objects if o.type in {"CAMERA", "LIGHT"}]:
            bpy.data.objects.remove(cam, do_unlink=True)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True)
    elif ext in {".glb", ".gltf"}:
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        sys.exit(f"unsupported model format: {ext}")


def build_demo():
    """A capsule 'body' with a nose pointing -Y and a bobbing, swaying
    animation — enough to check direction order and framing end to end."""
    bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=1.2, location=(0, 0, 0.6))
    body = bpy.context.object
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.25, location=(0, 0, 1.45))
    head = bpy.context.object
    bpy.ops.mesh.primitive_cone_add(radius1=0.1, depth=0.3, location=(0, -0.3, 1.45), rotation=(math.radians(90), 0, 0))
    nose = bpy.context.object
    for o, rgb in ((body, (0.2, 0.4, 0.9)), (head, (0.9, 0.8, 0.6)), (nose, (0.9, 0.2, 0.1))):
        mat = bpy.data.materials.new(o.name)
        mat.diffuse_color = (*rgb, 1)
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1)
        o.data.materials.append(mat)
    bpy.ops.object.empty_add(location=(0, 0, 0))
    rig = bpy.context.object
    rig.name = "DemoRig"
    for o in (body, head, nose):
        o.parent = rig
    rig.animation_data_create()
    action = bpy.data.actions.new("DemoWalk")
    rig.animation_data.action = action
    for f in range(1, 13):
        t = (f - 1) / 12 * 2 * math.pi
        rig.location = (0, 0, 0.08 * abs(math.sin(t)))
        rig.rotation_euler = (0, 0.15 * math.sin(t), 0)
        rig.keyframe_insert("location", frame=f)
        rig.keyframe_insert("rotation_euler", frame=f)


def animated_objects():
    return [o for o in bpy.data.objects if o.animation_data is not None or o.type == "ARMATURE"]


def pick_action(name):
    actions = list(bpy.data.actions)
    if not actions:
        return None
    if name:
        for a in actions:
            if a.name == name or a.name.split("|")[-1] == name:
                return a
        sys.exit(f"action '{name}' not found; available: {', '.join(a.name for a in actions)}")
    for o in animated_objects():
        if o.animation_data and o.animation_data.action:
            return o.animation_data.action
    return actions[0]


def assign_action(action):
    for o in animated_objects():
        if o.animation_data is None:
            o.animation_data_create()
        o.animation_data.action = action


def make_pivot(yaw_deg):
    """Parent every top-level object to one empty we can spin per direction."""
    bpy.ops.object.empty_add(location=(0, 0, 0))
    pivot = bpy.context.object
    pivot.name = "SpritePivot"
    for o in list(bpy.data.objects):
        if o is not pivot and o.parent is None and o.type not in {"CAMERA", "LIGHT"}:
            mw = o.matrix_world.copy()
            o.parent = pivot
            o.matrix_world = mw
    pivot["yaw"] = math.radians(yaw_deg)
    return pivot


def world_bounds(scene, frames):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for f in frames:
        whole = int(math.floor(f))
        scene.frame_set(whole, subframe=f - whole)
        depsgraph.update()
        for o in scene.objects:
            if o.type != "MESH":
                continue
            ev = o.evaluated_get(depsgraph)
            for corner in ev.bound_box:
                w = ev.matrix_world @ Vector(corner)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    return lo, hi


def setup_camera_and_lights(scene, center, radius, elevation_deg, ortho_scale, cell, samples):
    cam_data = bpy.data.cameras.new("SpriteCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new("SpriteCam", cam_data)
    scene.collection.objects.link(cam)
    e = math.radians(elevation_deg)
    dist = radius * 4 + 10
    cam.location = center + Vector((0, -math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (math.radians(90) - e, 0, 0)
    cam_data.clip_end = dist * 3
    scene.camera = cam

    sun_data = bpy.data.lights.new("Key", "SUN")
    sun_data.energy = 3.0
    sun = bpy.data.objects.new("Key", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    scene.collection.objects.link(sun)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.35, 0.35, 0.38, 1)
        bg.inputs["Strength"].default_value = 1.0

    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = samples
    scene.render.film_transparent = True
    scene.render.resolution_x = cell
    scene.render.resolution_y = cell
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"  # Filmic would shift sprite colours and normals
    scene.view_settings.look = "None"


def normal_material():
    """Emission of camera-space normal, remapped to screen convention
    (x right, y down, z toward viewer) and encoded n*0.5+0.5."""
    mat = bpy.data.materials.new("SpriteNormals")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    xf = nt.nodes.new("ShaderNodeVectorTransform")
    xf.vector_type = "NORMAL"
    xf.convert_from = "WORLD"
    xf.convert_to = "CAMERA"
    # Blender camera space: +x right, +y up, -z forward (into the scene).
    # Screen convention wanted: +x right, +y down, +z toward the viewer.
    # (MULTIPLY then ADD rather than MULTIPLY_ADD, which 2.93 lacks.)
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = (0.5, -0.5, -0.5)
    enc = nt.nodes.new("ShaderNodeVectorMath")
    enc.operation = "ADD"
    enc.inputs[1].default_value = (0.5, 0.5, 0.5)
    emit = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(geo.outputs["Normal"], xf.inputs["Vector"])
    nt.links.new(xf.outputs["Vector"], mul.inputs[0])
    nt.links.new(mul.outputs["Vector"], enc.inputs[0])
    nt.links.new(enc.outputs["Vector"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def render_cell(scene, path):
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1]  # Blender rows are bottom-up


def save_sheet(sheet, path):
    h, w = sheet.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), width=w, height=h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(sheet[::-1]).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def swap_materials(material):
    """Put `material` in every mesh slot; returns a restore function.
    (view_layer.material_override is ignored by Eevee in older Blenders.)"""
    saved = []
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        if not o.material_slots:
            o.data.materials.append(None)
            saved.append((o, None))
        for slot in o.material_slots:
            saved.append((slot, (slot.link, slot.material)))
            slot.link = "OBJECT"
            slot.material = material

    def restore():
        for target, state in reversed(saved):
            if state is None:
                target.data.materials.pop()
            else:
                target.link, target.material = state
    return restore


def render_sheet(scene, pivot, frames, cell, tmp, label, override=None):
    restore = swap_materials(override) if override is not None else None
    sheet = np.zeros((cell * len(frames), cell * DIRECTIONS, 4), dtype=np.float32)
    for row, f in enumerate(frames):
        whole = int(math.floor(f))
        scene.frame_set(whole, subframe=f - whole)
        for col in range(DIRECTIONS):
            # col 0 faces the camera (-Y); each step turns the model 45 deg so
            # its facing sweeps counter-clockwise on screen (right at col 2).
            pivot.rotation_euler = (0, 0, pivot["yaw"] + math.radians(45 * col))
            cellpx = render_cell(scene, os.path.join(tmp, f"{label}_{row}_{col}.png"))
            sheet[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = cellpx
        print(f"  {label}: frame {row + 1}/{len(frames)}", flush=True)
    if restore:
        restore()
    return sheet


def main():
    args = parse_args()
    reset_scene()
    if args.demo:
        build_demo()
    else:
        import_model(os.path.abspath(args.model))

    if args.list:
        for a in bpy.data.actions:
            s, e = a.frame_range
            print(f"action: {a.name}  frames {s:.0f}-{e:.0f} ({e - s + 1:.0f})")
        return

    scene = bpy.context.scene
    action = pick_action(args.action)
    if action:
        assign_action(action)
        start, end = action.frame_range
    else:
        start = end = scene.frame_current
    native = int(round(end - start)) + 1
    count = args.frames or native
    if count == native:
        frames = [start + i for i in range(count)]
    else:
        # Resample cyclically: a looping clip's frame after `end` is `start`.
        frames = [start + (end - start + 1) * i / count for i in range(count)]

    pivot = make_pivot(args.yaw)
    # Fit over every frame and every facing so nothing is clipped.
    lo, hi = world_bounds(scene, frames)
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 1e-3)
    ortho = args.ortho_scale or radius * 2 * args.margin
    setup_camera_and_lights(scene, center, radius, args.elevation, ortho, args.cell, args.samples)

    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    print(f"action={action.name if action else '<none>'} frames={count} "
          f"cell={args.cell} ortho_scale={ortho:.4f} elevation={args.elevation}")
    with tempfile.TemporaryDirectory() as tmp:
        save_sheet(render_sheet(scene, pivot, frames, args.cell, tmp, "colour"), out)
        print(f"wrote {out} ({args.cell * DIRECTIONS}x{args.cell * count})")
        if args.normals:
            nout = os.path.splitext(out)[0] + "_normals.png"
            save_sheet(render_sheet(scene, pivot, frames, args.cell, tmp, "normals", normal_material()), nout)
            print(f"wrote {nout}")

    print("\nadd to configs/production_atlas.json \"sources\":")
    print(f'  {{ "path": "<path relative to src/>", "directions": {DIRECTIONS}, '
          f'"frameWidth": {args.cell}, "frameHeight": {args.cell} }}')
    print(f"reuse --ortho-scale {ortho:.4f} for this character's other animations")


main()
