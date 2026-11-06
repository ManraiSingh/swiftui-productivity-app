import SwiftUI

struct PostOfficeView: View {
    @Environment(VillageStore.self) private var store
    @State private var draft = ""
    @State private var showDelivered = false
    @State private var repeatPick: RepeatRule?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VillagerHeader(villager: .pip, place: "Post office")

                if !store.bikeFixed {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("PIP'S BIKE")
                            .font(.pixel(12))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(store.bikeParts)/\(VillageStore.bikeGoal) parts")
                            .font(.pixel(12))
                            .foregroundStyle(Theme.pipBlue)
                    }
                    BikeView(parts: store.bikeParts)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(Color(hex: 0xDCEFD0))
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(BikePart.allCases, id: \.rawValue) { part in
                            let found = store.bikeParts >= part.rawValue
                            HStack(spacing: 5) {
                                Image(systemName: found ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(found ? Theme.leaf : Theme.muted)
                                Text(part.name)
                                    .font(.pixel(11, .semibold))
                                    .foregroundStyle(found ? Theme.ink : Theme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                    }
                    Text(store.bikeFixed ? "All fixed. Pip rides letters all over town now!" : "Each letter you deliver, Pip finds another part.")
                        .font(.pixel(12, .medium))
                        .foregroundStyle(Theme.muted)
                }
                .padding(14)
                .pixelBox(Theme.card)

                }

                HStack(spacing: 10) {
                    TextField("New letter… “call mom friday 6pm”", text: $draft)
                        .font(.pixel(14, .medium))
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(add)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .pixelBox(Theme.card, shadow: 2)
                    Menu {
                        Picker("Repeat", selection: $repeatPick) {
                            Text("Just once").tag(RepeatRule?.none)
                            ForEach(RepeatRule.allCases) { Text($0.label).tag(RepeatRule?.some($0)) }
                        }
                    } label: {
                        Image(systemName: "repeat")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(repeatPick == nil ? Theme.ink : Theme.cream)
                            .frame(width: 44, height: 48)
                            .pixelBox(repeatPick == nil ? Theme.card : Theme.pipBlue, shadow: 2)
                    }
                    .accessibilityLabel(repeatPick.map { "Repeats \($0.label.lowercased())" } ?? "Repeat")
                    Button("Give", action: add)
                        .buttonStyle(PixelButtonStyle(fill: Theme.pipBlue, foreground: Theme.cream))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("TO DELIVER · \(store.openLetters.count)")
                        .font(.pixel(12))
                        .foregroundStyle(Theme.muted)
                    if store.openLetters.isEmpty {
                        Text("Pip's satchel is empty. Nothing to do!")
                            .font(.pixel(13, .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.vertical, 6)
                    }
                    ForEach(store.openLetters) { LetterRow(letter: $0) }
                }

                if !store.deliveredLetters.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.snappy) { showDelivered.toggle() }
                        } label: {
                            HStack {
                                Text("DELIVERED · \(store.deliveredLetters.count)")
                                    .font(.pixel(12))
                                Image(systemName: showDelivered ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(Theme.muted)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if showDelivered {
                            ForEach(store.deliveredLetters) { LetterRow(letter: $0) }
                        }
                    }
                }
            }
            .padding(20)
            .padding(.top, 8)
        }
        .background(Theme.paper)
        .villageOverlays()
        .presentationDragIndicator(.visible)
    }

    private func add() {
        let parsed = Capture.parse(draft)
        guard !parsed.title.isEmpty else { return }
        withAnimation(.snappy) {
            store.addLetter(parsed.title, due: parsed.due, repeats: repeatPick ?? parsed.repeats)
        }
        draft = ""
        repeatPick = nil
    }
}

struct VillagerHeader: View {
    @Environment(VillageStore.self) private var store
    let villager: VillagerID
    let place: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 14) {
            BobbingSprite(sprite: villager.sprite, pixel: 5.5)
            VStack(alignment: .leading, spacing: 6) {
                Text(place.uppercased())
                    .font(.pixel(11))
                    .foregroundStyle(Theme.muted)
                Text(villager.name)
                    .font(.pixel(30, .heavy))
                    .foregroundStyle(villager.color)
                TimelineView(.periodic(from: .now, by: 6)) { tl in
                    SpeechBubble(text: Chatter.line(for: villager, store, t: tl.date.timeIntervalSinceReferenceDate), size: 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 8)
        }
    }
}

struct BikeView: View {
    let parts: Int

    var body: some View {
        Canvas { ctx, size in
            let s = floor(min(size.width / 22, size.height / 14))
            let ox = (size.width - 16 * s) / 2
            let oy = (size.height - 12 * s) / 2
            var c = ctx
            c.translateBy(x: ox, y: oy)
            let p = Painter(ctx: c, s: s)
            p.rect(-2, 11, 20, 1, Color(hex: 0xA8C99A))
            VillageRenderer.bike(p, x: 0, y: 0, parts: parts)
        }
        .accessibilityLabel("Pip's bike with \(parts) of 6 parts")
    }
}
