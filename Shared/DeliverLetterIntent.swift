import AppIntents
import WidgetKit

/// Ticking a letter on the widget. The widget updates right away; the app hands the
/// letter to Pip (bike parts, habit watering and all) the next time it opens.
struct DeliverLetterIntent: AppIntent {
    static var title: LocalizedStringResource = "Deliver letter"
    static var isDiscoverable = false

    @Parameter(title: "Letter")
    var letterID: String

    init() {}
    init(letterID: String) { self.letterID = letterID }

    func perform() async throws -> some IntentResult {
        WidgetSnapshot.markDelivered(letterID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
