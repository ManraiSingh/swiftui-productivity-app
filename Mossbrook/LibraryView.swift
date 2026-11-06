import SwiftUI

/// Mo's library: every note, with search, folders, pins and templates.
struct LibraryView: View {
    @Environment(VillageStore.self) private var store
    @State private var editing: Page?
    @State private var search = ""
    @State private var filter = "All"

    private var filtered: [Page] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.sortedPages
            .filter { page in
                switch filter {
                case "All": true
                case "Pinned": page.pinned
                default: page.folder == filter
                }
            }
            .filter { q.isEmpty || $0.text.lowercased().contains(q) || $0.title.lowercased().contains(q) }
            .sorted { ($0.pinned ? 1 : 0, $0.edited) > ($1.pinned ? 1 : 0, $1.edited) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VillagerHeader(villager: .mo, place: "Library")

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("MO'S BOOK")
                                .font(.pixel(11))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text("\(store.pagesFound)/\(VillageStore.bookGoal)")
                                .font(.pixel(11))
                                .foregroundStyle(Theme.moPlum)
                        }
                        PixelProgress(value: store.pagesFound, total: VillageStore.bookGoal, color: Theme.moPlum, cellHeight: 10)
                    }
                    .padding(12)
                    .pixelBox(Theme.card)
                }

                HStack(spacing: 10) {
                    Button {
                        editing = NoteTemplate.blank.make()
                    } label: {
                        Label("New note", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PixelButtonStyle(fill: Theme.moPlum, foreground: Theme.cream))

                    Menu {
                        ForEach(NoteTemplate.allCases) { template in
                            Button {
                                editing = template.make()
                            } label: { Label(template.label, systemImage: template.symbol) }
                        }
                    } label: {
                        VStack(spacing: 1) {
                            Image(systemName: "rectangle.stack").font(.system(size: 14, weight: .bold))
                            Text("Templates").font(.pixel(9, .heavy))
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(width: 84, height: 44)
                        .pixelBox(Theme.card)
                    }
                    .accessibilityLabel("New note from a template")
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    TextField("Search notes", text: $search)
                        .font(.pixel(14, .medium))
                        .submitLabel(.search)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .pixelBox(Theme.card, shadow: 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["All", "Pinned"] + store.folders, id: \.self) { name in
                            let on = filter == name
                            Button { filter = name } label: {
                                HStack(spacing: 4) {
                                    if name == "Pinned" { Image(systemName: "pin.fill").font(.system(size: 10, weight: .bold)) }
                                    else if name != "All" { Image(systemName: "folder.fill").font(.system(size: 10, weight: .bold)) }
                                    Text(name).font(.pixel(12, .heavy))
                                }
                                .foregroundStyle(on ? Theme.cream : Theme.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .pixelBox(on ? Theme.moPlum : Theme.card, shadow: on ? 2 : 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.bottom, 4)
                }

                if filtered.isEmpty {
                    Text(store.pages.isEmpty
                         ? "No notes yet. Start one, or try a template: a to-do list, meeting notes, a journal or a brainstorm board."
                         : "Nothing here yet.")
                        .font(.pixel(13, .medium))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 6)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(filtered) { page in
                        Button { editing = page } label: { NoteCard(page: page) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { store.togglePin(page) } label: {
                                    Label(page.pinned ? "Unpin" : "Pin", systemImage: page.pinned ? "pin.slash" : "pin")
                                }
                                Button { store.duplicatePage(page) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                ShareLink(item: page.text) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { store.deletePage(page) } label: { Label("Delete", systemImage: "trash") }
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
        .fullScreenCover(item: $editing) { page in
            NoteEditorView(page: page)
        }
    }
}

/// A note in the library grid, on its own paper color.
struct NoteCard: View {
    let page: Page

    var body: some View {
        let progress = page.checklistProgress
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(page.title)
                    .font(.pixel(14, .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if page.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.red)
                }
            }
            if !page.body.isEmpty {
                Text(page.body)
                    .font(.pixel(11, .regular))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if progress.total > 0 {
                    Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                }
                if !page.moreSheets.isEmpty { Label("\(page.moreSheets.count + 1)", systemImage: "book.pages") }
                if page.hasDrawing { Image(systemName: "scribble") }
                if !page.allStickies.isEmpty { Label("\(page.allStickies.count)", systemImage: "note.text") }
                if page.hasPhoto { Image(systemName: "photo") }
                Spacer(minLength: 0)
            }
            .font(.pixel(10, .heavy))
            .foregroundStyle(Theme.moPlum)
            HStack {
                Text(page.edited.formatted(.dateTime.day().month(.abbreviated)))
                if !page.folder.isEmpty {
                    Text("· \(page.folder)").lineLimit(1)
                }
            }
            .font(.pixel(10, .medium))
            .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(alignment: .topTrailing) {
            if let sticky = page.stickies.first {
                Rectangle()
                    .fill(NotePalette.sticky[sticky.color % NotePalette.sticky.count])
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(8))
                    .offset(x: -8, y: 30)
                    .opacity(0.9)
            }
        }
        .pixelBox(NotePalette.paper[page.tint] ?? Theme.card)
    }
}
