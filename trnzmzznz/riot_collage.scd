(
// Riot Collage: experimental collage engine for folder-based sample mangling
// -------------------------------------------------------------------------
// Aims:
// 1) musique concrète tape loops & MPC-style grids
// 2) raw underground NYC beat energy (afropunk/afrofuturist/punk-noise attitude)
// 3) voice-cutup sampler
// 4) concatenative grain streams glued from your folder of audio files
//
// Usage:
//   - Set ~riotCollage.config.folder to your audio folder (wav/aif/flac/ogg).
//   - Evaluate this file. Wait for "Riot Collage ready".
//   - Call ~riotCollage.loadFolder.(); then trigger helper play functions below.
//
// The design keeps everything in a single environment (~riotCollage)
// so you can re-evaluate safely during live-coding sessions.

s.waitForBoot {
    if(~riotCollage.notNil) {
        try { ~riotCollage.freeAll.() };
    };

    ~riotCollage = IdentityDictionary.new;
    ~riotCollage.config = (
        folder: PathName(Platform.userHomeDir).fullPath, // change this to your sample crate
        maxBuffers: 256,
        concreteQuant: 0.25,
        nycBpm: 92,
        swing: 0.08,
        defaultOut: 0
    );

    ~riotCollage.clock = TempoClock.new(~riotCollage.config.nycBpm/60).permanent_(true);
    ~riotCollage.masterGroup = Group.head(s);
    ~riotCollage.fxGroup = Group.after(~riotCollage.masterGroup);
    ~riotCollage.buffers = List.new;
    ~riotCollage.meta = IdentityDictionary.new; // maps bufnum -> metadata
    ~riotCollage.tags = IdentityDictionary.new; // tag -> List of bufnums
    ~riotCollage.slices = IdentityDictionary.new; // bufnum -> start positions

    // --- SynthDefs -------------------------------------------------------
    SynthDef(\riot_player, { |out=0, bufnum, startPos=0, rate=1, amp=1, pan=0,
        wow=0.002, flutter=0.001, hiss=-50.dbamp, grit=1.1, tone=4200,
        loop=1, fade=0.02, crush=1| // crush (>1) ups distortion and bit fuzz
        var baseRate = BufRateScale.kr(bufnum) * rate;
        var wowLfo = Lag.kr(LFNoise2.kr(0.25) * wow, 0.6);
        var flutterLfo = LFNoise2.kr(7) * flutter;
        var modRate = baseRate * (1 + wowLfo + flutterLfo);
        var sig = PlayBuf.ar(2, bufnum, modRate, startPos: startPos * BufFrames.kr(bufnum), loop: loop);
        var dropouts = Lag.kr(Dust.kr(0.12) * 0.35, 0.02).clip(0, 0.8);
        sig = sig * (1 - dropouts);
        sig = sig * grit;
        sig = tanh(sig);
        sig = LPF.ar(sig, tone.max(900));
        sig = HPF.ar(sig, 40);
        sig = sig + (HPF.ar(WhiteNoise.ar(hiss), 2000) * (1 - dropouts));
        sig = Decimator.ar(sig, crush.max(1), crush.max(1));
        sig = Balance2.ar(sig[0], sig[1], pan);
        sig = sig * amp * EnvGen.kr(Env.asr(fade, 1, fade), doneAction: 2);
        Out.ar(out, sig);
    }).add;

    SynthDef(\riot_grain, { |out=0, bufnum, rate=1, dur=0.18, dens=12, pan=0,
        warp=0.4, hp=80, lp=8500, tilt=0.0, amp=0.9|
        var trig = Impulse.kr(dens);
        var pos = LFNoise1.kr(dens * 0.7).range(0, BufDur.kr(bufnum));
        var sig = TGrains.ar(2, trig, bufnum, rate * BufRateScale.kr(bufnum), pos, dur,
            pan: LFNoise2.kr(3).range(-1, 1) + pan,
            envbufnum: -1);
        sig = BHiShelf.ar(sig, 1200, rq: 0.6, db: tilt.linlin(-1, 1, -9, 9));
        sig = HPF.ar(sig, hp);
        sig = LPF.ar(sig, lp);
        sig = sig * amp;
        Out.ar(out, sig);
    }).add;

    SynthDef(\riot_concat, { |out=0, bufnum, slicePos=0, amp=0.9, tilt=0, grainDur=0.11,
        jitter=0.03, spread=0.75|
        var trig = Impulse.kr(1 / grainDur);
        var pos = (slicePos + LFNoise2.kr(8) * jitter).clip(0, BufDur.kr(bufnum));
        var sig = TGrains.ar(2, trig, bufnum, BufRateScale.kr(bufnum), pos, grainDur,
            pan: LFNoise2.kr(4).range(-spread, spread), envbufnum: -1);
        sig = BHiShelf.ar(sig, 3000, rq: 0.6, db: tilt.linlin(-1, 1, -9, 9));
        sig = tanh(sig * 1.2);
        Out.ar(out, sig * amp);
    }).add;

    SynthDef(\riot_submerge, { |inbus, out=0, crush=6, drive=2.2, wet=0.35|
        var sig = In.ar(inbus, 2);
        var dirty = sig * drive;
        dirty = tanh(Decimator.ar(dirty, crush, crush));
        sig = XFade2.ar(sig, dirty, (wet * 2 - 1));
        Out.ar(out, sig);
    }).add;

    s.sync;

    // --- Utilities -------------------------------------------------------
    ~riotCollage.resetTags = {
        ~riotCollage.tags = IdentityDictionary.new;
        ~riotCollage.tags[\any] = List.new;
    };

    ~riotCollage.indexTag = { |tag, buf|
        ~riotCollage.tags[tag] ?? { ~riotCollage.tags[tag] = List.new };
        if(~riotCollage.tags[tag].includes(buf.bufnum).not) {
            ~riotCollage.tags[tag].add(buf.bufnum);
        };
        if(~riotCollage.tags[\any].includes(buf.bufnum).not) {
            ~riotCollage.tags[\any].add(buf.bufnum);
        };
    };

    ~riotCollage.analyzeBuffer = { |buf, path|
        var slices = 16;
        var starts = Array.series(slices, 0, buf.duration / slices);
        ~riotCollage.slices[buf.bufnum] = starts;
        ~riotCollage.meta[buf.bufnum] = (
            path: path,
            dur: buf.duration,
            frames: buf.numFrames
        );
    };

    ~riotCollage.loadFolder = { |path|
        var p = path ?? { ~riotCollage.config.folder };
        var pn = PathName(p);
        var audioExts = ["wav", "aif", "aiff", "flac", "ogg"];
        if(pn.exists.not) { ("[riot] Folder missing: %" % pn.fullPath).warn; ^nil };

        ~riotCollage.buffers.do(_.free);
        ~riotCollage.buffers.clear;
        ~riotCollage.resetTags.();

        var audioFiles = pn.files.select({ |f|
            audioExts.includes((f.extension ?? { "" }).asString.toLower)
        }).copyToList.keep(~riotCollage.config.maxBuffers);

        audioFiles.do({ |f|
            Buffer.readChannel(s, f.fullPath, channels: [0, 1], action: { |buf|
                ~riotCollage.buffers.add(buf);
                ~riotCollage.analyzeBuffer.(buf, f.fullPath);

                var lower = f.fileName.toLower;
                if(lower.contains("kick")) { ~riotCollage.indexTag.(\kick, buf) };
                if(lower.contains("snare")) { ~riotCollage.indexTag.(\snare, buf) };
                if(lower.contains("clap")) { ~riotCollage.indexTag.(\clap, buf) };
                if(lower.contains("perc")) { ~riotCollage.indexTag.(\perc, buf) };
                if(lower.contains("vox") or: { lower.contains("voice") }) { ~riotCollage.indexTag.(\voice, buf) };
                if(lower.contains("bass")) { ~riotCollage.indexTag.(\bass, buf) };
            });
        });

        s.sync;
        if(~riotCollage.buffers.isEmpty) {
            "[riot] No buffers loaded; check extensions or folder path.".warn;
        } {
            if(audioFiles.size >= ~riotCollage.config.maxBuffers) {
                ("[riot] Loaded % (capped at config.maxBuffers) from %" % [~riotCollage.buffers.size, pn.fullPath]).postln;
            } {
                ("Loaded % buffers from %" % [~riotCollage.buffers.size, pn.fullPath]).postln;
            };
        };
    };

    ~riotCollage.pick = { |tag=\any|
        var list = ~riotCollage.tags[tag] ?? { ~riotCollage.tags[\any] };
        if(list.isEmpty) { nil } { list.choose };
    };

    ~riotCollage.slicePos = { |bufnum|
        (~riotCollage.slices[bufnum] ?? { [0] }).choose;
    };

    ~riotCollage.status = {
        "--- Riot Collage ---".postln;
        ("Buffers: %" % ~riotCollage.buffers.size).postln;
        ~riotCollage.tags.keysValuesDo({ |tag, list|
            ("%: %" % [tag, list.size]).postln;
        });
        "Clock bpm:".post; (~riotCollage.clock.tempo * 60).round(0.1).postln;
        ("Source folder: %" % ~riotCollage.config.folder).postln;
        "--------------------".postln;
    };

    ~riotCollage.setBpm = { |bpm|
        ~riotCollage.config.nycBpm = bpm;
        ~riotCollage.clock.tempo_(bpm / 60);
        ("Clock tempo updated to % bpm" % bpm).postln;
    };

    // --- Style scripts ---------------------------------------------------
    ~riotCollage.concreteLooper = { |quant=true|
        Pdef(\riot_concrete,
            Pbind(
                \instrument, \riot_player,
                \out, ~riotCollage.config.defaultOut,
                \bufnum, Pfunc { ~riotCollage.pick.(\any) },
                \dur, Pwrand([~riotCollage.config.concreteQuant, ~riotCollage.config.concreteQuant*2, ~riotCollage.config.concreteQuant*0.5], [0.4, 0.3, 0.3], inf),
                \startPos, Pfunc { |ev| var dur = (~riotCollage.meta[ev[\bufnum]][\dur] ?? { 1 }).max(0.001); ~riotCollage.slicePos.(ev[\bufnum]) / dur },
                \rate, Pexprand(0.45, 1.35),
                \amp, Pexprand(0.3, 0.9),
                \pan, Pwhite(-0.9, 0.9),
                \wow, Pwhite(0.001, 0.009),
                \flutter, Pwhite(0.0005, 0.004),
                \tone, Pexprand(1100, 6200),
                \loop, 1,
                \crush, Pwhite(1, 5),
                \grit, Pexprand(1.0, 2.0)
            )
        );
        quant.if({ Pdef(\riot_concrete).play(~riotCollage.clock, quant: ~riotCollage.config.concreteQuant) }, {
            Pdef(\riot_concrete).play(~riotCollage.clock)
        });
        "concrete loop pattern started".postln;
    };

    ~riotCollage.nycBeats = {
        var kick = Pbind(
            \instrument, \riot_player,
            \bufnum, Pfunc { ~riotCollage.pick.(\kick) ?? { ~riotCollage.pick.(\any) } },
            \startPos, 0,
            \rate, 1,
            \amp, 1.2,
            \pan, Pwhite(-0.1, 0.1),
            \crush, 1,
            \grit, 1.8,
            \dur, Pseq([0.5, 0.5, 0.25, 0.75], inf)
        );
        var snare = Pbind(
            \instrument, \riot_player,
            \bufnum, Pfunc { ~riotCollage.pick.(\snare) ?? { ~riotCollage.pick.(\perc) } },
            \startPos, 0,
            \rate, Pwhite(0.9, 1.05),
            \amp, 1.1,
            \pan, Pwhite(-0.35, 0.35),
            \crush, 4,
            \grit, 2.3,
            \dur, Pseq([0.5, 0.5, 0.5, 0.5], inf),
            \stretch, 2,
            \lag, Pseq([0, ~riotCollage.config.swing * 0.25, 0, ~riotCollage.config.swing * 0.25], inf)
        );
        var hats = Pbind(
            \instrument, \riot_player,
            \bufnum, Pfunc { ~riotCollage.pick.(\perc) ?? { ~riotCollage.pick.(\any) } },
            \startPos, Pwhite(0.0, 0.2),
            \rate, Pwhite(0.9, 1.6),
            \amp, Pwhite(0.2, 0.5),
            \pan, Pwhite(-0.7, 0.7),
            \tone, 12000,
            \crush, 8,
            \dur, 0.25
        );
        Pdef(\riot_nyc, Ppar([kick, snare, hats])).play(~riotCollage.clock);
        "NYC beat mode: distortion-forward".postln;
    };

    ~riotCollage.voiceCuts = {
        var voxBuf = { ~riotCollage.pick.(\voice) ?? { ~riotCollage.pick.(\any) } };
        Pdef(\riot_voice,
            Pbind(
                \instrument, \riot_grain,
                \bufnum, Pfunc { voxBuf.value },
                \dur, Pwhite(0.15, 0.35),
                \dens, Pwhite(6, 22),
                \rate, Pwhite(0.6, 1.5) * Pwrand([1, -1], [0.8, 0.2], inf),
                \warp, Pwhite(0.1, 0.5),
                \pan, Pwhite(-0.7, 0.7),
                \tilt, Pwhite(-1.0, 1.0),
                \hp, Pwhite(120, 400),
                \lp, Pwhite(4000, 12000),
                \amp, Pexprand(0.2, 0.9)
            )
        ).play(~riotCollage.clock);
        "Voice cut-up stream running".postln;
    };

    ~riotCollage.concatStream = { |tag=\any, targetTilt=0|
        var pickBuf = { ~riotCollage.pick.(tag) ?? { ~riotCollage.pick.(\any) } };
        Pdef(\riot_concat,
            Pbind(
                \instrument, \riot_concat,
                \bufnum, Pfunc { pickBuf.value },
                \slicePos, Pfunc { |ev| ~riotCollage.slicePos.(ev[\bufnum]) },
                \grainDur, Pwhite(0.05, 0.18),
                \tilt, targetTilt + Pwhite(-0.3, 0.3),
                \amp, Pexprand(0.25, 0.9),
                \dur, Pwhite(0.1, 0.25)
            )
        ).play(~riotCollage.clock);
        "Concatenative grain ribbon patched".postln;
    };

    ~riotCollage.demoScene = {
        ~riotCollage.submerge.();
        ~riotCollage.concreteLooper.();
        ~riotCollage.nycBeats.();
        ~riotCollage.voiceCuts.();
        ~riotCollage.concatStream.(\any, targetTilt: 0.25);
        "Demo scene armed: submerge + concrete + NYC + voice + concat".postln;
    };

    // --- Master bus dirt -------------------------------------------------
    ~riotCollage.submerge = {
        ~riotCollage.submergeBus ?? { ~riotCollage.submergeBus = Bus.audio(s, 2) };
        ~riotCollage.submergeSynth.tryPerform(\free);
        ~riotCollage.submergeSynth = Synth.tail(~riotCollage.fxGroup, \riot_submerge, [\inbus, 0, \out, ~riotCollage.config.defaultOut]);
        "Dirty mix bus armed".postln;
    };

    ~riotCollage.freeAll = {
        Pdef(\riot_concrete).stop;
        Pdef(\riot_nyc).stop;
        Pdef(\riot_voice).stop;
        Pdef(\riot_concat).stop;
        ~riotCollage.submergeSynth.tryPerform(\free);
        ~riotCollage.buffers.do({ |buf| buf.tryPerform(\free) });
        ~riotCollage.buffers.clear;
        ~riotCollage.tags = IdentityDictionary.new;
        ~riotCollage.slices = IdentityDictionary.new;
        ~riotCollage.meta = IdentityDictionary.new;
        ~riotCollage = nil;
    };

    "Riot Collage ready. Call ~riotCollage.loadFolder.() then ~riotCollage.status.()".postln;
};
)
