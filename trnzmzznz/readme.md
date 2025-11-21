# Riot Collage (SuperCollider)

Riot Collage is an experimental sampler environment for folder-based mangling that lives entirely in `~riotCollage`. It maps your own audio crate into musique concrète tape loops, underground NYC drum patterns, voice cut-ups, and concatenative grain ribbons while routing everything through a dirty mix bus.

## Prerequisites
- SuperCollider 3.12+.
- A folder of stereo/mono audio files (`wav`, `aif`, `aiff`, `flac`, or `ogg`).
- Basic familiarity with evaluating SuperCollider code (booting the server, running `s.waitForBoot { ... }` blocks).

## Quickstart demo
1. Open [`riot_collage.scd`](./riot_collage.scd) in SuperCollider and update the `~riotCollage.config.folder` value near the top to point at your sample directory (it will warn if the folder is missing). You can also raise/lower `config.maxBuffers` to cap how many files are ingested.
2. Evaluate the entire file. Wait for the post window to show `Riot Collage ready. Call ~riotCollage.loadFolder.() then ~riotCollage.status.()`.
3. Run the following in the post window to load your sounds and start a demo scene:
   ```supercollider
   ~riotCollage.loadFolder.();      // ingest samples from the configured folder
   ~riotCollage.status.();          // print buffer/tag counts
   ~riotCollage.demoScene.();       // one-liner to arm submerge + concrete + NYC + voice + concat
   ```
4. Stop individual layers with `Pdef(\name).stop` (e.g., `Pdef(\riot_nyc).stop`) or clear everything with `~riotCollage.freeAll.()`.

## Function reference
All helpers live on the `~riotCollage` environment after evaluation.

### Configuration and status
- `config`: Dictionary of settings (`folder`, `maxBuffers`, `concreteQuant`, `nycBpm`, `swing`, `defaultOut`).
- `clock`: Dedicated `TempoClock` used by all patterns; tempo is derived from `config.nycBpm`.
- `loadFolder.(path=nil)`: Reads audio files from `path` (or `config.folder` if omitted), tags obvious kicks/snares/percussion/voice/bass by filename, stores metadata, and precomputes 16 evenly spaced slice start times.
- `status.()`: Prints buffer counts and how many files are tagged per category, the current clock BPM, and the configured source folder.
- `setBpm.(bpm)`: Update the shared `TempoClock` to a new BPM mid-set.

### Tagging, selection, and slices
- `resetTags.()`: Clears tag tables and ensures the `\any` bucket exists.
- `indexTag.(tag, buf)`: Adds a buffer to a specific tag and the `\any` catch-all.
- `pick.(tag=\any)`: Returns a random buffer number for the given tag.
- `slicePos.(bufnum)`: Returns a random slice start time (in seconds) for a buffer.

### Playback layers
- `concreteLooper.(quant=true)`: Launches a musique concrète loop pattern built from `\riot_player` with wow/flutter, hiss, randomised rates, and slice-based start positions. Quantizes to `config.concreteQuant` when `quant` is true.
- `nycBeats.()`: Starts a kick/snare/hat grid aimed at raw NYC underground energy, with swing (`config.swing`), distortion, and subtle stereo drift.
- `voiceCuts.()`: Streams dense vocal grains via `\riot_grain`, focusing on files tagged `\voice` when available.
- `concatStream.(tag=\any, targetTilt=0)`: Builds a concatenative grain ribbon over tagged slices using `\riot_concat`. `targetTilt` biases tonal tilt (negative = darker, positive = brighter).
- `demoScene.()`: Convenience macro that engages `submerge`, `concreteLooper`, `nycBeats`, `voiceCuts`, and a brightened `concatStream` in one call.

### Mix and cleanup
- `submerge.()`: Patches the `\riot_submerge` master FX (bit-crush + drive crossfade) onto the FX group.
- `freeAll.()`: Stops all `Pdef` layers, frees the mix bus, releases buffers, clears metadata/tags/slices, and removes the environment so you can re-evaluate cleanly.

## Suggested live-coding moves
- Swap the source crate mid-set with `~riotCollage.loadFolder.("/path/to/new/folder")` and re-run `status` to confirm tags.
- Tilt the concatenative ribbon brighter/darker by tweaking `targetTilt`, or retarget to a specific bucket (e.g., `\voice`, `\bass`, `\perc`).
- Alter the beat feel by editing `config.nycBpm`/`config.swing` and re-evaluating the file.
- Play with the tape-character controls on `\riot_player` inside `concreteLooper` (e.g., `wow`, `flutter`, `crush`, `grit`, `tone`) for more erosion.

## Cleanup
When you are done, run `~riotCollage.freeAll.()` to stop patterns, release buffers, and leave the server tidy. If you change BPM mid-set, you can restore the original feel with `~riotCollage.setBpm.(~riotCollage.config.nycBpm)`. When swapping sample folders, just rerun `loadFolder`—the engine frees old buffers and keeps tags tidy.
