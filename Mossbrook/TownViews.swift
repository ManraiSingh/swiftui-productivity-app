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
