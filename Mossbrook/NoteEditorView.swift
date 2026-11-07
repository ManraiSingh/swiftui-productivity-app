import PencilKit
import PhotosUI
import SwiftUI

// MARK: - Palettes

enum NotePalette {
    static let paper: [NoteTint: Color] = [
        .cream: Color(hex: 0xFFFBEF), .white: Color(hex: 0xFFFFFF), .pink: Color(hex: 0xFDEBEF),
        .mint: Color(hex: 0xEAF6EC), .sky: Color(hex: 0xE8F2FB), .lavender: Color(hex: 0xF1ECFA)
    ]
    static let sticky: [Color] = [
        Color(hex: 0xFFE9A0), Color(hex: 0xFFC9D6), Color(hex: 0xC9F0D3), Color(hex: 0xC6E2FA), Color(hex: 0xDCCBF5), Color(hex: 0xFFD3A8)
    ]
    static let ink: [Color] = [
        Color(hex: 0x2B2233), Color(hex: 0xC65F4A), Color(hex: 0x4A6FA5), Color(hex: 0x6E8B5E), Color(hex: 0x8E5A8A), Color(hex: 0xF2C14E)
    ]
}

enum NoteImages {
    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NoteImages")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let name = UUID().uuidString + ".jpg"
        try? jpeg.write(to: folder.appendingPathComponent(name))
        syncWithCloud()
        return name
    }

    /// Copies photos both ways between this iPhone and iCloud, so every device has them.
    static func syncWithCloud() {
        guard let cloud = CloudSync.shared.imagesFolder else { return }
        let local = folder
        Task.detached {
            let fm = FileManager.default
            let mine = Set((try? fm.contentsOfDirectory(atPath: local.path)) ?? [])
            let theirs = Set(((try? fm.contentsOfDirectory(atPath: cloud.path)) ?? []).map {
                // Not-yet-downloaded iCloud files show up as ".name.icloud".
                $0.hasPrefix(".") && $0.hasSuffix(".icloud") ? String($0.dropFirst().dropLast(7)) : $0
            })
            for name in mine.subtracting(theirs) where name.hasSuffix(".jpg") {
                try? fm.copyItem(at: local.appendingPathComponent(name), to: cloud.appendingPathComponent(name))
            }
            for name in theirs.subtracting(mine) where name.hasSuffix(".jpg") {
                let src = cloud.appendingPathComponent(name)
                try? fm.startDownloadingUbiquitousItem(at: src)
                NSFileCoordinator().coordinate(readingItemAt: src, options: [], error: nil) { u in
                    try? fm.copyItem(at: u, to: local.appendingPathComponent(name))
                }
            }
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// Images are read from disk once, then kept in memory, so redraws stay smooth.
    static func load(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: folder.appendingPathComponent(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

// MARK: - Templates

enum NoteTemplate: String, CaseIterable, Identifiable {
    case blank, todo, meeting, journal, brainstorm
    var id: String { rawValue }

    var label: String {
        switch self {
        case .blank: "Blank page"
        case .todo: "To-do list"
        case .meeting: "Meeting notes"
        case .journal: "Daily journal"
        case .brainstorm: "Brainstorm board"
        }
    }

    var symbol: String {
        switch self {
        case .blank: "doc"
        case .todo: "checklist"
        case .meeting: "person.2"
        case .journal: "book.closed"
        case .brainstorm: "lightbulb"
        }
    }

    func make() -> Page {
        var page = Page(text: "")
        page.blocks = []
        switch self {
        case .blank:
            page.blocks = [NoteBlock(kind: .text)]
        case .todo:
            page.titleText = "To do"
            page.blocks = (0..<3).map { _ in NoteBlock(kind: .checklist) }
            page.paper = .plain
        case .meeting:
            page.titleText = "Meeting notes"
            page.blocks = [
                NoteBlock(kind: .heading, text: "Agenda"), NoteBlock(kind: .bullet),
                NoteBlock(kind: .heading, text: "Notes"), NoteBlock(kind: .text),
                NoteBlock(kind: .heading, text: "Action items"), NoteBlock(kind: .checklist)
            ]
        case .journal:
            page.titleText = Date().formatted(.dateTime.weekday(.wide).day().month(.wide))
            page.blocks = [
                NoteBlock(kind: .heading, text: "Grateful for"), NoteBlock(kind: .numbered), NoteBlock(kind: .numbered), NoteBlock(kind: .numbered),
                NoteBlock(kind: .heading, text: "Today"), NoteBlock(kind: .text),
                NoteBlock(kind: .quote, text: "One thing I learned")
            ]
            page.tint = .pink
        case .brainstorm:
            page.titleText = "Brainstorm"
            page.blocks = [NoteBlock(kind: .text, text: "Drop ideas anywhere on the board.")]
            page.paper = .dots
            page.tint = .sky
            page.stickies = [
                Sticky(text: "Idea", color: 0, x: 40, y: 160, tilt: -3),
                Sticky(text: "Question", color: 1, x: 200, y: 200, tilt: 2),
                Sticky(text: "Next step", color: 2, x: 90, y: 360, tilt: 1)
            ]
        }
        return page
    }
}

// MARK: - Editor

struct NoteEditorView: View {
    enum Mode: String, CaseIterable {
        case write, draw, sticky, shapes

        var label: String {
            switch self {
            case .write: "Write"
            case .draw: "Pens"
            case .sticky: "Stickies"
            case .shapes: "Shapes"
            }
        }

        var symbol: String {
            switch self {
            case .write: "textformat"
            case .draw: "pencil.tip"
            case .sticky: "note.text"
            case .shapes: "square.on.circle"
            }
        }
    }

    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var page: Page
    @State private var mode: Mode = .write
    @State private var selectedShape: UUID?
    @State private var shapeColor = 0
    @State private var shapeFilled = false
    @State private var photo: PhotosPickerItem?
    @State private var askFolder = false
    @State private var folderName = ""
    @State private var confirmDelete = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focus: UUID?
    @FocusState private var titleFocused: Bool
    /// Every page of the note. The one on screen is edited live in `page`'s own fields, and
    /// `composed` puts it back in its slot before anything is saved.
    @State private var sheets: [NoteSheet] = []
    @State private var shown = 0
    @State private var turn: Edge = .trailing
    @State private var confirmDeletePage = false

    static let pageHeight: CGFloat = 1500

    var body: some View {
        VStack(spacing: 0) {
            topBar
            modePicker
            pageBar
            ScrollView {
                ZStack(alignment: .topLeading) {
                    PaperBackground(style: page.paper, tint: NotePalette.paper[page.tint] ?? .white)
                    writing
                        .allowsHitTesting(mode == .write)
                    shapesLayer
                        .allowsHitTesting(mode == .shapes)
                    DrawingCanvas(data: $page.drawing, active: mode == .draw)
                        .allowsHitTesting(mode == .draw)
                    stickiesLayer
                        .allowsHitTesting(mode == .write || mode == .sticky)
                }
                .frame(height: Self.pageHeight)
                .contentShape(Rectangle())
                .onTapGesture { selectedShape = nil }
                .id(sheetID)
                .transition(.asymmetric(insertion: .move(edge: turn).combined(with: .opacity),
                                        removal: .move(edge: turn == .trailing ? .leading : .trailing).combined(with: .opacity)))
            }
            .clipped()
            .scrollDisabled(mode == .draw)
            .scrollDismissesKeyboard(.interactively)
            if mode != .draw {
                toolBar
            }
        }
        .background(Theme.paper)
        // Cream paper all the way up, so the clock and battery stay dark.
        .preferredColorScheme(.light)
        .onChange(of: photo) { Task { await addPhoto() } }
        .onAppear { if sheets.isEmpty { sheets = page.sheets } }
        .task {
            // A brand-new blank note is ready to type a title into straight away.
            guard page.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(450))
            titleFocused = true
        }
        .onDisappear {
            saveTask?.cancel()
            store.savePage(composed)
        }
        .onChange(of: page) {
            // Save once you pause, not on every keystroke or nudge: saving rewrites the whole notebook.
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                store.savePage(composed)
            }
        }
        .confirmationDialog("Remove page \(shown + 1)?", isPresented: $confirmDeletePage, titleVisibility: .visible) {
            Button("Remove page", role: .destructive) { removeShownPage() }
        } message: {
            Text("Everything on this page goes with it.")
        }
        .alert("Move to folder", isPresented: $askFolder) {
            TextField("Folder name", text: $folderName)
            Button("Move") { page.folder = folderName.trimmingCharacters(in: .whitespaces) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this note?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete note", role: .destructive) {
                store.deletePage(page)
                page = Page(text: "")
                sheets = page.sheets
                shown = 0
                dismiss()
            }
        }
    }

    // MARK: Pages

    private var sheetID: UUID { sheets.indices.contains(shown) ? sheets[shown].id : page.id }
    private var pageCount: Int { max(sheets.count, 1) }

    /// The whole note, with the page on screen put back in its place.
    private var composed: Page {
        var all = sheets.isEmpty ? page.sheets : sheets
        if all.indices.contains(shown) { all[shown] = live(id: all[shown].id) }
        var full = page
        full.sheets = all
        return full
    }

    private func live(id: UUID) -> NoteSheet {
        NoteSheet(id: id, blocks: page.blocks, drawing: page.drawing, stickies: page.stickies, shapes: page.shapes)
    }

    private func show(_ index: Int) {
        guard sheets.indices.contains(index), index != shown else { return }
        focus = nil
        titleFocused = false
        selectedShape = nil
        sheets[shown] = live(id: sheets[shown].id)
        turn = index > shown ? .trailing : .leading
        let next = sheets[index]
        withAnimation(.snappy(duration: 0.28)) {
            shown = index
            page.blocks = next.blocks.isEmpty ? [NoteBlock(kind: .text)] : next.blocks
            page.drawing = next.drawing
            page.stickies = next.stickies
            page.shapes = next.shapes
        }
    }

    private func addPage() {
        if sheets.isEmpty { sheets = page.sheets }
        sheets[shown] = live(id: sheets[shown].id)
        sheets.insert(NoteSheet(), at: shown + 1)
        show(shown + 1)
        mode = .write
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = page.blocks.first?.id }
    }

    private func removeShownPage() {
        guard sheets.count > 1 else { return }
        let gone = shown
        sheets.remove(at: gone)
        let target = min(gone, sheets.count - 1)
        // Load the neighbour straight in (the removed page has nothing to save).
        shown = target
        turn = .leading
        let next = sheets[target]
        withAnimation(.snappy(duration: 0.28)) {
            page.blocks = next.blocks.isEmpty ? [NoteBlock(kind: .text)] : next.blocks
            page.drawing = next.drawing
            page.stickies = next.stickies
            page.shapes = next.shapes
        }
    }

    private var pageBar: some View {
        HStack(spacing: 8) {
            Button { show(shown - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .heavy)).frame(width: 40, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(shown > 0 ? Theme.ink : Theme.muted.opacity(0.35))
            .disabled(shown == 0)
            .accessibilityLabel("Previous page")

            Menu {
                ForEach(0..<pageCount, id: \.self) { i in
                    Button { show(i) } label: {
                        if i == shown { Label("Page \(i + 1)", systemImage: "checkmark") } else { Text("Page \(i + 1)") }
                    }
                }
                if pageCount > 1 {
                    Divider()
                    Button(role: .destructive) { confirmDeletePage = true } label: {
                        Label("Remove this page", systemImage: "trash")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    PageDots(count: pageCount, current: shown)
                    Text("Page \(shown + 1) of \(pageCount)")
                        .font(.pixel(11, .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .pixelBox(Theme.card, shadow: 1)
            }
            .accessibilityLabel("Page \(shown + 1) of \(pageCount). Choose a page")

            Button { show(shown + 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).frame(width: 40, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(shown < pageCount - 1 ? Theme.ink : Theme.muted.opacity(0.35))
            .disabled(shown >= pageCount - 1)
            .accessibilityLabel("Next page")

            Spacer(minLength: 0)

            Button(action: addPage) {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .heavy))
                    Text("New page").font(.pixel(11, .heavy))
                }
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .pixelBox(Theme.moPlum, shadow: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a new page after this one")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PixelButtonStyle(fill: Theme.card, hPad: 0))
            .accessibilityLabel("Save and close")

            TextField("Title", text: $page.titleText)
                .font(.pixel(20, .heavy))
                .foregroundStyle(Theme.ink)
                .focused($titleFocused)
                .submitLabel(.next)
                .onSubmit { focus = page.blocks.first?.id }

            Button {
                page.pinned.toggle()
            } label: {
                Image(systemName: page.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(page.pinned ? Theme.red : Theme.ink)
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel(page.pinned ? "Unpin" : "Pin")

            Menu {
                Picker("Paper", selection: $page.paper) {
                    Label("Plain", systemImage: "rectangle").tag(PaperStyle.plain)
                    Label("Lined", systemImage: "line.3.horizontal").tag(PaperStyle.lined)
                    Label("Grid", systemImage: "grid").tag(PaperStyle.grid)
                    Label("Dots", systemImage: "circle.grid.3x3").tag(PaperStyle.dots)
                }
                Picker("Paper color", selection: $page.tint) {
                    ForEach(NoteTint.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Button {
                    folderName = page.folder
                    askFolder = true
                } label: { Label(page.folder.isEmpty ? "Move to folder…" : "Folder: \(page.folder)", systemImage: "folder") }
                ShareLink(item: shareText) { Label("Share as text", systemImage: "square.and.arrow.up") }
                if page.drawing != nil {
                    Button(role: .destructive) { page.drawing = nil } label: { Label("Clear drawing", systemImage: "scribble") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete note", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 44)
            }
            .accessibilityLabel("Note options")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                let on = mode == m
                Button {
                    focus = nil
                    titleFocused = false
                    selectedShape = nil
                    withAnimation(.snappy) { mode = m }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: m.symbol).font(.system(size: 14, weight: .bold))
                        Text(m.label).font(.pixel(10, .heavy))
                    }
                    .foregroundStyle(on ? Theme.cream : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .pixelBox(on ? Theme.moPlum : Theme.card, shadow: on ? 2 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch mode {
                case .write:
                    tool("Text", "text.alignleft") { insert(.text) }
                    tool("Heading", "textformat.size") { insert(.heading) }
                    tool("Checklist", "checklist") { insert(.checklist) }
                    tool("Bullets", "list.bullet") { insert(.bullet) }
                    tool("Numbers", "list.number") { insert(.numbered) }
                    tool("Quote", "text.quote") { insert(.quote) }
                    tool("Divider", "minus") { insert(.divider) }
                    PhotosPicker(selection: $photo, matching: .images) {
                        toolLabel("Photo", "photo")
                    }
                case .sticky:
                    ForEach(NotePalette.sticky.indices, id: \.self) { i in
                        Button { addSticky(color: i) } label: {
                            VStack(spacing: 2) {
                                Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
                                Text("Sticky").font(.pixel(9, .heavy))
                            }
                            .foregroundStyle(Theme.ink)
                            .frame(width: 58, height: 48)
                            .pixelBox(NotePalette.sticky[i], shadow: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add sticky note, color \(i + 1)")
                    }
                case .shapes:
                    ForEach(NoteShape.Kind.allCases, id: \.self) { kind in
                        Button { addShape(kind) } label: {
                            NoteShapePath(kind: kind)
                                .stroke(NotePalette.ink[shapeColor], lineWidth: 2.5)
                                .frame(width: 26, height: 22)
                                .frame(width: 48, height: 48)
                                .pixelBox(Theme.card, shadow: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(kind.rawValue)")
                    }
                    Rectangle().fill(Theme.ink.opacity(0.2)).frame(width: 2, height: 36)
                    ForEach(NotePalette.ink.indices, id: \.self) { i in
                        Button {
                            shapeColor = i
                            updateSelected { $0.color = i }
                        } label: {
                            Circle().fill(NotePalette.ink[i])
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(shapeColor == i ? Theme.ink : .clear, lineWidth: 3).padding(-4))
                                .frame(width: 36, height: 48)
                        }
                        .accessibilityLabel("Shape color \(i + 1)")
                    }
                    Button {
                        shapeFilled.toggle()
                        updateSelected { $0.filled = shapeFilled }
                    } label: { toolLabel(shapeFilled ? "Filled" : "Outline", shapeFilled ? "circle.fill" : "circle") }
                        .buttonStyle(.plain)
                case .draw:
                    EmptyView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 2) }
    }

    private func tool(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolLabel(label, symbol) }
            .buttonStyle(.plain)
    }

    private func toolLabel(_ label: String, _ symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold))
            Text(label).font(.pixel(9, .heavy))
        }
        .foregroundStyle(Theme.ink)
        .frame(width: 62, height: 48)
        .pixelBox(Theme.card, shadow: 1)
    }

    // MARK: Layers

    private var writing: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach($page.blocks) { $block in
                BlockRow(
                    block: $block,
                    number: number(for: block),
                    focus: $focus,
                    onReturn: { rest in returnPressed(after: block, carrying: rest) },
                    onDelete: { remove(block) }
                )
            }
            Color.clear
                .frame(height: 240)
                .contentShape(Rectangle())
                .onTapGesture { tapBelow() }
        }
        .padding(.horizontal, 28)
        .padding(.top, NoteRuling.topPadding)
    }

    private var shapesLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach($page.shapes) { $shape in
                ShapeItem(shape: $shape, selected: selectedShape == shape.id, editable: mode == .shapes) {
                    selectedShape = shape.id
                    shapeColor = shape.color
                    shapeFilled = shape.filled
                } onDelete: {
                    page.shapes.removeAll { $0.id == shape.id }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var stickiesLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach($page.stickies) { $sticky in
                StickyView(sticky: $sticky) {
                    page.stickies.removeAll { $0.id == sticky.id }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Actions

    private var shareText: String {
        var copy = composed
        copy.syncText()
        return copy.text
    }

    private func number(for block: NoteBlock) -> Int {
        guard let i = page.blocks.firstIndex(where: { $0.id == block.id }) else { return 1 }
        var n = 1
        var j = i - 1
        while j >= 0 && page.blocks[j].kind == .numbered { n += 1; j -= 1 }
        return n
    }

    private func insert(_ kind: NoteBlock.Kind) {
        let new = NoteBlock(kind: kind)
        if let id = focus, let i = page.blocks.firstIndex(where: { $0.id == id }) {
            if page.blocks[i].text.isEmpty && kind != .divider {
                page.blocks[i].kind = kind
                return
            }
            page.blocks.insert(new, at: i + 1)
        } else {
            page.blocks.append(new)
        }
        if kind == .divider {
            let after = NoteBlock(kind: .text)
            if let i = page.blocks.firstIndex(where: { $0.id == new.id }) { page.blocks.insert(after, at: i + 1) }
            focus = after.id
        } else {
            focus = new.id
        }
    }

    private func returnPressed(after block: NoteBlock, carrying rest: String = "") {
        guard let i = page.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let listy: Set<NoteBlock.Kind> = [.checklist, .bullet, .numbered]
        // Return on an empty list row ends the list, and you keep writing on that line.
        if listy.contains(page.blocks[i].kind) && page.blocks[i].text.isEmpty && rest.isEmpty {
            page.blocks[i].kind = .text
            let id = block.id
            DispatchQueue.main.async { focus = id }
            return
        }
        var next = NoteBlock(kind: listy.contains(block.kind) ? block.kind : .text)
        next.text = rest
        page.blocks.insert(next, at: i + 1)
        focus = next.id
    }

    private func remove(_ block: NoteBlock) {
        guard let i = page.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        page.blocks.remove(at: i)
        if page.blocks.isEmpty { page.blocks = [NoteBlock(kind: .text)] }
        focus = page.blocks[max(0, i - 1)].id
    }

    private func tapBelow() {
        if let last = page.blocks.last, last.kind == .text, last.text.isEmpty {
            focus = last.id
        } else {
            let b = NoteBlock(kind: .text)
            page.blocks.append(b)
            focus = b.id
        }
    }

    private func addSticky(color: Int) {
        let n = Double(page.stickies.count % 6)
        page.stickies.append(Sticky(color: color, x: 40 + n * 22, y: 140 + n * 40, tilt: [-3, 2, -1, 3, -2, 1][Int(n)]))
    }

    private func addShape(_ kind: NoteShape.Kind) {
        let n = Double(page.shapes.count % 6)
        var shape = NoteShape(kind: kind, x: 60 + n * 20, y: 180 + n * 30, color: shapeColor, filled: shapeFilled)
        if kind == .line || kind == .arrow { shape.h = 30 }
        page.shapes.append(shape)
        selectedShape = shape.id
    }

    private func updateSelected(_ change: (inout NoteShape) -> Void) {
        guard let id = selectedShape, let i = page.shapes.firstIndex(where: { $0.id == id }) else { return }
        change(&page.shapes[i])
    }

    private func addPhoto() async {
        guard let item = photo, let data = try? await item.loadTransferable(type: Data.self), let name = NoteImages.save(data) else { return }
        await MainActor.run {
            var block = NoteBlock(kind: .image)
            block.image = name
            if let id = focus, let i = page.blocks.firstIndex(where: { $0.id == id }) {
                page.blocks.insert(block, at: i + 1)
            } else {
                page.blocks.append(block)
            }
            photo = nil
        }
    }
}

// MARK: - Blocks

struct BlockRow: View {
    @Binding var block: NoteBlock
    let number: Int
    var focus: FocusState<UUID?>.Binding
    let onReturn: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch block.kind {
            case .checklist:
                Button {
                    withAnimation(.snappy) { block.checked.toggle() }
                } label: {
                    Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(block.checked ? Theme.leaf : Theme.ink)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(block.checked ? "Done" : "Not done")
                field(.pixel(15, .medium), strike: block.checked)
            case .bullet:
                Text("•").font(.pixel(18, .heavy)).foregroundStyle(Theme.moPlum)
                field(.pixel(15, .medium))
            case .numbered:
                Text("\(number).").font(.pixel(15, .heavy)).foregroundStyle(Theme.moPlum)
                field(.pixel(15, .medium))
            case .heading:
                field(.pixel(20, .heavy), placeholder: "Heading")
            case .quote:
                field(.pixel(15, .medium).italic(), placeholder: "Quote", color: Theme.muted)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.moPlum).frame(width: 4).padding(.vertical, 6)
                    }
            case .divider:
                Rectangle()
                    .fill(Theme.ink.opacity(0.25))
                    .frame(height: 2)
                    .padding(.vertical, 10)
            case .image:
                if let name = block.image, let image = NoteImages.load(name) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 238)
                        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 2))
                        .frame(height: 252, alignment: .center)
                        .accessibilityLabel("Photo")
                }
            case .text:
                field(.pixel(15, .regular), placeholder: "Start writing…")
            }
        }
        .frame(minHeight: block.kind == .heading ? NoteRuling.gap * 2 : NoteRuling.gap, alignment: .bottomLeading)
        .contextMenu {
            Menu("Turn into") {
                ForEach([NoteBlock.Kind.text, .heading, .checklist, .bullet, .numbered, .quote], id: \.self) { kind in
                    Button(kind.rawValue.capitalized) { block.kind = kind }
                }
            }
            Button(role: .destructive, action: onDelete) { Label("Delete block", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func field(_ font: Font, placeholder: String = "", strike: Bool = false, color: Color = Theme.ink) -> some View {
        let singleLine: Set<NoteBlock.Kind> = [.checklist, .bullet, .numbered, .heading]
        if singleLine.contains(block.kind) {
            TextField(placeholder, text: $block.text)
                .font(font)
                .foregroundStyle(strike ? Theme.muted : color)
                .strikethrough(strike, color: Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .focused(focus, equals: block.id)
                .submitLabel(.next)
                .onSubmit { onReturn("") }
        } else {
            TextField(placeholder, text: $block.text, axis: .vertical)
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(NoteRuling.gap - 18)
                .padding(.top, NoteRuling.gap - 18)
                .focused(focus, equals: block.id)
        }
    }
}

// MARK: - Paper

/// A little row of pixel squares, one per page, with the open page filled in.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(count, 6), id: \.self) { i in
                Rectangle()
                    .fill(i == min(current, 5) ? Theme.moPlum : Theme.ink.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The ruling every row of writing snaps to: rows start at the top padding and are `gap` tall,
/// so each line of text rests on a paper line.
enum NoteRuling {
    static let gap: CGFloat = 28
    static let topPadding: CGFloat = 20
    static var firstLine: CGFloat { topPadding + gap - 4 }
}

struct PaperBackground: View {
    let style: PaperStyle
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(tint))
            let line = Color(hex: 0x8FA9C9).opacity(0.35)
            let gap = NoteRuling.gap
            let first = NoteRuling.firstLine
            switch style {
            case .plain:
                break
            case .lined:
                var y = first
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(line))
                    y += gap
                }
                ctx.fill(Path(CGRect(x: 20, y: 0, width: 1.5, height: size.height)), with: .color(Color(hex: 0xE58A8A).opacity(0.5)))
            case .grid:
                var x: CGFloat = 0
                while x < size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(line)); x += gap }
                var y = first.truncatingRemainder(dividingBy: gap)
                while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(line)); y += gap }
            case .dots:
                var y = first.truncatingRemainder(dividingBy: gap)
                while y < size.height {
                    var x: CGFloat = 14
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(line.opacity(1.6)))
                        x += gap
                    }
                    y += gap
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pens

/// Apple's PencilKit canvas with the full tool picker: pens, markers, pencil, eraser, lasso and ruler.
struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data?
    let active: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .anyInput
        view.isScrollEnabled = false
        view.tool = PKInkingTool(.pen, color: UIColor(red: 0.17, green: 0.13, blue: 0.2, alpha: 1), width: 3)
        if let data, let drawing = try? PKDrawing(data: data) { view.drawing = drawing }
        view.delegate = context.coordinator
        context.coordinator.picker.addObserver(view)
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = active
        context.coordinator.picker.setVisible(active, forFirstResponder: view)
        if active {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        let picker = PKToolPicker()

        init(_ parent: DrawingCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.data = canvasView.drawing.strokes.isEmpty ? nil : canvasView.drawing.dataRepresentation()
        }
    }
}

// MARK: - Stickies

struct StickyView: View {
    @Binding var sticky: Sticky
    let onDelete: () -> Void
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.4))
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.ink.opacity(0.5))
                        .frame(width: 28, height: 24)
                }
                .accessibilityLabel("Remove sticky note")
            }
            .padding(.leading, 8)
            .frame(height: 24)
            .background(Color.black.opacity(0.05))
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        sticky.x += value.translation.width
                        sticky.y += value.translation.height
                    }
            )
            .accessibilityLabel("Drag to move")

            TextField("Write…", text: $sticky.text, axis: .vertical)
                .font(.pixel(13, .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...7)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        }
        .frame(width: 150)
        .background(NotePalette.sticky[sticky.color % NotePalette.sticky.count])
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
        .background(Rectangle().fill(Color.black.opacity(0.18)).offset(x: 3, y: 3))
        .rotationEffect(.degrees(sticky.tilt))
        .offset(x: sticky.x + drag.width, y: sticky.y + drag.height)
    }
}

