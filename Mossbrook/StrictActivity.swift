import SwiftUI

/// What you're doing at the desk in strict mode. Each one fills up a little as your focus goes on.
enum StrictActivity: String, CaseIterable, Identifiable {
    case laptop, book

    var id: String { rawValue }

    var name: String {
        switch self {
        case .laptop: "Laptop"
        case .book: "Reading"
        }
    }

    /// For VoiceOver: "You, reading at your desk."
    var doing: String {
        switch self {
        case .laptop: "working on your laptop"
        case .book: "reading a book"
        }
    }

    var icon: Sprite {
        switch self {
        case .laptop: StrictIcons.laptop
        case .book: StrictIcons.book
        }
    }

    static let storageKey = "strictActivity"
}

/// Little pixel icons for the activity picker.
enum StrictIcons {
    private static let ink = VillageRenderer.ink

    static let laptop = Sprite([
        "..kkkkkkk..",
        "..kbbbbbk..",
        "..kbwbbbk..",
        "..kbbbbbk..",
        "..kkkkkkk..",
        ".kgggggggk.",
        "kkkkkkkkkkk"
    ], ["k": ink, "b": Color(hex: 0x9ED6EC), "w": Color(hex: 0xFFFFFF), "g": Color(hex: 0xB8BDC8)])

    static let book = Sprite([
        "kkkkk.kkkkk",
        "kwwwwkwwwwk",
        "kwkkwkwkkwk",
        "kwwwwkwwwwk",
        "kwkkwkwkkwk",
        "kwwwwkwwwwk",
        "kkkkkkkkkkk"
    ], ["k": ink, "w": Color(hex: 0xFFF6E5)])
}

extension StrictRenderer {
    private static let skin = Color(hex: 0xF6CFA8)
    private static let paper = Color(hex: 0xFFF6E5)

    static func hand(_ p: Painter, _ x: Int, _ y: Int) {
        p.rect(x, y, 5, 3, ink)
        p.rect(x + 1, y, 3, 2, skin)
    }

    /// The thing in your hands. `progress` runs from 0 to 1 over the session.
    static func activity(_ p: Painter, _ kind: StrictActivity, x0: Int, y0: Int, t: Double, progress: Double) {
        switch kind {
        case .laptop: laptop(p, x0: x0, y0: y0, t: t)
        case .book: book(p, x0: x0, t: t)
        }
    }

    private static func laptop(_ p: Painter, x0: Int, y0: Int, t: Double) {
        p.glow(Double(x0 + 24), Double(y0 + 22), radius: 18, Color(hex: 0xBFE6FF), 0.3)
        VillageRenderer.box(p, x0 + 8, 40, 32, 14, Color(hex: 0x9AA0AE))
        p.rect(x0 + 8, 40, 32, 1, Color(hex: 0xC4C9D2))
        p.rect(x0 + 8, 52, 32, 2, Color(hex: 0x7E8592))
        VillageRenderer.circle(p, cx: x0 + 24, cy: 46, r: 2, Color(hex: 0x78B86A))
        let typing = Int(t * 7) % 2 == 0
        hand(p, x0 + 3, 50 + (typing ? 0 : -1))
        hand(p, x0 + 40, 50 + (typing ? -1 : 0))
    }

    /// A hardback held up to read. Every few seconds a page turns over the top.
    private static func book(_ p: Painter, x0: Int, t: Double) {
        let by = 38
        let cover = Color(hex: 0x4A6FA5), coverDark = Color(hex: 0x37547F), gold = Color(hex: 0xF2C14E)
        p.glow(Double(x0 + 24), Double(by - 6), radius: 14, Color(hex: 0xFFE3A8), 0.22)
        VillageRenderer.box(p, x0 + 9, by, 30, 14, cover)
        p.rect(x0 + 23, by, 2, 14, coverDark)
        p.rect(x0 + 9, by - 2, 14, 1, ink)
        p.rect(x0 + 25, by - 2, 14, 1, ink)
        p.rect(x0 + 10, by - 1, 13, 1, paper)
        p.rect(x0 + 25, by - 1, 13, 1, paper)
        p.rect(x0 + 28, by + 4, 8, 2, gold)
        p.rect(x0 + 29, by + 7, 6, 1, gold)
        p.rect(x0 + 12, by + 4, 8, 1, Color(hex: 0x6C8FC4))
        // Turning a page now and then.
        let k = t.truncatingRemainder(dividingBy: 8) / 0.8
        if k < 1 {
            let px = x0 + 37 - Int(k * 26)
            let lift = Int(sin(k * .pi) * 3)
            p.rect(px - 1, by - 3 - lift, 5, 1, ink)
            p.rect(px, by - 2 - lift, 3, 1 + lift, paper)
        }
        hand(p, x0 + 5, by + 10)
        hand(p, x0 + 38, by + 10)
    }
}

/// A small pixel dropdown for what you're doing at the desk. It's drawn by hand (not a system
/// menu) because strict mode only turns its own picture sideways, and a system menu would pop up
/// the wrong way round. The list opens upwards, since it sits near the bottom of the screen.
struct ActivityPicker: View {
    @Binding var selection: String
    var compact = false
    @State private var open = false

    private var current: StrictActivity { StrictActivity(rawValue: selection) ?? .laptop }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(StrictActivity.allCases) { item in
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                selection = item.rawValue
                                open = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                SpriteView(sprite: item.icon, pixel: compact ? 1.6 : 2)
                                Text(item.name).font(.pixel(compact ? 11 : 13, .heavy))
                                Spacer(minLength: 8)
                                if item == current {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                                }
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .frame(height: compact ? 32 : 38)
                            .background(item == current ? Theme.gold.opacity(0.35) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(item == current ? .isSelected : [])
                    }
                }
                .fixedSize()
                .pixelBox(Theme.card, shadow: 2)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    SpriteView(sprite: current.icon, pixel: compact ? 1.6 : 2)
                    Text(current.name)
                        .font(.pixel(compact ? 11 : 13, .heavy))
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .font(.system(size: compact ? 9 : 11, weight: .heavy))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: compact ? 32 : 40)
                .pixelBox(Theme.card, shadow: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Working on: \(current.name)")
            .accessibilityHint("Choose what you're doing")
        }
    }
}

/// Shown the first time you open strict mode: what it does, and what you'd like to be doing.
struct StrictIntro: View {
    @Binding var selection: String
    let start: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        SpriteView(sprite: Sprites.deskYou, pixel: 2.5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("STRICT MODE")
                                .font(.pixel(10, .heavy))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.gold)
                            Text("Just you and the clock")
                                .font(.pixel(18, .heavy))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    row("iphone.landscape", "Your phone stays sideways and awake.")
                    row("bell.slash.fill", "Workdoro stays quiet. For total quiet, turn on Do Not Disturb too.")
                    row("hand.tap.fill", "To leave early, hold the red button.")
                }
                .frame(maxWidth: 270, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("WHAT ARE YOU WORKING ON?")
                        .font(.pixel(10, .heavy))
                        .foregroundStyle(Theme.muted)
                    ActivityPicker(selection: $selection)
                        .padding(.bottom, 6)
                    Button(action: start) {
                        Text("Start focusing").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(fill: Theme.beaOrange, foreground: Theme.cream))
                }
                .frame(width: 220)
            }
            .padding(20)
            .pixelBox(Theme.paper, shadow: 4)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.25)) { shown = true } }
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .pixelBox(Theme.card, shadow: 1)
            Text(text)
                .font(.pixel(12, .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
