import AVFoundation
import UIKit

/// Plays the chime when a work block or break ends.
enum FocusAlarm {
    private static var player: AVAudioPlayer?

    static func play() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "wav") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.9
        player?.play()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
