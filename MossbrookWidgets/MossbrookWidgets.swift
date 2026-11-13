import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MossbrookWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TogetherWidget()
        FocusLiveActivity()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MossbrookWidget", provider: MossProvider()) { entry in
            TodayView(entry: entry)
        }
        .configurationDisplayName("Workdoro")
        .description("Your letters, your café time and your habit streaks. You at your desk while you focus.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// The Together House: when the next shared focus session starts, and the countdown while it runs.
struct TogetherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TogetherWidget", provider: TogetherProvider()) { entry in
            TogetherWidgetView(entry: entry)
        }
        .configurationDisplayName("Together House")
        .description("Focus with real people. A shared session starts every :00 and :30.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Live Activity

struct FocusLiveActivity: Widget {
    private static let pink = Color(hex: 0xF7B7CF)
    private static let plum = Color(hex: 0x3A2440)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            let st = context.state
            let range = st.start...max(st.end, st.start.addingTimeInterval(1))
            let together = st.together == true
            HStack(spacing: 12) {
                scene(st)
                    .frame(width: 66, height: 66)
                    .framed()
                VStack(alignment: .leading, spacing: 4) {
                    Text(label(st))
                        .font(.pixel(10, .heavy))
                        .foregroundStyle(tint(st))
                    Text(subtitle(st))
                        .font(.pixel(14, .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(tint(st))
                }
                Text(timerInterval: range, countsDown: true)
                    .font(.pixel(24, .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(width: 84, alignment: .trailing)
            }
            .padding(14)
            .activityBackgroundTint(together ? Self.plum : WP.night)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let st = context.state
            let range = st.start...max(st.end, st.start.addingTimeInterval(1))
            let together = st.together == true
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    scene(st)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.pixel(22, .heavy))
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(st)).font(.pixel(9, .heavy)).foregroundStyle(tint(st))
                        Text(subtitle(st)).font(.pixel(13, .heavy)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(tint(st))
                }
            } compactLeading: {
                if together {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill").foregroundStyle(Self.pink)
                        if let n = st.people, n > 1 { Text("\(n)").font(.pixel(12, .heavy)).foregroundStyle(Self.pink) }
                    }
                } else {
                    Image(systemName: st.onBreak ? "cup.and.saucer.fill" : "laptopcomputer")
                        .foregroundStyle(WP.gold)
                }
            } compactTrailing: {
                Text(timerInterval: range, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 46)
                    .foregroundStyle(together ? Self.pink : .white)
            } minimal: {
                Image(systemName: together ? "person.2.fill" : "cup.and.saucer.fill")
                    .foregroundStyle(together ? Self.pink : WP.gold)
            }
        }
    }

    @ViewBuilder private func scene(_ st: FocusActivityAttributes.ContentState) -> some View {
        if st.together == true {
            TogetherScene(running: !st.onBreak, progress: 0.5, grid: 48)
        } else {
            PixelScene(kind: .desk(Color(hex: st.drinkHex), st.onBreak))
        }
    }

    private func tint(_ st: FocusActivityAttributes.ContentState) -> Color {
        if st.together == true { return Self.pink }
        return st.onBreak ? Color(hex: 0x9CD3A0) : WP.gold
    }

    private func subtitle(_ st: FocusActivityAttributes.ContentState) -> String {
        if st.together == true {
            let others = max(0, (st.people ?? 1) - 1)
            return others > 0 ? "with \(others) \(others == 1 ? "other" : "others") in the house" : "Holding the room"
        }
        return st.onBreak ? "Wander, sip, say hi" : st.title
    }

    private func label(_ st: FocusActivityAttributes.ContentState) -> String {
        if st.together == true { return "FOCUSING TOGETHER" }
        let r = st.rounds > 1 ? " · ROUND \(st.round)/\(st.rounds)" : ""
        return (st.onBreak ? "BREAK" : "FOCUSING") + r
    }
}
