import SwiftUI

enum Theme {
    static let ink = Color(hex: 0x2B2233)
    static let cream = Color(hex: 0xFFF6E5)
    static let paper = Color(hex: 0xF6EBD3)
    static let card = Color(hex: 0xFFFDF6)
    static let muted = Color(hex: 0x6B5F73)
    static let pipBlue = Color(hex: 0x4A6FA5)
    static let moPlum = Color(hex: 0x8E5A8A)
    static let beaOrange = Color(hex: 0xB8612F)
    static let leaf = Color(hex: 0x6E8B5E)
    static let red = Color(hex: 0xC65F4A)
    static let gold = Color(hex: 0xF2C14E)
    static let empty = Color(hex: 0xE6D9BD)
}

extension Font {
    static func pixel(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A chunky bordered box with a hard drop shadow, like an old game menu.
struct PixelBox: ViewModifier {
    var fill: Color = Theme.cream
    var shadow: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .background(fill, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink).offset(x: shadow, y: shadow))
    }
}

extension View {
    func pixelBox(_ fill: Color = Theme.cream, shadow: CGFloat = 3) -> some View {
        modifier(PixelBox(fill: fill, shadow: shadow))
    }
}

struct PixelButtonStyle: ButtonStyle {
    /// Set by the app to play a little sound when any pixel button is pressed.
    nonisolated(unsafe) static var onPress: (() -> Void)?
    var fill: Color = Theme.gold
    var foreground: Color = Theme.ink
    var hPad: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        PixelButtonBody(configuration: configuration, fill: fill, foreground: foreground, hPad: hPad)
    }
}

/// Split out so it can read `isEnabled`: a disabled button goes flat and faded, so it never looks tappable.
private struct PixelButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let foreground: Color
    let hPad: CGFloat

    var body: some View {
        let pressed = configuration.isPressed || !isEnabled
        configuration.label
            .font(.pixel(15))
            .foregroundStyle(foreground)
            .padding(.horizontal, hPad)
            .frame(minHeight: 44)
            .background(fill, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
            .background(Rectangle().fill(Theme.ink).offset(x: pressed ? 1 : 3, y: pressed ? 1 : 3))
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .saturation(isEnabled ? 1 : 0.3)
            .onChange(of: configuration.isPressed) { _, down in if down { PixelButtonStyle.onPress?() } }
    }
}

struct PixelProgress: View {
    let value: Int
    let total: Int
    var color: Color = Theme.pipBlue
    var cellHeight: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Rectangle()
                    .fill(i < value ? color : Theme.empty)
                    .frame(height: cellHeight)
                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(value) of \(total)")
    }
}

struct SpeechBubble: View {
    let text: String
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.pixel(size, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.card)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
            .overlay(alignment: .bottom) { BubbleTail().offset(y: BubbleTail.u * 3) }
    }
}

/// A little stepped pixel tail. Its first row sits on the bubble's border and opens it up.
struct BubbleTail: View {
    static let u: CGFloat = 1.5
    private static let rows = ["XooooooX", ".XooooX.", "..XooX..", "...XX..."]

    var body: some View {
        Canvas { ctx, _ in
            let u = Self.u
            for (y, row) in Self.rows.enumerated() {
                for (x, c) in row.enumerated() where c != "." {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * u, y: CGFloat(y) * u, width: u + 0.3, height: u + 0.3)),
                             with: .color(c == "X" ? Theme.ink : Theme.card))
                }
            }
        }
        .frame(width: Self.u * 8, height: Self.u * 4)
        .allowsHitTesting(false)
    }
}

enum DueFormat {
    static func text(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if date < Date() { return "late · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" }
        if cal.isDateInToday(date) { return "today · \(time)" }
        if cal.isDateInTomorrow(date) { return "tomorrow · \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}


/// "1 minute", "5 minutes".
func count(_ n: Int, _ word: String, plural: String? = nil) -> String {
    "\(n) \(n == 1 ? word : (plural ?? word + "s"))"
}
