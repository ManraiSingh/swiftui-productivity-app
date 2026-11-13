import ActivityKit
import Foundation

/// The Live Activity shown on the lock screen and in the Dynamic Island while you focus.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var start: Date
        var end: Date
        var onBreak: Bool
        var round: Int
        var rounds: Int
        var drinkHex: UInt32
        /// In a Together House session, and how many people are focusing in it.
        var together: Bool? = nil
        var people: Int? = nil
    }

    var name: String
}
