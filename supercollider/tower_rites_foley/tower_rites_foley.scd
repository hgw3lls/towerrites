// Tower Rites Foley — single-file performance patch
// Combines tape loops, live foley capture, musique concrète shuffling, and a lightweight concatenative voice.
// Evaluate the whole file. Use the cue helpers at the bottom to step through a show.

s.waitForBoot {
    // -------------------------------
    // Configuration
    // -------------------------------
    ~micInChan = 0;              // input channel for live foley
    ~loopCount = 4;              // number of independent tape heads
    ~loopSeconds = 8;            // base loop length
    ~foleyBufferDur = 3;         // capture buffer length for quick replay/reverse
    ~concatLibrary = [           // replace with your own library of micro-sounds
        Platform.resourceDir +/+ "sounds/a11wlk01.wav"
    ];

    // -------------------------------
    // Groups and Buses
    // -------------------------------
    ~groups = ();
    ~groups.root = Group.head(s);
    ~groups.tape = Group.after(~groups.root);
    ~groups.folio = Group.after(~groups.tape); // live foley capture / replay
    ~groups.concrete = Group.after(~groups.folio);
    ~groups.concat = Group.after(~groups.concrete);
    ~groups.master = Group.after(~groups.concat);

    ~buses = ();
    ~buses.mic = Bus.audio(s, 2);
    ~buses.loops = Bus.audio(s, 2);
    ~buses.fx = Bus.audio(s, 2);
    ~buses.master = 0; // write directly to hardware outs

    // -------------------------------
    // Buffers
    // -------------------------------
    ~loopBufs = Array.fill(~loopCount, { Buffer.alloc(s, (~loopSeconds * s.sampleRate).asInteger, 1) });
    ~foleyBuf = Buffer.alloc(s, (~foleyBufferDur * s.sampleRate).asInteger, 1);
    ~concatBufs = ~concatLibrary.collect { |path| Buffer.readChannel(s, path, channels: [0]) };

    // -------------------------------
    // SynthDefs
    // -------------------------------
    SynthDef(\micRouter, { |outBus=0, inChan=0, amp=1|
        var sig = SoundIn.ar(inChan);
        // mild high-pass to keep room rumble in check
        sig = HPF.ar(sig, 70);
        Out.ar(outBus, sig * amp ! 2);
    }).add;

    SynthDef(\tapeLoopHead, { |outBus=0, buf=0, rate=1, amp=0.2, pan=0, recLevel=0.0, preLevel=1.0|
        var sig;
        sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, loop: 1);
        // gentle aging
        sig = HPF.ar(sig, 100);
        sig = LPF.ar(sig, 7500);
        // wow/flutter
        sig = sig * (1 + 0.03 * LFNoise1.kr(0.25));
        sig = sig * (1 + 0.015 * LFNoise1.kr(3));
        sig = tanh(sig * 1.4);
        RecordBuf.ar(In.ar(~buses.mic, 1), buf, loop: 1, recLevel: recLevel, preLevel: preLevel);
        Out.ar(outBus, Pan2.ar(sig * amp, pan));
    }).add;

    SynthDef(\foleyRec, { |buf, inBus=0, recLevel=1, preLevel=0|
        var sig = In.ar(inBus, 1);
        RecordBuf.ar(sig, buf, loop: 0, recLevel: recLevel, preLevel: preLevel, doneAction: 2);
    }).add;

    SynthDef(\foleyPlay, { |buf, outBus=0, rate=1, amp=0.5, pan=0|
        var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, doneAction: 2);
        sig = HPF.ar(sig, 180);
        sig = LPF.ar(sig, 8500);
        sig = sig * EnvGen.kr(Env.linen(0.01, BufDur.kr(buf) / rate.abs, 0.05), doneAction: 2);
        Out.ar(outBus, Pan2.ar(sig * amp, pan));
    }).add;

    SynthDef(\slicePlay, { |buf, outBus=0, start=0.0, end=0.5, amp=0.35, pan=0|
        var dur = end - start;
        var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf), startPos: start * BufSampleRate.kr(buf), doneAction: 2);
        sig = sig * EnvGen.kr(Env.linen(0.01, dur.max(0.01), 0.05), doneAction: 2);
        Out.ar(outBus, Pan2.ar(sig * amp, pan));
    }).add;

    SynthDef(\concreteBurst, { |buf, outBus=0, sliceDur=0.15, rate=1, amp=0.3|
        var trig = Dust.kr(6); // sprinkle bursts
        var start = TExpRand.kr(0.0, BufDur.kr(buf) - sliceDur, trig);
        var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf) * rate, trigger: trig, startPos: start * BufSampleRate.kr(buf));
        sig = HPF.ar(sig, 120);
        sig = LPF.ar(sig, 9000);
        Out.ar(outBus, sig * amp ! 2);
    }).add;

    SynthDef(\concatVoice, { |outBus=0, amp=0.18|
        var inAmp = Amplitude.kr(In.ar(~buses.mic, 1), 0.01, 0.1);
        var trig = Impulse.kr(8); // events per second
        var idx = (inAmp.linlin(0, 0.35, 0, (~concatBufs.size - 1))).clip(0, (~concatBufs.size - 1)).round;
        var buf = Select.kr(idx, ~concatBufs.collect(_.bufnum));
        var sig = PlayBuf.ar(1, buf, BufRateScale.kr(buf), trig);
        sig = sig * EnvGen.kr(Env.perc(0.005, 0.12), trig);
        Out.ar(outBus, sig * amp ! 2);
    }).add;

    SynthDef(\masterMix, { |inBus=0, fxBus=0, outBus=0, dry=1, wet=0.25, amp=1|
        var drySig = In.ar(inBus, 2);
        var fxSig = In.ar(fxBus, 2);
        var sig = (drySig * dry) + (fxSig * wet);
        sig = Limiter.ar(sig, 0.98, 0.02);
        Out.ar(outBus, sig * amp);
    }).add;

    // -------------------------------
    // Routing
    // -------------------------------
    ~micRouter = Synth.head(~groups.root, \micRouter, [\outBus, ~buses.mic, \inChan, ~micInChan]);
    ~master = Synth.tail(~groups.master, \masterMix, [\inBus, ~buses.loops, \fxBus, ~buses.fx, \outBus, ~buses.master, \amp, 1]);

    // -------------------------------
    // Helpers
    // -------------------------------
    ~startLoops = {
        ~loopSynths = ~loopBufs.collect { |buf, i|
            var rate = [0.5, 0.75, 1.0, 1.25].wrapAt(i);
            Synth.tail(~groups.tape, \tapeLoopHead, [\buf, buf, \rate, rate, \amp, 0.14, \pan, (i.linlin(0, ~loopBufs.size - 1, -0.6, 0.6))]);
        };
    };

    ~setLoopRecord = { |rec=0.0, pre=1.0|
        ~loopSynths.do { |synth| synth.set(\recLevel, rec, \preLevel, pre) };
    };

    ~captureFoley = { ~foleyRec = Synth.head(~groups.folio, \foleyRec, [\buf, ~foleyBuf, \inBus, ~buses.mic]) };
    ~playFoley = { |rate=1| Synth.tail(~groups.folio, \foleyPlay, [\buf, ~foleyBuf, \outBus, ~buses.loops, \rate, rate]) };

    ~concreteShuffle = { |buf|
        Routine({
            12.do {
                var start = rrand(0.0, (BufDur.ir(buf) * 0.8));
                var end = (start + rrand(0.05, 0.4)).clip(0, BufDur.ir(buf));
                Synth.tail(~groups.concrete, \slicePlay, [\buf, buf, \outBus, ~buses.loops, \start, start, \end, end, \pan, rrand(-0.7, 0.7)]);
                (rrand(0.08, 0.35)).wait;
            }
        }).play;
    };

    ~startConcreteBurst = { |buf|
        Synth.tail(~groups.concrete, \concreteBurst, [\buf, buf, \outBus, ~buses.fx, \amp, 0.22]);
    };

    ~startConcat = { ~concatSynth = Synth.tail(~groups.concat, \concatVoice, [\outBus, ~buses.loops]) };
    ~stopConcat = { ~concatSynth.tryPerform(\free) };

    // -------------------------------
    // Cue system (minimal examples)
    // -------------------------------
    ~cues = (
        intro: {
            "Cue: intro — start quiet tape beds.".postln;
            ~startLoops.();
        },
        overdub: {
            "Cue: overdub — write foley into loops.".postln;
            ~setLoopRecord.(0.28, 0.75);
        },
        capture: {
            "Cue: capture one foley gesture now.".postln;
            ~captureFoley.();
        },
        replay: {
            "Cue: replay captured foley forward and reverse.".postln;
            ~playFoley.(1);
            ~playFoley.(-1);
        },
        concrete: {
            "Cue: collage shuffle from a buffer.".postln;
            ~concreteShuffle.(~concatBufs[0]);
        },
        burst: {
            "Cue: sustained burst layer.".postln;
            ~startConcreteBurst.(~concatBufs[0]);
        },
        concatenate: {
            "Cue: tower answers with concatenative voice.".postln;
            ~startConcat.();
        },
        fade: {
            "Cue: fade down.".postln;
            ~setLoopRecord.(0.0, 1.0);
            ~loopSynths.do { |s| s.set(\amp, 0.08) };
            ~master.set(\amp, 0.6, \wet, 0.15);
        }
    );

    ~runCue = { |name| (~cues[name] ? { ("No cue called %").format(name).postln }).value };

    "Tower Rites Foley ready. Try ~runCue.(\\intro);".postln;
};
