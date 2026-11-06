import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MossbrookWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
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

// MARK: - Live Activity

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            let st = context.state
            let range = st.start...max(st.end, st.start.addingTimeInterval(1))
            HStack(spacing: 12) {
                PixelScene(kind: .desk(Color(hex: st.drinkHex), st.onBreak))
                    .frame(width: 66, height: 66)
                    .framed()
                VStack(alignment: .leading, spacing: 4) {
                    Text(label(st))
                        .font(.pixel(10, .heavy))
                        .foregroundStyle(st.onBreak ? Color(hex: 0x9CD3A0) : WP.gold)
                    Text(st.onBreak ? "Wander, sip, say hi" : st.title)
                        .font(.pixel(14, .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(st.onBreak ? Color(hex: 0x9CD3A0) : WP.gold)
                }
                Text(timerInterval: range, countsDown: true)
                    .font(.pixel(24, .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .frame(width: 84, alignment: .trailing)
            }
            .padding(14)
            .activityBackgroundTint(WP.night)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let st = context.state
            let range = st.start...max(st.end, st.start.addingTimeInterval(1))
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PixelScene(kind: .desk(Color(hex: st.drinkHex), st.onBreak))
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
                        Text(label(st)).font(.pixel(9, .heavy)).foregroundStyle(WP.gold)
                        Text(st.onBreak ? "Wander, sip, say hi" : st.title).font(.pixel(13, .heavy)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(st.onBreak ? Color(hex: 0x9CD3A0) : WP.gold)
                }
            } compactLeading: {
                Image(systemName: st.onBreak ? "cup.and.saucer.fill" : "laptopcomputer")
                    .foregroundStyle(WP.gold)
            } compactTrailing: {
                Text(timerInterval: range, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 46)
            } minimal: {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(WP.gold)
            }
        }
    }

    private func label(_ st: FocusActivityAttributes.ContentState) -> String {
        let r = st.rounds > 1 ? " · ROUND \(st.round)/\(st.rounds)" : ""
        return (st.onBreak ? "BREAK" : "FOCUSING") + r
    }
}
