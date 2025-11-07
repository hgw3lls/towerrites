"""TouchDesigner network builder for Tower Rites Itself.

This module exposes a :func:`build` helper that can be run from a Text DAT
inside TouchDesigner to programmatically assemble the core network for the
"Tower Rites Itself" project.  The resulting network focuses on sculptural
feedback-driven visuals with audio reactive modulation, a preset control
layer for live performance tweaking, and a generative media block that
streams AI-generated imagery and film-textured archival footage into the
feedback loop.

Example usage inside TouchDesigner::

    # Drop this file into a Text DAT, set it to "DAT Execute" or press CTRL+R
    # after pointing "Module" to ``touchdesigner/tower_rites_setup``.
    from touchdesigner import tower_rites_setup
    tower_rites_setup.build()

The network that is created has the following high-level structure::

    /project1/towerRites
        controls      # container for master controls & presets
        visuals       # feedback based TOP chain with GLSL post processing
        output        # TOP to CHOP conversions + levels for final output

The function can be called repeatedly; it will destroy and recreate an
existing ``towerRites`` component so that tweaks in the script are reflected
in the live network.
"""
from __future__ import annotations

from typing import Optional


__all__ = ["build"]


def build(root: Optional["COMP"] = None) -> "COMP":
    """Construct or rebuild the Tower Rites Itself network.

    Parameters
    ----------
    root:
        Optional component that will act as the parent for the ``towerRites``
        container.  When omitted, the function defaults to ``/project1``.

    Returns
    -------
    COMP
        The newly created ``towerRites`` container component.
    """
    if root is None:
        root = op("/project1")

    if root is None:
        raise RuntimeError("Unable to resolve /project1. Pass an explicit root COMP.")

    existing = root.op("towerRites")
    if existing is not None:
        existing.destroy()

    tower = root.create(containerCOMP, "towerRites")
    tower.nodeWidth = 300
    tower.nodeHeight = 180
    tower.par.alignorder = "lrbt"
    tower.par.align = True
    tower.par.alignhorz = "left"
    tower.par.alignvert = "top"
    tower.par.display = True
    tower.par.w = 1280
    tower.par.h = 720

    controls = tower.create(baseCOMP, "controls")
    visuals = tower.create(containerCOMP, "visuals")
    output = tower.create(containerCOMP, "output")

    _build_controls(controls)
    _build_visuals(visuals, controls)
    _build_output(output, visuals)

    # Expose handy shortcuts on the parent container.
    tower.store("controls", controls)
    tower.store("visuals", visuals)
    tower.store("output", output)
    tower.store("build_version", "2024-06-20")

    return tower


