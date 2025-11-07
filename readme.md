# TowerRites Performance Toolkit

This repository now includes tools for both the audio (SuperCollider) and visual (TouchDesigner) sides of the Tower Rites Itself project.

## TouchDesigner network builder

- Scripted network constructor for the Tower Rites Itself visuals lives at [`touchdesigner/tower_rites_setup.py`](touchdesigner/tower_rites_setup.py).
- Run the module from a Text DAT inside TouchDesigner (set the DAT's `Language` to Python, point the `Module` parameter to `touchdesigner.tower_rites_setup`, and press `CTRL+R`) to instantiate a feedback-driven tower visual with audio-reactive controls.
- The script creates a `towerRites` container with `controls`, `visuals`, and `output` sections, plus GLSL TOPs for bloom, chromatic dispersion, and a new film texture shader that adds grain, scratches, and vignette wear.
- The visual chain folds in an AI media generator and an archival footage blend so the tower feedback loop can incorporate live-produced imagery, stills, and the historic Tower Press video feed.
- Core control channels (feedback mix, audio drive, warp amount, bloom, chromatic shift, glitch gate, AI blend, archival blend, film wear, LFOs, and audio envelope) are exposed via a `master` Constant CHOP and downstream `modulation` Math CHOP so they can be exported to MIDI controllers or UI widgets.

### Generative media workflow

1. Place the Tower Press reference footage inside `media/archival/` (e.g. `tower_press_video.mp4` and `tower_press_still.jpg`) relative to the `.toe` project.
2. Ensure the TouchDesigner Python environment has the `requests` package available (install via the built-in `pip` if necessary).
3. Provide an AI image/video endpoint—by default the DAT Execute script targets a local Automatic1111/Stable Diffusion WebUI server (`http://127.0.0.1:7860/sdapi/v1/img2img`). Update `aiGenerator`'s storage values if you are using RunwayML, Replicate, ComfyUI, or another gateway.
4. The `controls/setup/prompts` table DAT defines rotating prompt seeds. Modify/add rows to steer the hallucinations.
5. Audio envelope spikes advance prompts, while the feedback mix modulates CFG scale and denoising. Generated frames land in `media/generated/latest.png` and are reloaded into the network automatically.
6. Adjust the `ai_blend`, `archive_blend`, and `film_wear` channels (via the `master` Constant CHOP) to decide how prominently the generative textures, archival layers, and GLSL film wear appear in the composite.

## SuperCollider tape-loop sampler

The SuperCollider script that implements a tape-loop / MPC-style sampler environment lives at [`supercollider/tape_loop_sampler.scd`](supercollider/tape_loop_sampler.scd). It exposes a `~tapeLoop` environment for quickly capturing, overdubbing, and triggering loops from a MIDI controller or the keyboard.

## Features

- Three dedicated pads pre-sized for ~5s, ~15s, and ~30s tape loops.
- Quantised record/play scheduling via a dedicated `TempoClock`.
- Overdub support with configurable pre-level.
- Per-pad looped or one-shot playback with envelope-shaped stops.
- MIDI note mapping helper for pad-style controllers.
- Playback stage adds gentle wow/flutter modulation, tape saturation, hiss, and occasional drop-outs for a worn-loop character.

## Getting started

1. Open the script in SuperCollider and evaluate it (or place it in your startup folder).
2. After the server boots you should see `"Tape loop sampler ready..."` in the post window.
3. Call `~tapeLoop.listen.()` to route hardware inputs into the sampler bus.
4. Use `~tapeLoop.record.(padIndex);` to capture audio and `~tapeLoop.play.(padIndex);` to trigger a loop (pads 0, 1, and 2 correspond to roughly 5s, 15s, and 30s respectively).
5. Adjust tempo and quantisation with `~tapeLoop.setTempo.(bpm);` and `~tapeLoop.setQuant.(beats);`.
6. Map an MPC-style controller with `~tapeLoop.midiPads.(deviceID);` where `deviceID` is the MIDI source identifier reported by `MIDIClient.sources`.

Refer to the top of the script for additional helper functions such as `~tapeLoop.once`, `~tapeLoop.stop`, and `~tapeLoop.clear`. You can also pass optional keywords to `~tapeLoop.play`/`once` (e.g. `wow`, `flutter`, `saturation`, `hiss`, `tone`, `dropRate`, `dropDepth`) to fine-tune the tape-wear character per trigger.
