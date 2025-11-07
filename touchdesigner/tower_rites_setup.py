"""TouchDesigner network builder for Tower Rites Itself.

This module exposes a :func:`build` helper that can be run from a Text DAT
inside TouchDesigner to programmatically assemble the core network for the
"Tower Rites Itself" project.  The resulting network focuses on sculptural
feedback-driven visuals with audio reactive modulation and a preset control
layer for live performance tweaking.

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
    tower.store("build_version", "2024-06-14")

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
    master.par.name0 = "feedback_mix"
    master.par.name1 = "audio_drive"
    master.par.name2 = "warp_amount"
    master.par.name3 = "bloom"
    master.par.name4 = "chromatic"
    master.par.name5 = "glitch_gate"

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

    glitch_switch = vis.create(levelTOP, "glitchSwitch")
    glitch_switch.inputs = [comp]
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

    vis.store("ramp", ramp)
    vis.store("noise", noise)
    vis.store("level", level)
    vis.store("displace", displace)
    vis.store("feedback", feedback)
    vis.store("transform", xform)
    vis.store("composite", comp)
    vis.store("glitch", glitch)
    vis.store("bloom", bloom)
    vis.store("chromatic", chroma)

    _wire_visual_parameters(vis, controls)


def _wire_visual_parameters(vis: "COMP", controls: "COMP") -> None:
    """Connect control channels to TOP parameter expressions."""
    mods = controls.fetch("modulation")
    master = controls.fetch("master")
    envelope = controls.fetch("envelope")
    lfo_slow = controls.fetch("lfo_slow")
    lfo_fast = controls.fetch("lfo_fast")

    feedback = vis.fetch("feedback")
    transform = vis.fetch("transform")
    comp = vis.fetch("composite")
    glitch = vis.fetch("glitch")
    bloom = vis.fetch("bloom")
    chroma = vis.fetch("chromatic")

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


def _build_output(out: "COMP", visuals: "COMP") -> None:
    """Set up the final output chain."""
    out.nodeWidth = 280
    out.nodeHeight = 160
    out.par.align = True
    out.par.alignorder = "lrbt"

    for child in list(out.children):
        child.destroy()

    viewer = out.create(nullTOP, "final")
    viewer.inputs = [visuals.fetch("chromatic")]
    viewer.par.resolutionw = 1280
    viewer.par.resolutionh = 720

    levels = out.create(levelTOP, "displayLevel")
    levels.inputs = [viewer]
    levels.par.brightness = 0.96

    out.store("output", levels)


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
