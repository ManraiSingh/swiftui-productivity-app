import SwiftUI

struct RootView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var openVillager: VillagerID?
    @State private var showCapture = false
    @State private var showCafe = false
    @State private var drawerOpen = false
    @State private var showLetter = false
    @State private var showTownHall = false
    @State private var showGreenhouse = false
    @Environment(\.displayScale) private var displayScale
    /// Current zoom (1 = the normal view) and where the world's top edge is on screen, for the sky behind.
    @State private var zoom: CGFloat = 1
    @State private var worldTop: CGFloat = 0
    @State private var mapOffset: CGPoint = .zero
    @State private var tourStep = 0
    /// The tour opens on the whole town before zooming in to the first villager.
    @State private var tourIntro = true

    /// A full screen or a tall sheet is over the town, so there's no need to keep animating it.
    private var townCovered: Bool { showCafe || showGreenhouse || openVillager != nil || showTownHall }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                let base = defaultDots(geo.size.width) / displayScale
                SkyBackdrop(phase: store.phase, weather: store.weather, pixel: base * zoom, horizon: worldTop, paused: townCovered)
                    .ignoresSafeArea()
                ZoomableWorld(
                    contentSize: CGSize(width: CGFloat(VillageLayout.worldWidth) * base, height: CGFloat(VillageLayout.worldHeight) * base),
                    minZoom: dotRange(geo.size.width).0 / defaultDots(geo.size.width),
                    maxZoom: 2,
                    snapStep: 1 / defaultDots(geo.size.width),
                    bottomInset: VillageDrawer.collapsedHeight - 20,
                    focus: tourFocus(base: base),
                    focusZoom: store.showTour ? (tourIntro ? dotRange(geo.size.width).0 / defaultDots(geo.size.width) : 1) : nil,
                    onChange: { z, offset in
                        zoom = z
                        worldTop = -offset.y
                        mapOffset = offset
                    },
                    onBackgroundTap: { if drawerOpen { withAnimation(.snappy) { drawerOpen = false } } }
                ) {
                    VillageSceneView(
                        onTap: open,
                        onTapCafe: { showCafe = true },
                        onMailbox: { showLetter = true },
                        onTownHall: { showTownHall = true },
                        paused: townCovered
                    )
                    .environment(store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .ignoresSafeArea()

                VillageHeader()
                    .frame(maxHeight: .infinity, alignment: .top)

                VillageDrawer(
                    expanded: $drawerOpen,
                    maxHeight: geo.size.height * 0.74,
                    open: open,
                    capture: { showCapture = true }
                )

                if store.showTour && !tourIntro {
                    TownTourOverlay(
                        step: tourStep,
                        screenRect: { r in
                            let k = base * zoom
                            let m = CGFloat(VillageLayout.margin)
                            // r.origin is the building's centre in town art pixels.
                            return CGRect(
                                x: (r.minX - r.width / 2 + m) * k - mapOffset.x,
                                y: (r.minY - r.height / 2) * k - mapOffset.y,
                                width: r.width * k, height: r.height * k
                            )
                        },
                        next: {
                            if tourStep < TourStop.all.count - 1 { tourStep += 1 } else { endTour() }
                        },
                        skip: endTour
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: store.showTour)
            .onChange(of: store.showTour, initial: true) { _, on in
                guard on else { return }
                tourIntro = true
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    tourIntro = false
                }
            }
        }
        .villageOverlays()
        .sheet(item: $openVillager) { villager in
            switch villager {
            case .pip: PostOfficeView()
            case .mo: LibraryView()
            case .bea: EmptyView()
            case .juniper: GreenhouseView()
            case .rosie: BakeryView()
            }
        }
        .sheet(isPresented: $showCapture) {
            CaptureView()
        }
        .sheet(isPresented: $showLetter) {
            DailyLetterView()
        }
        .sheet(isPresented: $showTownHall) {
            TownHallView()
        }
        .fullScreenCover(isPresented: $showCafe) {
            CafeView()
        }
        .fullScreenCover(isPresented: $showGreenhouse) {
            GreenhouseView()
        }
        .onAppear {
            store.applyWidgetDeliveries()
            store.resumeFocusIfNeeded()
            store.checkStory()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                store.applyWidgetDeliveries()
                CloudSync.shared.refresh()
                NoteImages.syncWithCloud()
                LiveFocus.publish(store)
                store.resumeFocusIfNeeded()
            }
        }
        .task(id: focusKey) {
            guard let session = store.activeFocus else { return }
            let wait = session.end.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { store.advanceFocus() }
        }
    }





    /// The normal view: about 128 art pixels across the screen, snapped to whole screen pixels.
    private func defaultDots(_ width: CGFloat) -> CGFloat {
        max(1, (width / 128 * displayScale).rounded(.down))
    }

    /// Zoomed out as far as the whole town fits across the screen; zoomed in to about twice the normal size.
    private func dotRange(_ width: CGFloat) -> (CGFloat, CGFloat) {
        let lo = max(1, (width * displayScale / CGFloat(VillageLayout.width + 24)).rounded(.down))
        return (lo, defaultDots(width) * 2)
    }

    /// Where the map should glide during the tour (world coordinates at zoom 1).
    private func tourFocus(base: CGFloat) -> CGPoint? {
        guard store.showTour else { return nil }
        if tourIntro {
            // Centre of the whole town.
            return CGPoint(x: (CGFloat(VillageLayout.width) / 2 + CGFloat(VillageLayout.margin)) * base,
                           y: CGFloat(VillageLayout.height) * 0.6 * base)
        }
        guard let r = TourStop.all[tourStep].rect else { return nil }
        return CGPoint(x: (r.minX + CGFloat(VillageLayout.margin)) * base, y: r.minY * base)
    }

    private func endTour() {
        tourStep = 0
        tourIntro = true
        store.finishTour()
    }

    private var skyTop: Color {
        switch store.phase {
        case .day: Color(hex: 0x9ED6EC)
        case .dusk: Color(hex: 0x8E6FA6)
        case .night: Color(hex: 0x161B3A)
        }
    }

    private var focusKey: String {
        guard let s = store.activeFocus else { return "none" }
        return "\(s.id)-\(s.round)-\(s.onBreak)-\(s.start.timeIntervalSince1970)"
    }

    private func open(_ villager: VillagerID) {
        switch villager {
        case .bea: showCafe = true
        case .juniper: showGreenhouse = true
        default: openVillager = villager
        }
    }
}

