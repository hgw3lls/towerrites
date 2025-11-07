(
// Tape Loop / MPC-style sampler environment for SuperCollider
// -----------------------------------------------------------
// Drop this file into your startup folder or evaluate it manually.
// It provides an interactive ~tapeLoop environment with helpers to
// record, overdub, loop, and trigger pads with tempo-quantised timing.

s.waitForBoot {
    if(~tapeLoop.notNil) {
        // Clean up a previous instance if the file gets re-evaluated.
        try { ~tapeLoop.freeAll.() };
    };

    ~tapeLoop = IdentityDictionary.new;
    ~tapeLoop.padDurations = [5, 15, 30];
    ~tapeLoop.numPads = ~tapeLoop.padDurations.size; // how many virtual pads we have
    ~tapeLoop.quant = 0.25;       // default quantisation grid (in beats)
    ~tapeLoop.clock = TempoClock.new(120/60).permanent_(true);
    ~tapeLoop.masterGroup = Group.head(s);
    ~tapeLoop.fxGroup = Group.after(~tapeLoop.masterGroup);
    ~tapeLoop.outputBus = 0;
    ~tapeLoop.inputBus = Bus.audio(s, 2);

    // Utility helpers ------------------------------------------------------
    ~tapeLoop.resolveQuant = { |quant| 
        switch(quant,
            true, { ~tapeLoop.quant },
            false, { nil },
            nil, { nil },
            { quant }
        )
    };

    ~tapeLoop.schedule = { |func, quant=true|
        var q = ~tapeLoop.resolveQuant.(quant);
        if(q.isNil) {
            func.value;
        } {
            var next = ~tapeLoop.clock.nextTimeOnGrid(q);
            ~tapeLoop.clock.schedAbs(next, {
                func.value;
                nil;
            });
        };
    };

    ~tapeLoop.setTempo = { |bpm|
        ~tapeLoop.clock.tempo = bpm / 60;
    };

    ~tapeLoop.setQuant = { |beats|
        ~tapeLoop.quant = beats;
    };

    ~tapeLoop.status = {
        "--- Tape Loop Status ---".postln;
        ("Tempo: % bpm" % (~tapeLoop.clock.tempo * 60)).postln;
        ("Quant grid: % beats" % (~tapeLoop.quant ?? { "(off)" })).postln;
        ~tapeLoop.padState.do({ |state, idx|
            var flag = state[\recorded].if({ "rec" }, { "-" });
            var playing = state[\player].isNil.if({ "" }, { "playing" });
            var duration = state[\duration] ?? { ~tapeLoop.padDurations[idx] };
            (
                "Pad " ++ idx.asString ++
                " (" ++ duration.asStringPrec(3) ++ "s): " ++
                flag ++ " " ++ playing
            ).postln;
        });
        "--------------------------".postln;
    };

    // SynthDefs ------------------------------------------------------------
    SynthDef(\tl_inputTap, { |outBus|
        var sig = SoundIn.ar((0..1));
        Out.ar(outBus, sig);
    }).add;

    SynthDef(\tl_recorder, { |bufnum, inBus, preLevel=0|
        var sig = In.ar(inBus, 2);
        RecordBuf.ar(sig, bufnum, loop: 0, preLevel: preLevel, doneAction: 2);
    }).add;

    SynthDef(\tl_player, { |out=0, bufnum, rate=1, startPos=0, amp=1, pan=0, loop=1, gate=1, fade=0.02,
        wow=0.003, flutter=0.001, saturation=1.3, hiss=-45.dbamp, tone=3800, dropRate=0.08, dropDepth=0.25|
        var baseRate = BufRateScale.kr(bufnum) * rate;
        var wowLfo = Lag.kr(LFNoise2.kr(0.2) * wow, 0.4);
        var flutterLfo = LFNoise2.kr(5) * flutter;
        var modRate = baseRate * (1 + wowLfo + flutterLfo);
        var sig = PlayBuf.ar(2, bufnum, modRate, startPos: startPos, loop: loop);
        var dropouts = Lag.kr(Dust.kr(dropRate) * dropDepth, 0.03).clip(0, 0.95);
        var env = EnvGen.kr(Env.asr(fade, 1, fade), gate, doneAction: 2);
        sig = sig * (1 - dropouts);
        sig = sig * saturation;
        sig = sig.tanh;
        sig = LPF.ar(sig, tone.max(800));
        sig = Balance2.ar(sig[0], sig[1], pan);
        sig = sig * amp;
        sig = sig * env;
        sig = sig + (HPF.ar(WhiteNoise.ar(hiss), 2000) * env);
        Out.ar(out, sig);
    }).add;

    s.sync;

    // Pad preparation ------------------------------------------------------
    ~tapeLoop.setupPads = {
        ~tapeLoop.buffers = Array.fill(~tapeLoop.numPads, { |idx|
            var duration = ~tapeLoop.padDurations[idx];
            var frames = (s.sampleRate * duration).asInteger;
            Buffer.alloc(s, frames, 2);
        });
        s.sync;
        ~tapeLoop.buffers.do(_.zero);
        ~tapeLoop.padState = Array.fill(~tapeLoop.numPads, { |idx|
            IdentityDictionary[
                recorded: false,
                player: nil,
                duration: ~tapeLoop.padDurations[idx]
            ]
        });
        s.sync;
    };

    ~tapeLoop.freePads = {
        ~tapeLoop.padState.do({ |state|
            state[\player].tryPerform(\set, \gate, 0);
            state[\player].tryPerform(\free);
        });
        ~tapeLoop.buffers.do(_.free);
        ~tapeLoop.padState = nil;
        ~tapeLoop.buffers = nil;
    };

    ~tapeLoop.setupPads.();

    // IO routing -----------------------------------------------------------
    ~tapeLoop.listen = {
        ~tapeLoop.inputTap.tryPerform(\free);
        ~tapeLoop.inputTap = Synth.tail(~tapeLoop.masterGroup, \tl_inputTap, [\outBus, ~tapeLoop.inputBus]);
    };

    ~tapeLoop.stopListening = {
        ~tapeLoop.inputTap.tryPerform(\free);
        ~tapeLoop.inputTap = nil;
    };

    // Core actions ---------------------------------------------------------
    ~tapeLoop.record = { |pad=0, quant=true, overdub=false, preLevel=0.7|
        var action = {
            var buf = ~tapeLoop.buffers[pad];
            if(overdub.not) {
                buf.zero;
                s.sync;
            };
            ~tapeLoop.padState[pad][\player].tryPerform(\set, \gate, 0);
            ~tapeLoop.padState[pad][\player].tryPerform(\free);
            Synth.tail(~tapeLoop.masterGroup, \tl_recorder, [
                \bufnum, buf.bufnum,
                \inBus, ~tapeLoop.inputBus,
                \preLevel, overdub.if({ preLevel }, { 0 })
            ]);
            ~tapeLoop.padState[pad][\recorded] = true;
        };
        ~tapeLoop.schedule.(action, quant);
    };

    ~tapeLoop.play = { |pad=0, quant=true, amp=1, rate=1, pan=0, loop=true,
        wow=0.003, flutter=0.001, saturation=1.3, hiss=-45.dbamp, tone=3800, dropRate=0.08, dropDepth=0.25|
        var action = {
            var buf = ~tapeLoop.buffers[pad];
            if(~tapeLoop.padState[pad][\recorded].not) {
                ("Pad % is empty" % pad).warn;
            } {
                ~tapeLoop.padState[pad][\player].tryPerform(\set, \gate, 0);
                ~tapeLoop.padState[pad][\player].tryPerform(\free);
                ~tapeLoop.padState[pad][\player] = Synth.tail(~tapeLoop.masterGroup, \tl_player, [
                    \bufnum, buf.bufnum,
                    \out, ~tapeLoop.outputBus,
                    \amp, amp,
                    \rate, rate,
                    \pan, pan,
                    \loop, loop.asInteger,
                    \wow, wow,
                    \flutter, flutter,
                    \saturation, saturation,
                    \hiss, hiss,
                    \tone, tone,
                    \dropRate, dropRate,
                    \dropDepth, dropDepth
                ]);
            };
        };
        ~tapeLoop.schedule.(action, quant);
    };

    ~tapeLoop.once = { |pad=0, quant=true, amp=1, rate=1, pan=0,
        wow=0.003, flutter=0.001, saturation=1.3, hiss=-45.dbamp, tone=3800, dropRate=0.08, dropDepth=0.25|
        ~tapeLoop.play.(pad, quant, amp, rate, pan, false, wow, flutter, saturation, hiss, tone, dropRate, dropDepth);
    };

    ~tapeLoop.stop = { |pad=0, quant=false|
        var action = {
            ~tapeLoop.padState[pad][\player].tryPerform(\set, \gate, 0);
            ~tapeLoop.padState[pad][\player] = nil;
        };
        ~tapeLoop.schedule.(action, quant);
    };

    ~tapeLoop.clear = { |pad=0|
        var buf = ~tapeLoop.buffers[pad];
        buf.zero;
        ~tapeLoop.padState[pad][\recorded] = false;
        ~tapeLoop.stop.(pad, false);
    };

    ~tapeLoop.clearAll = {
        ~tapeLoop.numPads.do({ |i| ~tapeLoop.clear.(i) });
    };

    ~tapeLoop.freeAll = {
        ~tapeLoop.stopListening.();
        ~tapeLoop.freePads.();
        ~tapeLoop.inputBus.free;
        ~tapeLoop = nil;
    };

    // Example MIDI bindings -----------------------------------------------
    ~tapeLoop.midiPads = { |deviceName, chan=0|
        MIDIClient.init;
        MIDIIn.connectAll;
        ~tapeLoop._midiPads ?? { ~tapeLoop._midiPads = IdentityDictionary.new };
        ~tapeLoop._midiPads.do({ |def| def.free });
        ~tapeLoop._midiPads.clear;
        ~tapeLoop.numPads.do({ |idx|
            var note = 36 + idx;
            ~tapeLoop._midiPads[note] = MIDIdef.noteOn(("pad_%" % idx).asSymbol, { |vel, num|
                if(vel > 0) {
                    if(~tapeLoop.padState[idx][\recorded].not) {
                        ~tapeLoop.record.(idx);
                    } {
                        ~tapeLoop.play.(idx);
                    };
                } {
                    ~tapeLoop.stop.(idx);
                };
            }, note, chan: chan, srcID: deviceName);
        });
        "MIDI pads mapped".postln;
    };

    "Tape loop sampler ready. Call ~tapeLoop.listen.() to monitor inputs.".postln;
};
)
