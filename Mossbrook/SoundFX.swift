import AVFoundation
import SwiftUI
import UIKit

/// Little cozy sounds for taps, made in code (no audio files): soft wooden taps, bubbly pops,
/// music-box chimes, a quacking duck and Pip's bicycle bell.
///
/// Sounds respect the silent switch and mix with whatever else is playing. They can be turned
/// off in Settings.
final class SoundFX {
    static let shared = SoundFX()
    static let enabledKey = "tapSounds"

    enum Sound: CaseIterable {
        case tap, pop, open, close, quack, apple, star, bikeBell, deliver, water, sparkle, page, blip, toggle, message
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    /// Taps play a little pentatonic tune, one soft note per tap, so tapping around sounds musical.
    private var tapNotes: [AVAudioPCMBuffer] = []
    private var tapIndex = 0
    private var blips: [AVAudioPCMBuffer] = []
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false
    /// When a named sound last played, so the gentle all-purpose tap doesn't double up on it.
    private(set) var lastPlayed = Date.distantPast

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private init() {}

    /// Builds the sounds and starts the engine. Called once at launch.
    func prepare() {
        guard !started else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category == .soloAmbient {
            try? session.setCategory(.ambient, options: [.mixWithOthers])
        }
        for sound in Sound.allCases { buffers[sound] = make(render(sound)) }
        tapNotes = [1047.0, 1175, 1319, 1568, 1760, 1568, 1319, 1175].map { make(softNote($0)) }
        // One little "voice" for each villager, at a different pitch.
        blips = [659.0, 523.0, 784.0, 587.0, 880.0, 440.0].map { make(voice($0)) }
        for _ in 0..<6 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        engine.mainMixerNode.outputVolume = 0.55
        do {
            try engine.start()
            players.forEach { $0.play() }
            started = true
        } catch {
            started = false
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
        }
    }

    private func restart() {
        guard started, !engine.isRunning else { return }
        try? engine.start()
        players.forEach { $0.play() }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        guard let buffer = buffers[sound] else { return }
        schedule(buffer, volume: volume)
    }

    /// The next note of the tap tune, played softly.
    func playTap(volume: Float = 0.3) {
        guard !tapNotes.isEmpty else { return play(.tap, volume: volume) }
        schedule(tapNotes[tapIndex % tapNotes.count], volume: volume)
        tapIndex += 1
    }

    /// A tiny chirpy voice, pitched per villager.
    func voice(of villager: VillagerID) {
        guard !blips.isEmpty else { return }
        let i = (VillagerID.allCases.firstIndex(of: villager) ?? 0) % blips.count
        schedule(blips[i], volume: 0.9)
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, volume: Float) {
        guard enabled, started else { return }
        restart()
        lastPlayed = .now
        let node = players[next]
        next = (next + 1) % players.count
        node.volume = volume
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
    }

    // MARK: Making the sounds

    private let sr = 44_100.0

    private func make(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let peak = max(samples.map(abs).max() ?? 1, 0.0001)
        for (i, s) in samples.enumerated() { buffer.floatChannelData![0][i] = s / peak * 0.8 }
        return buffer
    }

    private func silence(_ seconds: Double) -> [Float] { Array(repeating: 0, count: Int(seconds * sr)) }

    /// A soft bell: a sine with a gentle inharmonic shimmer, fading out.
    private func bell(_ freq: Double, _ dur: Double, decay: Double = 7) -> [Float] {
        (0..<Int(dur * sr)).map { i in
            let t = Double(i) / sr
            let attack = min(1, t / 0.003)
            let s = sin(2 * .pi * freq * t) + 0.3 * sin(2 * .pi * freq * 2.76 * t) * exp(-t * 12)
            return Float(s * attack * exp(-t * decay))
        }
    }

    private func mix(_ parts: [(Double, [Float])]) -> [Float] {
        let length = parts.map { Int($0.0 * sr) + $0.1.count }.max() ?? 0
        var out = [Float](repeating: 0, count: length)
        for (start, part) in parts {
            let o = Int(start * sr)
            for (i, s) in part.enumerated() { out[o + i] += s }
        }
        return out
    }

    private func sweep(_ from: Double, _ to: Double, _ dur: Double, decay: Double, wave: (Double) -> Double = { sin($0) }) -> [Float] {
        var phase = 0.0
        return (0..<Int(dur * sr)).map { i in
            let t = Double(i) / sr, k = t / dur
            let f = from * pow(to / from, k)
            phase += 2 * .pi * f / sr
            return Float(wave(phase) * min(1, t / 0.003) * exp(-t * decay))
        }
    }