def _build_controls(ctrl: "COMP") -> None:
    """Create the control surface components."""
    ctrl.nodeWidth = 220
    ctrl.nodeHeight = 160
    ctrl.par.align = True
    ctrl.par.alignorder = "lrbt"

    if ctrl.children:
        for child in list(ctrl.children):
            child.destroy()

    setup = ctrl.create(baseCOMP, "setup")
    setup.par.align = True
    setup.par.alignorder = "lrbt"

    # Master parameter storage using a Constant CHOP for easy export.
    master = setup.create(constantCHOP, "master")
    master.par.value0 = 0.6  # feedback mix
    master.par.value1 = 0.35  # audio drive
    master.par.value2 = 0.25  # tower warp
    master.par.value3 = 0.5  # bloom amount
    master.par.value4 = 0.2  # chromatic shift
    master.par.value5 = 0.0  # glitch gate
    master.par.value6 = 0.35  # ai blend
    master.par.value7 = 0.45  # archive blend
    master.par.value8 = 0.55  # film wear
    master.par.name0 = "feedback_mix"
    master.par.name1 = "audio_drive"
    master.par.name2 = "warp_amount"
    master.par.name3 = "bloom"
    master.par.name4 = "chromatic"
    master.par.name5 = "glitch_gate"
    master.par.name6 = "ai_blend"
    master.par.name7 = "archive_blend"
    master.par.name8 = "film_wear"

    # Audio input chain
    audio = setup.create(nullCHOP, "audio")
    audio.inputs = [setup.create(audioDeviceInCHOP, "audioIn")]
    audio.par.renamechan = True
    audio.par.renameto = "audio"
    audio.par.moncook = 1

    # Envelope follower for audio modulation
    envelope = setup.create(filterCHOP, "envelope")
    envelope.inputs = [audio]
    envelope.par.filtertype = "lag"
    envelope.par.lag = 0.12
    envelope.par.amp = 1.4

    # LFOs for slow modulation of tower states
    lfo_slow = setup.create(lfoCHOP, "lfoSlow")
    lfo_slow.par.type = "sine"
    lfo_slow.par.frequency = 0.015

    lfo_fast = setup.create(lfoCHOP, "lfoFast")
    lfo_fast.par.type = "noise"
    lfo_fast.par.frequency = 0.45
    lfo_fast.par.amp = 0.3

    # Combine control values for export.
    merge = setup.create(mathCHOP, "modulation")
    merge.inputs = [master, envelope, lfo_slow, lfo_fast]
    merge.par.combinechans = "byindex"
    merge.par.channame1 = "feedback_mix"
    merge.par.channame2 = "audio_drive"
    merge.par.channame3 = "warp_amount"
    merge.par.channame4 = "bloom"
    merge.par.channame5 = "chromatic"
    merge.par.channame6 = "glitch_gate"
    merge.par.channame7 = "audio_env"
    merge.par.channame8 = "lfo_slow"
    merge.par.channame9 = "lfo_fast"
    merge.par.channame10 = "ai_blend"
    merge.par.channame11 = "archive_blend"
    merge.par.channame12 = "film_wear"

    # Store a default generative prompt table for the AI driver to use.
    prompts = setup.create(tableDAT, "prompts")
    prompts.clear()
    prompts.appendRow(["key", "prompt"])
    prompts.appendRow(["base_prompt", "tower rites itself, brutalist scaffolding, decaying ritual architecture, archival newspaper ink bleeding, cinematic, dusk light"])
    prompts.appendRow(["alt_prompt", "tower rites itself, documentary fragments, analogue collage, machine hallucination, fractured lens bokeh"])
    prompts.par.edit = True

    ctrl.store("prompts", prompts)

    ctrl.store("master", master)
    ctrl.store("audio", audio)
    ctrl.store("envelope", envelope)
    ctrl.store("lfo_slow", lfo_slow)
    ctrl.store("lfo_fast", lfo_fast)
    ctrl.store("modulation", merge)


