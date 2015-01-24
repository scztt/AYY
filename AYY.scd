(

State(\ayy).clear().push();
State(\ayy).autoEnvirWindow = true;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// INIT
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
State(\ayy).initActions.add({
	MIDIIn.connectAll;

	~lc.notNil.if({ ~lc.free });

	~buffer = Buffer.alloc(s, 44100, 2);
	~buffer.zero;
	~distBuffer = Buffer.alloc(s, 4092);
	~distBuffer.zero;
	~distBuffer.cheby([0, 2, 1.5], asWavetable:true);
	~distBuffer.plot;

	~resources.addAll([
		~lc = ~lc ?? { LCDevice() },
		~lc.knobs.do(_.ringStyle_(\fill)),
	]);

	DistCurve(\buzzD).size_(4092);
	DistCurve(\buzzD,
		Env([-1, 0, 1]),
		Env([-1, -0.8, -0.5, -0.2, 0.8, 0.9, 1], curve:'sin')
	);


	SynthDef(\buzz, {
		| amp=0, freq=310, lag=8, gate=1, filtMax=1, gain1=1.1, width=0.5 |
		var sig, distSig, sigPos, sigNeg, mod, env, filtEnv, feedIn;

		width		= LagUD.kr(width, 10, 8);
		filtMax 	= filtMax.linlin(0, 1, 2, 15);
		feedIn 		= DelayN.ar(LocalIn.ar(2), 0.7, 0.7);
		feedIn		= BLPF.ar(feedIn, 8, 9000);
		gain1 		= LagUD.kr(gain1, 0.2, 4);
		env 		= EnvGen.ar(Env.adsr(2, 0.5, 1, 25), gate, doneAction:2);
		filtEnv 	= EnvGen.ar(Env.adsr(0.5, 0.5, 1, 14), gate) * (filtMax * 1000) + 1000;

		mod 		= SinOsc.ar(124 / [9, 10, 11, 8, 12], Rand(0, 1));
		freq 		= Lag2.kr(freq, lag);

		sig 		= (LFPulse.ar(freq * [1, 1.01, 1.022, 0.995, 1.333], mod, 0.01 + (width * 0.5)).sum) + feedIn.neg;
		sig 		= MoogFF.ar(sig, filtEnv, 2);
		sig			= Splay.ar(sig);
		sig			= (0.0 * sig) + (30 * MoogLadder.ar(sig, 140, 1.4) * MoogFF.ar(sig, 160, 3));
		//sig			= SoftClipAmp4.ar(sig, 5, 1/5);
		//sig 		= DistCurve(\buzzD).ar(sig * (gain1.linlin(0, 1, 1, 4) * env), 0.5, gain1);
		sig			= Shaper.ar(~distBuffer.bufnum, LeakDC.ar(sig));

		// sigPos = (sig * 0.7).clip(0, 2);
		// sigNeg = (sig * 0.7).clip(-2, 0);
		// distSig = sig.sign * Mix([sigPos, sigNeg.abs].collect {
		// 	|x|
		// 	var ds;
		// 	x = (x.abs > 0.00001) * x;
		// 	ds = (64 * x.pow(7)) - (112 * x.pow(5)) + (56 * x.pow(3)) - (7 * x);
		// });
		// sig 		= sig + distSig;

		sig 		= MoogFF.ar(sig, filtEnv, 2);
		sig 		= sig;

		//LocalOut.ar((sig + SinOsc.ar(Rand(0.05, 0.07), Rand(0.0, 1.0), 0.2)) * env);

		sig = sig * [1, 1] * env * amp.dbamp;
		Out.ar(0, sig);
//		Out.ar(10, sig);
	}).addReplace;



	SynthDef( \highDelay, {
		| in, bufnum |
		var inSig, sig, delayed;
		inSig 		= LeakDC.ar(LocalIn.ar(2));
		inSig		= Balance2.ar(inSig[0], inSig[1], SinOsc.kr(0.07));
		inSig		= LPF.ar(Compander.ar(inSig, inSig, 0.2, 5, 1/60), 20000);
		inSig		= SoftClipAmp8.ar(inSig);
		inSig 		= inSig + LPF.ar(In.ar(in, 2), 10000);

		delayed 	= HPF.ar(inSig, 100);
		delayed 	= MultiTap.ar(
			`([0.11, 0.343, 0.425, 0.6342, 0.723].collect({ |i| i + LFTri.kr(Rand(0.14, 0.21), 1.0.rand, 0.03) })),
			#[0.8, 0.7, 0.5, 0.3, 0.1],
			in: LeakDC.ar(delayed),
			bufnum: bufnum
		);

		inSig 		= BLPF.ar(inSig, 2, 60) + BLPF.ar(inSig, 4, 60);
		LocalOut.ar(LeakDC.ar(delayed));

		inSig		= LeakDC.ar(inSig);
		inSig		= inSig /*+ (delayed * 0.001)*/;
		inSig 		= FreeVerb2.ar(inSig[0], inSig[1]);
		inSig		= inSig * 10;

		Out.ar(0, inSig);
	}).addReplace;

	SynthDef(\qctrl, {
		| bus, t_pres = 0, t_x = 0.0, t_y = 0.0 |
		var presC, xC, yC, last, mix;

		last = LocalIn.kr(3);

		t_pres = Latch.kr(t_pres, t_pres.abs) * Trig1.kr(t_pres.abs + t_x.abs + t_y.abs, 0.4);
		t_x = Latch.kr(t_x, t_x.abs).tanh / 2;
		t_y = Latch.kr(t_y, t_y.abs).tanh / 2;

		presC = t_pres;
		mix = presC.linlin(0, 1, 1, 0.5);
		xC = (last[1] * mix) + ((last[1] + (t_x * 0.01 * t_pres.pow(4))) * (1 - mix));
		xC = xC.max(-1).min(1);
		yC = (last[2] * mix) + ((last[2] + (t_y * 0.01 * t_pres.pow(4))) * (1 - mix));
		yC = yC.max(-1).min(1);

		LocalOut.kr([presC, xC, yC]);
		// xC = xC + RHPF.kr(xC, 1, 1);
		// yC = yC + RHPF.kr(yC, 1, 1);

		Out.kr(bus, [presC, xC, yC]);
	}).addReplace;


	~cbus = ~lc.knobCols.collect {
		|col, coli|
		col.collect {
			|knob, rowi|
			var bus = Bus.control(s, 1);
			~resources.add(bus);
			knob.connect.cv.action_({ |cv| bus.set(cv.value) });
		}
	};

	~freqs = 16.collect({ |i| Scale.partch_o2.degreeToFreq(i * 2, 40, 0) });
	~notes = nil ! 16;

	~resources.addAll(
		~qbus = 16.collect { Bus.control(s, 3) }
	);
	~resources.addAll(
		~qpads = ~qbus.collect { |bus| Synth(\qctrl, args: [bus: bus]) }
	);

	MIDIdef.noteOn(\qunon, {
		|...args|
		var pad = args[1] - 36, vel = args[0];
		"pad #% on (v:%)".format(pad, vel).postln;
		if (vel > 10) {
			if (~notes[pad].isNil) {
				~notes[pad] = Synth(\buzz, args: [
					\freq, ~freqs[pad],
					\width, Bus.newFrom(~qbus[pad], 0, 1).asMap.postln,
					\gain1, Bus.newFrom(~qbus[pad], 2, 1).asMap.postln,
				]);
			} {
				~notes[pad].set(\gate, 0);
				~notes[pad] = nil;
			}
		}
	}.inEnvir(currentEnvironment), (36..51), 0, MIDIIn.findPort("QUNEO", "QUNEO").uid);

	MIDIdef.cc(\qunpres, {
		|...args|
		var pad = args[1] - 23 / 3, pres = args[0];
		~qpads[pad].set(\t_pres, pres / 127.0);
	}.inEnvir(currentEnvironment), (23,26..68), 0, MIDIIn.findPort("QUNEO", "QUNEO").uid);

	MIDIdef.cc(\qunx, {
		|...args|
		var pad = args[1] - 23 / 3, x = args[0];
		~qpads[pad].set(\t_x, (x - 64.0 / 64.0));
	}.inEnvir(currentEnvironment), (24,27..69), 0, MIDIIn.findPort("QUNEO", "QUNEO").uid);

	MIDIdef.cc(\quny, {
		|...args|
		var pad = args[1] - 23 / 3, y = args[0];
		~qpads[pad].set(\t_y, (y - 64.0 / 64.0));
	}.inEnvir(currentEnvironment), (25,28..70), 0, MIDIIn.findPort("QUNEO", "QUNEO").uid);

});


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//FREE
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
State(\ayy).freeActions.add({
	~lc.free;
	~notes.collect(_.free);
	~notes.clear;
});

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// START
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
State(\ayy).startActions.add({
	~buffer.postln;
	~resources.addAll([
		~gr = Group(s),
		~eff = Group(~gr, \addAfter),
		~delay = Synth( \highDelay, [\in, 10, \bufnum, ~buffer.bufnum], target:e),
		~buf
	]);
});


///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// STOP
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

State(\ayy).stopActions.add({


});

)
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

State(\ayy).doInit();
State(\ayy).doStart();

State(\ayy).doStop();
State(\ayy).push

)