struct VillageHeader: View {
    @Environment(VillageStore.self) private var store
    @State private var gallery = false
    @State private var settings = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Workdoro")
                    .font(.pixel(26, .heavy))
                    .foregroundStyle(Theme.cream)
                    .shadow(color: Theme.ink, radius: 0, x: 2, y: 2)
                    #if DEBUG
                    .onLongPressGesture { gallery = true }
                    .fullScreenCover(isPresented: $gallery) { WidgetGallery() }
                    #endif
                Text(store.bikeFixed && store.bookDone ? "SEASON 1 · COMPLETE" : "SEASON 1 · WAKE THE VILLAGE")
                    .font(.pixel(10))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .pixelBox(Theme.gold, shadow: 2)
                HStack(spacing: 8) {
                    chip(symbol: store.weather.symbol, text: store.weather.label)
                    chip(sprite: Sprites.flame, text: store.streak == 1 ? "1 day" : "\(store.streak) days")
                }
                .padding(.top, 2)
            }
            Spacer()
            Menu {
                Picker("Time of day", selection: Binding(get: { store.phaseOverride }, set: { store.phaseOverride = $0 })) {
                    Label("Real time", systemImage: "clock").tag(DayPhase?.none)
                    Label("Day", systemImage: DayPhase.day.symbol).tag(DayPhase?.some(.day))
                    Label("Sunset", systemImage: DayPhase.dusk.symbol).tag(DayPhase?.some(.dusk))
                    Label("Night", systemImage: DayPhase.night.symbol).tag(DayPhase?.some(.night))
                }
                Picker("Weather", selection: Binding(get: { store.weatherOverride }, set: { store.weatherOverride = $0 })) {
                    Label("Today's weather", systemImage: "calendar").tag(Weather?.none)
                    ForEach(Weather.allCases) { w in
                        Label(w.label, systemImage: w.symbol).tag(Weather?.some(w))
                    }
                }
            } label: {
                Image(systemName: store.phaseOverride?.symbol ?? "clock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .pixelBox(Theme.cream)
            }
            .accessibilityLabel("Change time of day")
            Button { settings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .pixelBox(Theme.cream)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .sheet(isPresented: $settings) { SettingsView() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private func chip(sprite: Sprite, text: String) -> some View {
        HStack(spacing: 4) {
            SpriteView(sprite: sprite, pixel: 1.2)
            Text(text)
                .font(.pixel(10, .heavy))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .pixelBox(Theme.card, shadow: 2)
    }

    private func chip(symbol: String, text: String, tint: Color = Theme.ink) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.pixel(10, .heavy))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .pixelBox(Theme.card, shadow: 2)
    }
}

struct VillageDrawer: View {
    @Environment(VillageStore.self) private var store
    @Binding var expanded: Bool
    let maxHeight: CGFloat
    let open: (VillagerID) -> Void
    let capture: () -> Void
    @GestureState private var drag: CGFloat = 0

    static let collapsedHeight: CGFloat = 122

    var body: some View {
        let base = expanded ? maxHeight : Self.collapsedHeight
        let height = min(max(base - drag, Self.collapsedHeight), maxHeight)

        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Rectangle()
                        .fill(Theme.ink.opacity(0.3))
                        .frame(width: 44, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse" : "Show more")

                HStack(spacing: 8) {
                    if store.bikeFixed {
                        MiniCard(villager: .pip, title: "Mail", value: store.deliveredLetters.count, total: store.letters.count) { open(.pip) }
                    } else {
                        MiniCard(villager: .pip, title: "Bike", value: store.bikeParts, total: VillageStore.bikeGoal) { open(.pip) }
                    }
                    MiniCard(villager: .mo, title: "Book", value: store.pagesFound, total: VillageStore.bookGoal) { open(.mo) }
                    CafeMiniCard { open(.bea) }
                    Button(action: capture) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .heavy))
                            .frame(width: 52, height: 76)
                    }
                    .buttonStyle(PixelButtonStyle(hPad: 0))
                    .accessibilityLabel("Add a task or note")
                }
                .padding(.horizontal, 14)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .updating($drag) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        withAnimation(.snappy) {
                            if value.translation.height < -40 { expanded = true }
                            if value.translation.height > 40 { expanded = false }
                        }
                    }
            )

            if expanded {
                ScrollView {
                    DrawerDetails(open: open)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Theme.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 3) }
        .animation(.snappy, value: expanded)
    }
}