def _build_visuals(vis: "COMP", controls: "COMP") -> None:
    """Create the primary TOP network for the tower visuals."""
    vis.nodeWidth = 340
    vis.nodeHeight = 200
    vis.par.align = True
    vis.par.alignorder = "lrbt"

    for child in list(vis.children):
        child.destroy()

    ai_output = _build_ai_generator(vis, controls)

    archival_video = vis.create(moviefileinTOP, "archivalVideo")
    archival_video.par.file = "./media/archival/tower_press_video.mp4"
    archival_video.par.reload = True
    archival_video.par.play = True
    archival_video.par.rate = 0.95
    archival_video.par.loop = True

    archival_still = vis.create(moviefileinTOP, "archivalStill")
    archival_still.par.file = "./media/archival/tower_press_still.jpg"
    archival_still.par.reload = True
    archival_still.par.play = False

    archival_mix = vis.create(crossTOP, "archivalMix")
    archival_mix.inputs = [archival_video, archival_still]
    archival_mix.par.blend = 0.4

    # Base geometry using feedback network.
    ramp = vis.create(rampTOP, "heightRamp")
    ramp.par.type = "horizontal"

    noise = vis.create(noiseTOP, "foundationNoise")
    noise.par.resolutionw = 1280
    noise.par.resolutionh = 720
    noise.par.type = "alligator"
    noise.par.period = 6
    noise.par.harmonics = 7
    noise.par.exponent = 3.5

    level = vis.create(levelTOP, "foundationLevel")
    level.inputs = [noise]
    level.par.postadd = 0.15
    level.par.postmult = 0.8

    displace = vis.create(displaceTOP, "displaceTower")
    displace.inputs = [ramp, level]
    displace.par.displaceweight = 0.47

    feedback = vis.create(feedbackTOP, "feedback")
    feedback.inputs = [displace]

    xform = vis.create(transformTOP, "feedbackTransform")
    xform.inputs = [feedback]
    xform.par.rotate = 0.15
    xform.par.scale = 1.006
    xform.par.tx = 0.001
    xform.par.ty = -0.002

    comp = vis.create(compositeTOP, "feedbackComposite")
    comp.inputs = [displace, xform]
    comp.par.op = "add"
    comp.par.preadd = 0.4

    ai_cross = vis.create(crossTOP, "aiCross")
    ai_cross.inputs = [comp, ai_output]
    ai_cross.par.blend = 0.2

    archive_cross = vis.create(crossTOP, "archiveCross")
    archive_cross.inputs = [ai_cross, archival_mix]
    archive_cross.par.blend = 0.3

    glitch_switch = vis.create(levelTOP, "glitchSwitch")
    glitch_switch.inputs = [archive_cross]
    glitch_switch.par.brightness = 0.95

    glitch = vis.create(lookupTOP, "glitch")
    glitch.inputs = [glitch_switch, vis.create(noiseTOP, "glitchPattern")]
    glitch_op = glitch.inputs[1]
    glitch_op.par.type = "random"
    glitch_op.par.period = 0.3
    glitch_op.par.harmonics = 9
    glitch.par.index = 0.4

    bloom = vis.create(glslTOP, "bloom")
    bloom.inputs = [glitch]
    bloom.par.pixelcode = BLOOM_GLSL
    bloom.par.resolutionmenu = "frominput"

    chroma = vis.create(glslTOP, "chromaticOffset")
    chroma.inputs = [bloom]
    chroma.par.pixelcode = CHROMA_GLSL
    chroma.par.resolutionmenu = "frominput"

    film = vis.create(glslTOP, "filmTexture")
    film.inputs = [chroma]
    film.par.pixelcode = FILM_GLSL
    film.par.resolutionmenu = "frominput"

    vis.store("ramp", ramp)
    vis.store("noise", noise)
    vis.store("level", level)
    vis.store("displace", displace)
    vis.store("feedback", feedback)
    vis.store("transform", xform)
    vis.store("composite", comp)
    vis.store("ai_cross", ai_cross)
    vis.store("archival_cross", archive_cross)
    vis.store("glitch", glitch)
    vis.store("bloom", bloom)
    vis.store("chromatic", chroma)
    vis.store("film", film)
    vis.store("archival_mix", archival_mix)
    vis.store("archival_video", archival_video)
    vis.store("archival_still", archival_still)
    vis.store("ai_output", ai_output)

    _wire_visual_parameters(vis, controls)


