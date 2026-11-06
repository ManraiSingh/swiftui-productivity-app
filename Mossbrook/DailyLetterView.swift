import SwiftUI

/// Pip's morning letter: a kind note and one tiny quest for the day.
struct DailyLetterView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    static let notes = [
        "Small steps still count as walking.",
        "The kettle never rushes, and the tea is still lovely.",
        "Do one thing today that future-you will thank you for.",
        "Rainy days are made for cozy, focused work.",
        "You don't need a perfect plan, just a first page.",
        "Even the clock tower started with one tick.",
        "Rest is part of the work, not a break from it.",
        "Finish the small thing. It makes room for the big thing.",
        "Be gentle with yourself. The village is proud of you.",
        "A tidy list makes for a quiet mind.",
        "Stars don't hurry, and they still shine.",
        "Whatever you finish today, the ducks will be impressed."
    ]

    static let quests = [
        "Deliver one letter before lunch.",
        "Write one page, even a tiny one.",
        "Sit for one cup at Bea's café.",
        "Finish one small thing you've been avoiding.",
        "Write down three things you're grateful for.",
        "Try one session in strict mode.",
        "Tidy up your letters: deliver or remove one."
    ]

    private var dayIndex: Int {
        Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 12) {
                    BobbingSprite(sprite: Sprites.pip, pixel: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A LETTER FOR YOU")
                            .font(.pixel(11))
                            .foregroundStyle(Theme.muted)
                        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.pixel(16, .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                }

                Text("\u{201C}\(Self.notes[dayIndex % Self.notes.count])\u{201D}")
                    .font(.pixel(18, .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Theme.ink.opacity(0.15)).frame(height: 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("TODAY'S TINY QUEST")
                        .font(.pixel(11))
                        .foregroundStyle(Theme.pipBlue)
                    Text(Self.quests[dayIndex % Self.quests.count])
                        .font(.pixel(15, .heavy))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Theme.red)
                    Text(store.streak == 0
                         ? "Do one thing today to start your streak. Juniper's garden is waiting."
                         : "\(store.streak)-day streak. \(min(store.streak, 15)) \(min(store.streak, 15) == 1 ? "flower" : "flowers") in the garden.")
                        .font(.pixel(12, .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("— Pip")
                    .font(.pixel(14, .heavy))
                    .foregroundStyle(Theme.pipBlue)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .pixelBox(Color(hex: 0xFFFBEF))

            Button {
                dismiss()
            } label: {
                Text("Thanks, Pip").frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(fill: Theme.pipBlue, foreground: Theme.cream))
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { store.openDailyLetter() }
    }
}