struct MiniCard: View {
    let villager: VillagerID
    let title: String
    let value: Int
    let total: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    SpriteView(sprite: villager.sprite, pixel: 2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.pixel(12, .heavy))
                            .foregroundStyle(Theme.ink)
                        Text("\(value)/\(total)")
                            .font(.pixel(10, .semibold))
                            .foregroundStyle(villager.color)
                    }
                }
                PixelProgress(value: value * 6 / max(total, 1), total: 6, color: villager.color, cellHeight: 6)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .pixelBox(Theme.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(villager.name): \(title), \(value) of \(total)")
    }
}

struct CafeMiniCard: View {
    @Environment(VillageStore.self) private var store
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    SpriteView(sprite: Sprites.bea, pixel: 2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Café")
                            .font(.pixel(12, .heavy))
                            .foregroundStyle(Theme.ink)
                        if let session = store.activeFocus {
                            TimelineView(.periodic(from: .now, by: 1)) { tl in
                                Text(FocusFormat.clock(session.end.timeIntervalSince(tl.date)))
                                    .font(.pixel(10, .semibold))
                                    .foregroundStyle(Theme.beaOrange)
                            }
                        } else {
                            Text("\(store.focusMinutes)m")
                                .font(.pixel(10, .semibold))
                                .foregroundStyle(Theme.beaOrange)
                        }
                    }
                }
                PixelProgress(value: min(store.focusMinutes, VillageStore.cafeGoal) * 6 / VillageStore.cafeGoal, total: 6, color: Theme.beaOrange, cellHeight: 6)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .pixelBox(store.isFocusing ? Color(hex: 0xFFF1C9) : Theme.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bea's café, \(count(store.focusMinutes, "minute")) focused")
    }
}

