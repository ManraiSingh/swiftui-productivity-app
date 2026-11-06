import SwiftUI

// MARK: - Rosie's bakery: treats

enum Treat: Int, CaseIterable {
    case croissant, cookie, cupcake, bun, pie, cake

    var name: String {
        ["Croissant", "Cookie", "Cupcake", "Cinnamon bun", "Berry pie", "Birthday cake"][rawValue]
    }

    /// How many treats you need to have baked before this one unlocks.
    var unlockAt: Int { [1, 3, 6, 10, 15, 25][rawValue] }

    var sprite: Sprite {
        let ink = VillageRenderer.ink
        switch self {
        case .croissant:
            return Sprite(["...kkkk...", "..kddddk..", ".kdlddldk.", "kdddddddk", ".kkkkkkk."],
                          ["k": ink, "d": Color(hex: 0xD99456), "l": Color(hex: 0xF2C14E)])
        case .cookie:
            return Sprite([".kkkkk.", "kddcddk", "kcdddck", "kdddcdk", ".kkkkk."],
                          ["k": ink, "d": Color(hex: 0xD9A45E), "c": Color(hex: 0x6B4226)])
        case .cupcake:
            return Sprite(["...r...", ".kpppk.", "kpppppk", "kbbbbbk", ".kbbbk.", ".kkkkk."],
                          ["k": ink, "r": Color(hex: 0xD9534F), "p": Color(hex: 0xF7B7CF), "b": Color(hex: 0xC69C6D)])
        case .bun:
            return Sprite([".kkkkk.", "kdwddwk", "kddwddk", "kwdddwk", ".kkkkk."],
                          ["k": ink, "d": Color(hex: 0xC47A35), "w": Color(hex: 0xFFF6E5)])
        case .pie:
            return Sprite(["..kkkkk..", ".kcbcbck.", "kccccccck", "kdddddddk", ".kkkkkkk."],
                          ["k": ink, "c": Color(hex: 0xE8B66A), "b": Color(hex: 0x8E2E5A), "d": Color(hex: 0xC47A35)])
        case .cake:
            return Sprite(["...f.f...", "...k.k...", ".kwwwwwk.", ".kpppppk.", "kwwwwwwwk", "kpppppppk", "kkkkkkkkk"],
                          ["k": ink, "f": Color(hex: 0xF2C14E), "w": Color(hex: 0xFFF6E5), "p": Color(hex: 0xF49AC1)])
        }
    }
}

struct BakeryView: View {
    @Environment(VillageStore.self) private var store

    private static let specials = [
        "Today's special: warm cinnamon buns.",
        "Today's special: lemon cookies.",
        "Today's special: strawberry cupcakes.",
        "Today's special: honey croissants.",
        "Today's special: blueberry pie."
    ]