def _wire_visual_parameters(vis: "COMP", controls: "COMP") -> None:
    """Connect control channels to TOP parameter expressions."""
    mods = controls.fetch("modulation")
    master = controls.fetch("master")
    lfo_slow = controls.fetch("lfo_slow")
    lfo_fast = controls.fetch("lfo_fast")

    feedback = vis.fetch("feedback")
    transform = vis.fetch("transform")
    comp = vis.fetch("composite")
    glitch = vis.fetch("glitch")
    bloom = vis.fetch("bloom")
    chroma = vis.fetch("chromatic")
    film = vis.fetch("film")
    ai_cross = vis.fetch("ai_cross")
    archive_cross = vis.fetch("archival_cross")
    archival_mix = vis.fetch("archival_mix")

    feedback.par.feedback = "op('{}')['feedback_mix']".format(master.path)
    transform.par.rotate = "0.06 + op('{}')['warp_amount'] * 12".format(mods.path)
    transform.par.scale = "1.002 + op('{}')['feedback_mix'] * 0.02".format(master.path)
    transform.par.tx = "-0.004 + op('{}')['lfo_slow'] * 0.01".format(mods.path)
    transform.par.ty = "-0.002 + op('{}')['lfo_fast'] * 0.015".format(mods.path)

    comp.par.preadd = "0.25 + op('{}')['audio_env'] * 0.45".format(mods.path)

    glitch_pattern = glitch.inputs[1]
    glitch_pattern.par.seed = "absTime.frame"
    glitch.par.index = "0.35 + op('{}')['glitch_gate'] * 0.4".format(master.path)

    bloom.par.multiadd = "0.4 + op('{}')['bloom'] * 1.6".format(master.path)
    bloom.par.multimult = "0.6 + op('{}')['audio_drive'] * 0.5".format(mods.path)

    chroma.par.pixelcode = CHROMA_GLSL
    chroma.par.par1 = "op('{}')['chromatic']".format(master.path)
    chroma.par.par2 = "op('{}')['audio_env']".format(mods.path)

    ai_cross.par.blend = "clamp(op('{}')['ai_blend'], 0, 1)".format(master.path)
    archive_cross.par.blend = "clamp(op('{}')['archive_blend'] + op('{}')['audio_env'] * 0.25, 0, 1)".format(master.path, mods.path)
    archival_mix.par.blend = "clamp(0.35 + op('{}')['lfo_slow'] * 0.3, 0, 1)".format(mods.path)

    film.par.pixelcode = FILM_GLSL
    film.par.par1 = "op('{}')['film_wear']".format(master.path)
    film.par.par2 = "op('{}')['audio_env']".format(mods.path)


def _build_output(out: "COMP", visuals: "COMP") -> None:
    """Set up the final output chain."""
    out.nodeWidth = 280
    out.nodeHeight = 160
    out.par.align = True
    out.par.alignorder = "lrbt"

    for child in list(out.children):
        child.destroy()

    viewer = out.create(nullTOP, "final")
    viewer.inputs = [visuals.fetch("film")]
    viewer.par.resolutionw = 1280
    viewer.par.resolutionh = 720

    levels = out.create(levelTOP, "displayLevel")
    levels.inputs = [viewer]
    levels.par.brightness = 0.96

    out.store("output", levels)


def _build_ai_generator(vis: "COMP", controls: "COMP") -> "TOP":
    """Build the AI generative media driver and return its output TOP."""
    ai = vis.create(baseCOMP, "aiGenerator")
    ai.nodeWidth = 240
    ai.nodeHeight = 160
    ai.par.align = True
    ai.par.alignorder = "lrbt"

    if ai.children:
        for child in list(ai.children):
            child.destroy()

    modulation = controls.fetch("modulation")
    prompts = controls.fetch("prompts")

    generated = ai.create(moviefileinTOP, "generated")
    generated.par.file = "./media/generated/latest.png"
    generated.par.reload = True
    generated.par.play = False

    null_out = ai.create(nullTOP, "out")
    null_out.inputs = [generated]

    driver = ai.create(textDAT, "driver")
    driver.text = AI_DRIVER_SCRIPT

    driver_exec = ai.create(datExecuteDAT, "driverExec")
    driver_exec.par.dat = driver
    driver_exec.par.frame = True
    driver_exec.par.active = True

    ai.store("audio_chop_path", modulation.path)
    ai.store("feedback_chop_path", modulation.path)
    ai.store("prompt_table", prompts.path)
    ai.store("generated_top", generated.path)
    ai.store("last_prompt_index", 0)
    ai.store("prompt_seed", 0)
    ai.store("enabled", True)
    ai.store("endpoint", "http://127.0.0.1:7860/sdapi/v1/img2img")
    ai.store("interval", 8.0)

    return null_out