struct DrawerDetails: View {
    @Environment(VillageStore.self) private var store
    var open: (VillagerID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("LETTERS TO DELIVER")
                        .font(.pixel(12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Post office") { open(.pip) }
                        .font(.pixel(12))
                        .foregroundStyle(Theme.pipBlue)
                        .frame(minHeight: 44)
                }
                if store.openLetters.isEmpty {
                    Text("No letters right now. Tap + and tell Pip what needs doing.")
                        .font(.pixel(13, .medium))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(store.openLetters.prefix(5)) { LetterRow(letter: $0) }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("BEA'S CAFÉ")
                        .font(.pixel(12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button(store.isFocusing ? "Back to your seat" : "Start focusing") { open(.bea) }
                        .font(.pixel(12))
                        .foregroundStyle(Theme.beaOrange)
                        .frame(minHeight: 44)
                }
                Text("\(count(store.focusMinutes, "minute")) focused · \(count(store.focusSessions, "cup"))")
                    .font(.pixel(13, .medium))
                    .foregroundStyle(Theme.ink)
            }

            if let page = store.sortedPages.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("LATEST PAGE")
                            .font(.pixel(12))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Library") { open(.mo) }
                            .font(.pixel(12))
                            .foregroundStyle(Theme.moPlum)
                            .frame(minHeight: 44)
                    }
                    Button { open(.mo) } label: { PageCard(page: page) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 40)
    }
}

struct StoryCard: View {
    let villager: VillagerID
    let title: String
    let detail: String
    let value: Int
    let total: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    SpriteView(sprite: villager.sprite, pixel: 2.5)
                    Text(title)
                        .font(.pixel(14))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                PixelProgress(value: value, total: total, color: villager.color, cellHeight: 10)
                Text(detail)
                    .font(.pixel(11, .medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pixelBox(Theme.card)
        }
        .buttonStyle(.plain)
    }
}

struct LetterRow: View {
    @Environment(VillageStore.self) private var store
    let letter: Letter

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) {
                    if letter.done { store.undeliver(letter) } else { store.deliver(letter) }
                }
            } label: {
                ZStack {
                    Rectangle().fill(letter.done ? Theme.leaf : Theme.card)
                        .frame(width: 26, height: 26)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
                    if letter.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Theme.cream)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(letter.done ? "Mark as not delivered" : "Deliver")

            SpriteView(sprite: Sprites.envelope, pixel: 2.5)

            VStack(alignment: .leading, spacing: 3) {
                Text(letter.title)
                    .font(.pixel(14, .semibold))
                    .foregroundStyle(letter.done ? Theme.muted : Theme.ink)
                    .strikethrough(letter.done, color: Theme.muted)
                    .lineLimit(2)
                if !letter.done, letter.due != nil || letter.repeats != nil {
                    HStack(spacing: 6) {
                        if let due = letter.due {
                            Text(DueFormat.text(due))
                                .foregroundStyle(due < Date() ? Theme.red : Theme.muted)
                        }
                        if let rule = letter.repeats {
                            Label(rule.short, systemImage: "repeat")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(Theme.pipBlue)
                        }
                    }
                    .font(.pixel(11, .medium))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 12)
        .pixelBox(Theme.card)
        .contextMenu {
            Menu {
                Picker("Repeat", selection: Binding(get: { letter.repeats }, set: { store.setRepeat(letter, $0) })) {
                    Text("Just once").tag(RepeatRule?.none)
                    ForEach(RepeatRule.allCases) { Text($0.label).tag(RepeatRule?.some($0)) }
                }
            } label: { Label("Repeat", systemImage: "repeat") }
            Button(role: .destructive) { store.deleteLetter(letter) } label: { Label("Remove letter", systemImage: "trash") }
        }
    }
}

struct PageCard: View {
    let page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(page.title)
                    .font(.pixel(14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                SpriteView(sprite: Sprites.page, pixel: 2)
            }
            if !page.body.isEmpty {
                Text(page.body)
                    .font(.pixel(12, .regular))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(3)
            }
            Text(page.edited.formatted(.dateTime.day().month(.abbreviated)))
                .font(.pixel(10, .medium))
                .foregroundStyle(Theme.moPlum)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .pixelBox(Theme.card)
    }
}