    var body: some View {
        let baked = store.treatsBaked
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VillagerHeader(villager: .rosie, place: "Bakery")

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(baked)")
                        .font(.pixel(40, .heavy))
                        .foregroundStyle(Color(hex: 0xC2577A))
                    Text("treats baked for you")
                        .font(.pixel(13, .heavy))
                        .foregroundStyle(Theme.ink)
                    Text("Rosie bakes one for every cup you finish at the café and every letter you deliver.")
                        .font(.pixel(12, .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.specials[day % Self.specials.count])
                        .font(.pixel(12, .heavy))
                        .foregroundStyle(Color(hex: 0xC2577A))
                        .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pixelBox(Theme.card)

                TreatJarCard()

                Text("THE DISPLAY CASE")
                    .font(.pixel(12))
                    .foregroundStyle(Theme.muted)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Treat.allCases, id: \.rawValue) { treat in
                        let unlocked = baked >= treat.unlockAt
                        VStack(spacing: 8) {
                            if unlocked {
                                SpriteView(sprite: treat.sprite, pixel: 4)
                                    .frame(height: 32)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Theme.muted)
                                    .frame(height: 32)
                            }
                            Text(unlocked ? treat.name : "\(treat.unlockAt) treats")
                                .font(.pixel(11, .heavy))
                                .foregroundStyle(unlocked ? Theme.ink : Theme.muted)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .pixelBox(unlocked ? Color(hex: 0xFFF1E6) : Theme.card, shadow: unlocked ? 3 : 1)
                        .accessibilityElement(children: .combine)
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
}

// MARK: - Town hall: this week

struct TownHallView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let week = store.week
        let maxTotal = max(week.map(\.total).max() ?? 0, 1)
        let letters = week.map(\.letters).reduce(0, +)
        let pages = week.map(\.pages).reduce(0, +)
        let habits = week.map(\.habits).reduce(0, +)
        let best = week.max { $0.total < $1.total }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TOWN HALL")
                            .font(.pixel(11))
                            .foregroundStyle(Theme.muted)
                        Text("This week in Workdoro")
                            .font(.pixel(22, .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                }

                // Pixel bar chart of the last seven days.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(week) { day in
                            VStack(spacing: 6) {
                                Text(day.total > 0 ? "\(day.total)" : "")
                                    .font(.pixel(10, .heavy))
                                    .foregroundStyle(Theme.ink)
                                let h = CGFloat(day.total) / CGFloat(maxTotal) * 110
                                VStack(spacing: 0) {
                                    Rectangle().fill(Theme.leaf).frame(height: h * CGFloat(day.habits) / CGFloat(max(day.total, 1)))
                                    Rectangle().fill(Theme.moPlum).frame(height: h * CGFloat(day.pages) / CGFloat(max(day.total, 1)))
                                    Rectangle().fill(Theme.pipBlue).frame(height: h * CGFloat(day.letters) / CGFloat(max(day.total, 1)))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: max(h, 4), alignment: .bottom)
                                .background(day.total == 0 ? Theme.empty : .clear)
                                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                                Text(day.label)
                                    .font(.pixel(11, .heavy))
                                    .foregroundStyle(day.id == VillageStore.dayKey() ? Theme.red : Theme.muted)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(day.label): \(count(day.letters, "letter")), \(count(day.pages, "page")), \(count(day.habits, "habit"))")
                        }
                    }
                    .frame(height: 150, alignment: .bottom)
                    HStack(spacing: 14) {
                        legend(Theme.pipBlue, "Letters")
                        legend(Theme.moPlum, "Pages")
                        legend(Theme.leaf, "Habits")
                    }
                }
                .padding(16)
                .pixelBox(Theme.card)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    stat("\(letters)", letters == 1 ? "letter delivered" : "letters delivered", Theme.pipBlue)
                    stat("\(pages)", pages == 1 ? "page written" : "pages written", Theme.moPlum)
                    stat("\(habits)", habits == 1 ? "habit kept" : "habits kept", Theme.leaf)
                    stat("\(store.focusMinutes)m", "focus at the café", Theme.beaOrange)
                    stat("\(store.streak)", "day streak", Theme.red)
                    stat("\(store.treatsBaked)", store.treatsBaked == 1 ? "treat baked" : "treats baked", Color(hex: 0xC2577A))
                }

                if let best, best.total > 0 {
                    Text("Best day this week: \(best.fullName), with \(best.total) things done. The mayor is impressed.")
                        .font(.pixel(13, .medium))
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .pixelBox(Color(hex: 0xFFFBEF))
                } else {
                    Text("A quiet week so far. Deliver a letter or plant a habit and the board fills up.")
                        .font(.pixel(13, .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(20)
            .padding(.top, 8)
        }
        .background(Theme.paper)
        .presentationDragIndicator(.visible)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(color).frame(width: 10, height: 10).overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
            Text(text).font(.pixel(10, .heavy)).foregroundStyle(Theme.muted)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.pixel(26, .heavy))
                .foregroundStyle(color)
            Text(label)
                .font(.pixel(11, .heavy))
                .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelBox(Theme.card)
        .accessibilityElement(children: .combine)
    }
}

/// What treats are for: a snack, a gift for a friend, or saving your streak.
struct TreatJarCard: View {
    @Environment(VillageStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR TREAT JAR")
                    .font(.pixel(11))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(store.treatsInJar) inside")
                    .font(.pixel(13, .heavy))
                    .foregroundStyle(Color(hex: 0xC2577A))
            }
            HStack(spacing: 4) {
                ForEach(0..<min(store.treatsInJar, 12), id: \.self) { i in
                    SpriteView(sprite: Treat.allCases[i % Treat.allCases.count].sprite, pixel: 2)
                }
                if store.treatsInJar > 12 { Text("+\(store.treatsInJar - 12)").font(.pixel(10, .heavy)).foregroundStyle(Theme.muted) }
            }
            .frame(minHeight: 16)

            if store.canSaveStreak {
                Button {
                    store.saveStreak()
                } label: {
                    Label("Missed yesterday? Save my streak · 3 treats", systemImage: "flame.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PixelButtonStyle(fill: Theme.red, foreground: Theme.cream))
            } else {
                Label("If you miss a day, come back here and spend 3 treats to keep your streak.", systemImage: "flame")
                    .font(.pixel(11, .medium))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("GIFT A TREAT")
                .font(.pixel(11))
                .foregroundStyle(Theme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(VillagerID.allCases) { v in
                        Button {
                            store.giftTreat(to: v)
                        } label: {
                            VStack(spacing: 4) {
                                SpriteView(sprite: v.sprite, pixel: 2.5)
                                Text(v.name).font(.pixel(10, .heavy)).foregroundStyle(Theme.ink)
                                HStack(spacing: 1) {
                                    ForEach(0..<5, id: \.self) { h in
                                        Image(systemName: h < store.hearts(v) ? "heart.fill" : "heart")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(Color(hex: 0xC2577A))
                                    }
                                }
                            }
                            .padding(8)
                            .pixelBox(Theme.card, shadow: 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Gift a treat to \(v.name)")
                    }
                }
                .padding(.bottom, 4)
            }

            Button {
                store.eatTreat()
            } label: {
                Label("Eat one", systemImage: "fork.knife").frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(fill: Color(hex: 0xC2577A), foreground: Theme.cream))
            .disabled(store.treatsInJar == 0)
        }
        .padding(16)
        .pixelBox(Theme.card)
    }
}