    /// A soft, round little note: a pure tone with a gentle fade-in so it never clicks,
    /// a touch of an octave above for sparkle, and a quick, airy fade.
    private func softNote(_ freq: Double) -> [Float] {
        (0..<Int(0.22 * sr)).map { i in
            let t = Double(i) / sr
            let attack = min(1, t / 0.006)
            let s = sin(2 * .pi * freq * t) + 0.12 * sin(2 * .pi * freq * 2 * t) * exp(-t * 30)
            return Float(s * attack * exp(-t * 16))
        }
    }

    private func voice(_ freq: Double) -> [Float] {
        // Two quick syllables, like a tiny "mm-hm!".
        mix([(0, sweep(freq * 0.9, freq * 1.15, 0.07, decay: 18, wave: { sin($0) + 0.35 * sin(2 * $0) })),
             (0.075, sweep(freq * 1.1, freq * 1.3, 0.09, decay: 16, wave: { sin($0) + 0.35 * sin(2 * $0) }))])
    }

    private func render(_ sound: Sound) -> [Float] {
        switch sound {
        case .tap:
            // A tiny music-box note: pure, round and quick to fade (see `tapNotes` for the melody).
            return softNote(1319)
        case .pop:
            return sweep(420, 1300, 0.09, decay: 34)
        case .open:
            return mix([(0, bell(1047, 0.35, decay: 10)), (0.07, bell(1568, 0.45, decay: 9))])
        case .close:
            return mix([(0, bell(1568, 0.3, decay: 11)), (0.07, bell(1047, 0.4, decay: 10))])
        case .quack:
            let q = sweep(560, 330, 0.16, decay: 9, wave: { $0.truncatingRemainder(dividingBy: 2 * .pi) < .pi * 0.7 ? 0.8 : -0.5 })
            return mix([(0, q), (0.2, sweep(520, 310, 0.13, decay: 11, wave: { $0.truncatingRemainder(dividingBy: 2 * .pi) < .pi * 0.7 ? 0.8 : -0.5 }))])
        case .apple:
            let thunk = sweep(240, 90, 0.12, decay: 30)
            return mix([(0.22, thunk), (0, sweep(1200, 600, 0.2, decay: 14))])
        case .star:
            return mix([2093.0, 2637, 3136, 4186].enumerated().map { (Double($0.offset) * 0.06, bell($0.element, 0.6, decay: 8)) })
        case .bikeBell:
            // "Ring ring!": two bright two-tone dings.
            let ring = mix([(0, bell(2349, 0.5, decay: 6)), (0, bell(2960, 0.5, decay: 7))])
            return mix([(0, ring), (0.22, ring), (0.6, silence(0.01))])
        case .deliver:
            return mix([(0, bell(1319, 0.4)), (0.08, bell(1661, 0.4)), (0.16, bell(1976, 0.7, decay: 5))])
        case .water:
            return mix([(0, sweep(500, 1400, 0.08, decay: 30)), (0.1, sweep(600, 1600, 0.08, decay: 30)), (0.2, bell(1760, 0.4, decay: 9))])
        case .sparkle:
            return mix([3136.0, 3951, 4699].enumerated().map { (Double($0.offset) * 0.045, bell($0.element, 0.35, decay: 12)) })
        case .page:
            var rng = SystemRandomNumberGenerator()
            return (0..<Int(0.14 * sr)).map { i in
                let t = Double(i) / sr
                return Float(Double.random(in: -1...1, using: &rng) * sin(.pi * t / 0.14) * 0.35)
            }
        case .blip:
            return voice(700)
        case .toggle:
            return mix([(0, sweep(700, 900, 0.04, decay: 60)), (0.05, bell(1319, 0.25, decay: 14))])
        case .message:
            // A soft "new message" chime: a tiny bubbly pop, then two gentle music-box notes.
            let pop = sweep(560, 940, 0.05, decay: 46).map { $0 * 0.5 }
            let shimmer = bell(2637, 0.25, decay: 16).map { $0 * 0.18 }
            return mix([(0, pop), (0.04, bell(1568, 0.4, decay: 11)), (0.11, bell(2093, 0.55, decay: 8)), (0.11, shimmer)])
        }
    }
}

/// Plays the gentle all-purpose tap for any touch that didn't already make its own sound,
/// so the whole app feels tactile without every button needing code.
final class TapSoundRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(tapped))
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
    }

    @objc private func tapped() {
        let touchTime = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Something more specific played for this touch already.
            if SoundFX.shared.lastPlayed > touchTime.addingTimeInterval(-0.08) { return }
            SoundFX.shared.playTap()
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UITextView || touch.view is UITextField)
    }
}

extension SoundFX {
    /// Adds the tap listener to every window in the app.
    static func installTapListener() {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows where !(window.gestureRecognizers ?? []).contains(where: { $0 is TapSoundRecognizer }) {
                window.addGestureRecognizer(TapSoundRecognizer())
            }
        }
    }
}