AI_DRIVER_SCRIPT = """\
\"\"\"DAT Execute script that fetches generative imagery for Tower Rites.\"\"\"
import base64
import os
import random
import time

import requests

MEDIA_NAME = os.path.join('media', 'generated', 'latest.png')


def _ensure_media_path(project_folder):
    path = os.path.join(project_folder, MEDIA_NAME)
    folder = os.path.dirname(path)
    if not os.path.isdir(folder):
        try:
            os.makedirs(folder, exist_ok=True)
        except Exception:
            pass
    return path


def _build_prompt(comp):
    table_path = comp.fetch('prompt_table', '')
    prompt_dat = op(table_path) if table_path else None
    if prompt_dat is None:
        return "tower rites itself, analogue dream"

    prompts = []
    for row in prompt_dat.rows():
        if len(row) < 2 or row[0].val == 'key':
            continue
        prompts.append(row[1].val)

    if not prompts:
        return "tower rites itself, analogue dream"

    last_index = comp.fetch('last_prompt_index', 0)
    if last_index >= len(prompts):
        last_index = 0

    # Occasionally rotate prompts when the audio envelope spikes.
    audio = _fetch_audio(comp)
    if audio > 0.75:
        last_index = (last_index + 1) % len(prompts)

    comp.store('last_prompt_index', last_index)
    return prompts[last_index]


def _fetch_audio(comp):
    audio_path = comp.fetch('audio_chop_path', '')
    audio_chop = op(audio_path) if audio_path else None
    if audio_chop is None:
        return 0.0
    try:
        names = getattr(audio_chop, 'chanNames', [])
        chan = audio_chop['audio_env'] if 'audio_env' in names else audio_chop[0]
        return max(0.0, float(chan[0]))
    except Exception:
        return 0.0


def _fetch_feedback(comp):
    fb_path = comp.fetch('feedback_chop_path', '')
    fb_chop = op(fb_path) if fb_path else None
    if fb_chop is None:
        return 0.0
    try:
        names = getattr(fb_chop, 'chanNames', [])
        chan = fb_chop['feedback_mix'] if 'feedback_mix' in names else fb_chop[0]
        return max(0.0, float(chan[0]))
    except Exception:
        return 0.0


def _grab_archival_frame(comp, target_path):
    parent_comp = comp.parent()
    archive_top = parent_comp.fetch('archival_video', None)
    still_top = parent_comp.fetch('archival_still', None)
    source = archive_top if archive_top is not None else still_top
    if source is None:
        return None

    try:
        source.save(target_path, createFolders=True)
        with open(target_path, 'rb') as handle:
            return base64.b64encode(handle.read()).decode('utf-8')
    except Exception:
        return None


def onFrameStart(frame):
    comp = me.parent()
    if not comp.fetch('enabled', True):
        return

    base_interval = float(comp.fetch('interval', 8.0))
    audio_env = _fetch_audio(comp)
    effective_interval = max(2.0, base_interval - audio_env * 4.5)

    now = time.time()
    last_update = comp.fetch('last_update', 0.0)
    if now - last_update < effective_interval:
        return

    endpoint = comp.fetch('endpoint', '')
    if not endpoint:
        return

    prompt = _build_prompt(comp)
    feedback_level = _fetch_feedback(comp)

    project_folder = project.folder
    target_path = _ensure_media_path(project_folder)
    init_path = os.path.join(project_folder, 'media', 'generated', 'init_source.png')
    init_image = _grab_archival_frame(comp, init_path)

    payload = {
        'prompt': '{} :: memory recursion {}'.format(prompt, int(audio_env * 100)),
        'cfg_scale': 6.0 + feedback_level * 6.0,
        'steps': 30,
        'width': 1280,
        'height': 720,
        'seed': random.randint(0, 2 ** 31 - 1),
        'sampler_index': 'Euler a',
        'denoising_strength': min(0.9, 0.35 + audio_env * 0.45),
        'tiling': False,
        'negative_prompt': 'watermark, oversaturated, jpeg artifacts, disfigured, missing detail'
    }

    if init_image is not None:
        payload['init_images'] = [init_image]

    try:
        response = requests.post(endpoint, json=payload, timeout=35)
        response.raise_for_status()
    except Exception as err:
        print('AI driver request failed: {}'.format(err))
        comp.store('last_update', now)
        return

    data = response.json()
    images = data.get('images') if isinstance(data, dict) else None
    if not images:
        comp.store('last_update', now)
        return

    encoded = images[0]
    if encoded.startswith('data:'):
        encoded = encoded.split(',', 1)[1]

    try:
        with open(target_path, 'wb') as output:
            output.write(base64.b64decode(encoded))
    except Exception as err:
        print('Failed to write AI frame: {}'.format(err))
        comp.store('last_update', now)
        return

    comp.store('last_update', now)

    generated_path = comp.fetch('generated_top', '')
    generated_top = op(generated_path) if generated_path else None
    if generated_top is not None:
        try:
            generated_top.par.reloadpulse.pulse()
        except Exception:
            pass

"""


