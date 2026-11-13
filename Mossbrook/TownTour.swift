import SwiftUI

/// One stop on the guided walk: a villager (standing still at their place) introduces themself.
struct TourStop {
    let villager: VillagerID?
    let place: String
    let text: String

    /// Spotlight around the villager: origin is the centre, in town art pixels. Nil for the closing card.
    var rect: CGRect? {
        guard let v = villager, !isClosing else { return nil }
        let s = VillageLayout.tourSpot(v)
        return CGRect(x: s.x, y: s.y - 8, width: 28, height: 28)
    }
    var isClosing = false

    static let all: [TourStop] = [
        TourStop(villager: .pip, place: "Postman · Tasks",
                 text: "Hi! Give me your to-dos and I'll carry them as letters. Finish one and I find a piece of my bike!"),
        TourStop(villager: .mo, place: "Librarian · Notes",
                 text: "I keep your notes. Write, draw, add stickies and shapes. Every page fills my book."),
        TourStop(villager: .bea, place: "Café owner · Focus",
                 text: "Grab a drink and focus with me. On breaks you can wander around and chat!"),
        TourStop(villager: .juniper, place: "Gardener · Habits",
                 text: "Your habits grow into real plants. Water them daily to keep the streak alive."),
        TourStop(villager: .rosie, place: "Baker · Treats",
                 text: "Focus sessions earn you treats. Eat one on a break, or save three to rescue a streak."),
        TourStop(villager: .pip, place: "Welcome home",
                 text: "Tap + any time to add a letter or a note. Pop by the Old Oak for a town meeting with the mayor. Have fun!",
                 isClosing: true)
    ]
}

/// Dims the town and shines a pulsing circle on one villager, with their speech card and a
/// little pointer underneath. Tap anywhere or Next to move on; Skip ends the tour.
struct TownTourOverlay: View {
    let step: Int
    /// Where a town art rect sits on screen right now.
    let screenRect: (CGRect) -> CGRect
    let next: () -> Void
    let skip: () -> Void
    @State private var pulse = false
    /// False while the map is gliding to the next villager; the circle and card appear once it stops.
    @State private var settled = false

    private var stop: TourStop { TourStop.all[step] }
    private var isLast: Bool { step == TourStop.all.count - 1 }
    private let cardHeight: CGFloat = 162

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let hole = stop.rect.map { screenRect($0).offsetBy(dx: -origin.x, dy: -origin.y) }
            let cardW = min(geo.size.width - 32, 360)
            let cardX = (geo.size.width - cardW) / 2
            let below = hole.map { $0.maxY + 22 + cardHeight < geo.size.height - 140 } ?? true
            let cardTop: CGFloat = {
                guard let hole else { return geo.size.height * 0.45 - cardHeight / 2 }
                return below ? hole.maxY + 22 : hole.minY - 22 - cardHeight
            }()

            ZStack(alignment: .topLeading) {
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: geo.size))
                    if settled, let hole { p.addEllipse(in: hole.insetBy(dx: -6, dy: -6)) }
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))

                if settled, let hole {
                    Circle()
                        .stroke(Theme.gold, lineWidth: 3)
                        .frame(width: hole.width + 12, height: hole.height + 12)
                        .scaleEffect(pulse ? 1.12 : 1)
                        .opacity(pulse ? 0.4 : 1)
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)

                    // Pointer from the card to the villager.
                    Pointer(up: below)
                        .fill(Theme.card)
                        .overlay(Pointer(up: below).stroke(Theme.ink, lineWidth: 2))
                        .frame(width: 22, height: 14)
                        .position(
                            x: min(max(hole.midX, cardX + 24), cardX + cardW - 24),
                            y: below ? cardTop - 6 : cardTop + cardHeight + 6
                        )
                        .zIndex(1)
                }

                if settled {
                    card
                        .frame(width: cardW, height: cardHeight)
                        .position(x: geo.size.width / 2, y: cardTop + cardHeight / 2)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: settled)
            .contentShape(Rectangle())
            .onTapGesture(perform: advance)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
        .task(id: step) {
            // Wait for the map's glide (0.55s) to finish so the circle lands right on the villager.
            settled = false
            try? await Task.sleep(for: .milliseconds(stop.rect == nil ? 150 : (step == 0 ? 1350 : 620)))
            settled = true
        }
        .sensoryFeedback(.selection, trigger: step)
    }

    /// One step per tap, and only once the current villager is shown.
    private func advance() {
        guard settled else { return }
        settled = false
        next()
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let v = stop.villager {
                    Text(stop.isClosing ? "That's Workdoro!" : v.name)
                        .font(.pixel(18, .heavy))
                        .foregroundStyle(stop.isClosing ? Theme.ink : v.color)
                }
                Text(stop.place.uppercased())
                    .font(.pixel(10, .heavy))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            Text(stop.text)
                .font(.pixel(14, .semibold))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 6) {
                ForEach(0..<TourStop.all.count, id: \.self) { i in
                    Rectangle()
                        .fill(i == step ? Theme.gold : (i < step ? Theme.ink.opacity(0.5) : Theme.ink.opacity(0.15)))
                        .frame(width: i == step ? 16 : 8, height: 8)
                }
                Spacer()
                if !isLast {
                    Button(action: skip) {
                        Text("Skip")
                            .font(.pixel(13, .heavy))
                            .foregroundStyle(Theme.muted)
                            .frame(minWidth: 44, minHeight: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip the tour")
                }
                Button(action: advance) {
                    Text(isLast ? "Let's go!" : "Next ▸")
                        .font(.pixel(13, .heavy))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .pixelBox(Theme.gold, shadow: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .pixelBox(Theme.card)
    }
}

/// A small triangle for the tooltip's pointer.
private struct Pointer: Shape {
    let up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        return p
    }
}