// MARK: - Shapes

struct NoteShapePath: Shape {
    let kind: NoteShape.Kind

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .rectangle:
            p.addRoundedRect(in: r, cornerSize: CGSize(width: 6, height: 6))
        case .circle:
            p.addEllipse(in: r)
        case .triangle:
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        case .star:
            let c = CGPoint(x: r.midX, y: r.midY)
            for i in 0..<10 {
                let a = Double(i) * .pi / 5 - .pi / 2
                let rad = i % 2 == 0 ? 1.0 : 0.45
                let pt = CGPoint(x: c.x + cos(a) * r.width / 2 * rad, y: c.y + sin(a) * r.height / 2 * rad)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        case .heart:
            let w = r.width, h = r.height
            p.move(to: CGPoint(x: r.midX, y: r.maxY))
            p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.3), control1: CGPoint(x: r.midX - w * 0.1, y: r.maxY - h * 0.15), control2: CGPoint(x: r.minX, y: r.minY + h * 0.6))
            p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.3), radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.3), radius: w * 0.25, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + h * 0.6), control2: CGPoint(x: r.midX + w * 0.1, y: r.maxY - h * 0.15))
        case .arrow:
            let y = r.midY
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.move(to: CGPoint(x: r.maxX - min(16, r.width / 3), y: y - min(12, r.height / 2)))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.addLine(to: CGPoint(x: r.maxX - min(16, r.width / 3), y: y + min(12, r.height / 2)))
        case .line:
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        }
        return p
    }
}