BLOOM_GLSL = """\
vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 st)
{
    vec4 sum = vec4(0.0);
    vec2 texel = 1.0 / uTD2DInfos[0].res;
    float bloom = uParm1.x;
    float spread = 3.5;

    for (int x = -2; x <= 2; ++x)
    {
        for (int y = -2; y <= 2; ++y)
        {
            vec2 offset = vec2(x, y) * texel * spread;
            sum += texture(sTD2DInputs[0], uv + offset);
        }
    }

    sum /= 25.0;
    vec4 base = texture(sTD2DInputs[0], uv);
    vec4 bloomColor = mix(base, sum, clamp(bloom, 0.0, 1.0));
    return vec4(bloomColor.rgb, 1.0);
}
"""


CHROMA_GLSL = """\
vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 st)
{
    float shift = uParm1.x;
    float drive = uParm2.x;
    vec2 texel = 1.0 / uTD2DInfos[0].res;

    vec2 offsetR = vec2(shift * 2.0, shift * -1.5) * texel * (0.2 + drive);
    vec2 offsetG = vec2(-shift * 1.5, shift * 1.0) * texel * (0.3 + drive * 0.6);
    vec2 offsetB = vec2(shift * 1.0, shift * 1.8) * texel * (0.5 + drive * 0.3);

    float r = texture(sTD2DInputs[0], uv + offsetR).r;
    float g = texture(sTD2DInputs[0], uv + offsetG).g;
    float b = texture(sTD2DInputs[0], uv + offsetB).b;

    return vec4(r, g, b, 1.0);
}
"""


FILM_GLSL = """\
vec3 hash(vec3 p)
{
    p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
             dot(p, vec3(269.5, 183.3, 246.1)),
             dot(p, vec3(113.5, 271.9, 124.6)));
    return fract(sin(p) * 43758.5453);
}


vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 st)
{
    float wear = clamp(uParm1.x, 0.0, 1.0);
    float audio = clamp(uParm2.x, 0.0, 1.0);
    vec4 base = texture(sTD2DInputs[0], uv);

    float time = uTime * 0.75;
    vec3 grain = hash(vec3(uv * uTD2DInfos[0].res.xy, time));
    float flicker = sin(time * 6.0) * 0.08;

    float vignette = smoothstep(1.2, 0.45, length(uv - vec2(0.5)));

    float scratches = 0.0;
    for (int i = -1; i <= 1; ++i)
    {
        vec2 coord = uv * uTD2DInfos[0].res.xy + vec2(float(i) * 0.5, time * 40.0);
        scratches += smoothstep(0.98, 1.0, hash(vec3(coord, time * 0.1)).r);
    }
    scratches = clamp(scratches * 0.25, 0.0, 1.0);

    vec3 worn = base.rgb + (grain - 0.5) * (0.35 + wear * 0.65);
    worn += flicker * wear * 0.5;
    worn = mix(worn, worn * vignette, 0.25 + wear * 0.35);
    worn += scratches * wear * (0.15 + audio * 0.25);

    return vec4(clamp(worn, 0.0, 1.0), base.a);
}
"""
