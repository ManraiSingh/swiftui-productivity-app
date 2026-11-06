import AVFoundation
import Observation

/// One mood of music. Everything is synthesized in the app, so there's no recording to license.
struct LofiTrack {
    let name: String
    let bpm: Double
    let chords: [[Int]]   // MIDI notes
    let scale: [Int]      // MIDI notes for the little melody
    let rain: Double
    let drums: Double

    static let all: [LofiTrack] = [
        LofiTrack(
            name: "Rainy desk", bpm: 70,
            chords: [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]],
            scale: [60, 62, 64, 67, 69, 72], rain: 0.9, drums: 0.8
        ),
        LofiTrack(
            name: "Warm café", bpm: 78,
            chords: [[48, 52, 55, 59], [45, 48, 52, 55], [50, 53, 57, 60], [43, 47, 50, 53]],
            scale: [60, 62, 64, 67, 69, 72], rain: 0, drums: 1
        ),
        LofiTrack(
            name: "Night owl", bpm: 64,
            chords: [[45, 48, 52, 55, 59], [41, 45, 48, 52], [48, 52, 55, 59], [40, 43, 47, 50]],
            scale: [57, 60, 62, 64, 67, 69], rain: 0.4, drums: 0.6
        )
    ]
}

/// Precomputed frequencies, swapped in as one object so the audio thread never sees a half-changed track.
final class LofiTrackData {
    let bpm: Double
    let chords: [[Double]]
    let bass: [Double]
    let scale: [Double]
    let rain: Double
    let drums: Double

    init(_ track: LofiTrack) {
        func freq(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
        bpm = track.bpm
        // Voice chords in a warm middle register so nothing gets muddy.
        chords = track.chords.map { chord in chord.map { freq($0 < 50 ? $0 + 12 : $0) } }
        bass = track.chords.map { chord in freq((chord.min() ?? 48) % 12 + 36) }
        scale = track.scale.map(freq)
        rain = track.rain
        drums = track.drums
    }
}

/// A tiny Schroeder reverb: four combs into two all-passes.
final class LofiReverb {
    private var combs: [UnsafeMutablePointer<Float>] = []
    private var combLengths: [Int] = []
    private var combIndex: [Int] = []
    private var combStore: [Float] = []
    private var passes: [UnsafeMutablePointer<Float>] = []
    private var passLengths: [Int] = []
    private var passIndex: [Int] = []

    init(sampleRate: Double) {
        let scale = sampleRate / 44_100
        for base in [1557, 1617, 1491, 1422] {
            let length = max(1, Int(Double(base) * scale))
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: length)
            buffer.initialize(repeating: 0, count: length)
            combs.append(buffer); combLengths.append(length); combIndex.append(0); combStore.append(0)
        }
        for base in [225, 556] {
            let length = max(1, Int(Double(base) * scale))
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: length)
            buffer.initialize(repeating: 0, count: length)
            passes.append(buffer); passLengths.append(length); passIndex.append(0)
        }
    }

    deinit {
        for (b, n) in zip(combs, combLengths) { b.deallocate(); _ = n }
        for b in passes { b.deallocate() }
    }

    func process(_ input: Float) -> Float {
        var sum: Float = 0
        for i in 0..<combs.count {
            let out = combs[i][combIndex[i]]
            combStore[i] = out * 0.6 + combStore[i] * 0.4
            combs[i][combIndex[i]] = input + combStore[i] * 0.8
            combIndex[i] = (combIndex[i] + 1) % combLengths[i]
            sum += out
        }
        var y = sum * 0.25
        for i in 0..<passes.count {
            let buffered = passes[i][passIndex[i]]
            let out = -y + buffered
            passes[i][passIndex[i]] = y + buffered * 0.5
            passIndex[i] = (passIndex[i] + 1) % passLengths[i]
            y = out
        }
        return y
    }
}

/// The synth itself. `render` runs on the audio thread, so it only does arithmetic.
final class LofiRenderer {
    let sampleRate: Double
    var data: LofiTrackData
    var targetGain: Float = 0
    private var gain: Float = 0
    private var n: Int64 = 0
    private var lowpass: Double = 0
    private var rain1: Double = 0
    private var rain2: Double = 0
    private var brush: Double = 0
    private var crackle: Double = 0
    private var seed: UInt32 = 0x1234_5678
    private let reverb: LofiReverb

    init(track: LofiTrack, sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        data = LofiTrackData(track)
        reverb = LofiReverb(sampleRate: sampleRate)
    }

    private func noise() -> Double {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Double(Int32(bitPattern: seed)) / Double(Int32.max)
    }

    private func hash(_ k: Int) -> Int {
        var x = UInt32(truncatingIfNeeded: k &+ 7919) &* 2_654_435_761
        x ^= x >> 15
        return Int(x % 1000)
    }

    /// A warm electric-piano note (two-operator FM) `lt` seconds after it was struck.
    private func piano(_ f: Double, _ lt: Double, bright: Double) -> Double {
        guard lt >= 0, lt < 4 else { return 0 }
        let twoPi = 2 * Double.pi
        let index = bright * exp(-lt * 3.5) + 0.15
        let mod = sin(twoPi * f * lt) * index
        let attack = min(1, lt * 200)
        return sin(twoPi * f * lt + mod) * exp(-lt * 1.7) * attack
    }