struct ShapeItem: View {
    @Binding var shape: NoteShape
    let selected: Bool
    let editable: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @GestureState private var move: CGSize = .zero
    @GestureState private var resize: CGSize = .zero

    var body: some View {
        let color = NotePalette.ink[shape.color % NotePalette.ink.count]
        let w = max(20, shape.w + resize.width)
        let h = max(shape.kind == .line || shape.kind == .arrow ? 16 : 20, shape.h + resize.height)
        let fillable = shape.kind != .line && shape.kind != .arrow
        ZStack(alignment: .topLeading) {
            ZStack {
                if shape.filled && fillable {
                    NoteShapePath(kind: shape.kind).fill(color.opacity(0.85))
                }
                NoteShapePath(kind: shape.kind).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            .frame(width: w, height: h)
            .padding(6)
            .contentShape(Rectangle())
            .overlay {
                if selected && editable {
                    Rectangle().stroke(Theme.moPlum, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .onTapGesture(perform: onSelect)
            .highPriorityGesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($move) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        shape.x += value.translation.width
                        shape.y += value.translation.height
                        onSelect()
                    }
            )

            if selected && editable {
                Circle()
                    .fill(Theme.moPlum)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(Theme.cream, lineWidth: 2))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .offset(x: w + 12 - 22, y: h + 12 - 22)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .updating($resize) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                shape.w = max(20, shape.w + value.translation.width)
                                shape.h = max(16, shape.h + value.translation.height)
                            }
                    )
                    .accessibilityLabel("Resize")

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Theme.cream)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.red))
                        .frame(width: 44, height: 44)
                }
                .offset(x: -22, y: -22)
                .accessibilityLabel("Delete shape")
            }
        }
        .offset(x: shape.x + move.width, y: shape.y + move.height)
    }
}
