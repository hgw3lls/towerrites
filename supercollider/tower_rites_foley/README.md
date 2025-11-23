# Tower Rites Foley

A single SuperCollider performance script for live foley + musique concrète + tape loop cinema.

## Files
- `tower_rites_foley.scd` — full performance patch with groups, buses, cue helpers, and modular voices.

## Quick use
1. Boot SuperCollider server (`s.waitForBoot { ... }` is included in the script).
2. Evaluate the entire file. It sets up groups, buses, buffers, and SynthDefs.
3. Use the cue helpers at the bottom of the script (e.g., `~runCue.(\intro)` or `~runCue.(\concatenate)`) to step through a performance flow.
4. Adjust routings/levels via the environment variables declared after boot (e.g., `~micInChan`, `~loopCount`, `~foleyBufferDur`).

The script is written to be self-documenting with inline comments so you can modify or extend individual modules without hunting through multiple files.