    func render(_ count: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        let d = data
        let twoPi = 2 * Double.pi
        let beatLen = 60 / d.bpm
        for i in 0..<count {
            let tau = Double(n) / sampleRate
            n += 1
            let beat = tau / beatLen
            let bar = Int(beat / 4)
            let pos = beat - Double(bar * 4)
            let ci = bar % d.chords.count
            let pi = (bar + d.chords.count - 1) % d.chords.count
            let chord = d.chords[ci]
            let prevChord = d.chords[pi]
            let wobble = 1 + 0.003 * sin(twoPi * 0.25 * tau) + 0.0008 * sin(twoPi * 5.5 * tau)

            // Kick timing drives a gentle "pump" on everything else.
            var sinceKick = 10.0
            for hit in [0.0, 2.5] where pos >= hit { sinceKick = min(sinceKick, (pos - hit) * beatLen) }
            if pos < 0.5 { sinceKick = min(sinceKick, (pos + 1.5) * beatLen) }
            let pump = 1 - 0.3 * exp(-sinceKick * 7)

            var music = 0.0

            // Electric-piano chords: struck on 1 and the "and" of 3, lightly strummed.
            for (barOffset, hits) in [(0.0, [0.0, 2.5]), (4.0, [2.5])] {
                let notes = barOffset == 0 ? chord : prevChord
                for hit in hits {
                    let base = (pos + barOffset - hit) * beatLen
                    let soft = hit == 0 ? 1.0 : 0.7
                    for (k, f) in notes.enumerated() {
                        music += 0.065 * soft * piano(f * wobble, base - Double(k) * 0.018, bright: 1.2)
                    }
                }
            }

            // A few soft melody notes on top, now and then.
            let eighth = Int(pos * 2)
            for back in 0..<3 {
                let step = eighth - back
                let key = bar * 8 + step
                let h = hash(key)
                if bar % 8 >= 2 && h % 9 < 2 {
                    let f = d.scale[h % d.scale.count]
                    let lt = (pos * 2 - Double(step)) * beatLen / 2
                    music += 0.05 * piano(f * wobble, lt, bright: 0.8)
                }
            }

            // Short, soft bass pluck on the root (no long hum).
            let root = d.bass[ci]
            for hit in [0.0, 2.0] where pos >= hit {
                let lt = (pos - hit) * beatLen
                if lt < 0.6 {
                    let env = exp(-lt * 7) * min(1, lt * 120)
                    music += 0.13 * env * (sin(twoPi * root * tau) + 0.3 * sin(twoPi * root * 2 * tau))
                }
            }

            var s = music * pump

            if d.drums > 0 {
                // Soft kick.
                if sinceKick < 0.35 {
                    let lt = sinceKick
                    let phase = twoPi * (48 * lt + 60 * (1 - exp(-lt * 30)) / 30)
                    s += d.drums * 0.28 * sin(phase) * exp(-lt * 9)
                }
                // Brushed snare: a soft body plus heavily filtered noise.
                brush += 0.08 * (noise() - brush)
                for hit in [1.0, 3.0] where pos >= hit {
                    let lt = (pos - hit) * beatLen
                    if lt < 0.35 {
                        s += d.drums * (0.05 * sin(twoPi * 185 * lt) * exp(-lt * 25) + 0.12 * brush * exp(-lt * 10))
                    }
                }
            }

            // Rain as a low, gentle wash, and the occasional soft crackle.
            rain1 += 0.025 * (noise() - rain1)
            rain2 += 0.025 * (rain1 - rain2)
            s += d.rain * 0.55 * rain2
            if noise() > 0.99992 { crackle = 0.03 * noise() }
            crackle *= 0.9
            s += crackle

            lowpass += 0.22 * (s - lowpass)
            let wet = Double(reverb.process(Float(lowpass)))
            let mixed = lowpass * 0.82 + wet * 0.35
            gain += (targetGain - gain) * 0.0004
            let out = Float(tanh(mixed * 1.8)) * gain
            left[i] = out
            right?[i] = out
        }
    }
}

/// Plays the generated music. Starts gently, fades out when paused.
@Observable
final class LofiPlayer {
    private(set) var isPlaying = false
    private(set) var index = 0
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var renderer: LofiRenderer?

    var trackName: String { LofiTrack.all[index].name }

    func play() {
        if engine == nil { setUp() }
        if let engine, !engine.isRunning { try? engine.start() }
        renderer?.targetGain = 0.7
        isPlaying = true
    }

    func pause() {
        renderer?.targetGain = 0
        isPlaying = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.engine?.pause()
        }
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func next() {
        index = (index + 1) % LofiTrack.all.count
        renderer?.data = LofiTrackData(LofiTrack.all[index])
    }

    func stop() {
        engine?.stop()
        engine = nil
        renderer = nil
        isPlaying = false
    }

    private func setUp() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        let engine = AVAudioEngine()
        var rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate <= 0 { rate = 44_100 }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let renderer = LofiRenderer(track: LofiTrack.all[index], sampleRate: rate)

        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let left = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            renderer.render(Int(frameCount), left: left, right: right)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
        } catch {
            return
        }
        self.engine = engine
        self.renderer = renderer
    }
}
