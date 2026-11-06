import Foundation

enum Speaker: Equatable {
    case narrator
    case villager(VillagerID)
}

struct Line {
    let speaker: Speaker
    let text: String

    static func pip(_ text: String) -> Line { Line(speaker: .villager(.pip), text: text) }
    static func mo(_ text: String) -> Line { Line(speaker: .villager(.mo), text: text) }
    static func narrator(_ text: String) -> Line { Line(speaker: .narrator, text: text) }
    static func villager(_ v: VillagerID, _ text: String) -> Line { Line(speaker: .villager(v), text: text) }
}

struct StoryEvent: Identifiable {
    let id: String
    let title: String
    let lines: [Line]
    let isReady: (VillageStore) -> Bool
}

enum Story {
    static let events: [StoryEvent] = [
        StoryEvent(
            id: "intro",
            title: "Welcome to Workdoro",
            lines: [
                .narrator("The last train of the evening lets you off at a sleepy little village called Workdoro."),
                .pip("Oh! A new face! Hi, I'm Pip, the postman."),
                .mo("And I'm Mo, from the library. The whole town has been fast asleep for years."),
                .pip("Everything you get done helps Workdoro wake up. Come on, we'll show you around!")
            ],
            isReady: { _ in true }
        ),
        StoryEvent(
            id: "bea-intro",
            title: "Meet Bea",
            lines: [
                .narrator("Down the lane, past the garden, a little café sits dark and dusty."),
                .villager(.bea, "Oh! Hello! I'm Bea. This used to be the coziest café in the valley."),
                .villager(.bea, "Nobody's sat down for a cup in years. Come in, pick one thing to work on, and I'll make you a drink."),
                .narrator("Tap the café to start a focus session. Every cup you finish brings it back to life.")
            ],
            isReady: { $0.tourDone }
        ),
        StoryEvent(
            id: "pip-1",
            title: "Chapter 1 · A wheel!",
            lines: [
                .pip("You did it! And look what turned up behind the mailbox... my front wheel!"),
                .pip("Five more parts. With your help, I'll be riding again by the end of the season.")
            ],
            isReady: { $0.bikeParts >= 1 }
        ),
        StoryEvent(
            id: "mo-1",
            title: "Chapter 1 · The first page",
            lines: [
                .mo("Oh... is this a page? A real page!"),
                .mo("The library already feels warmer. Look, the windows are glowing again.")
            ],
            isReady: { $0.pagesFound >= 1 }
        ),
        StoryEvent(
            id: "pip-3",
            title: "Chapter 2 · Halfway there",
            lines: [
                .pip("Two wheels and a chain! It's starting to look like a bike again."),
                .mo("Pip's been whistling all morning. I haven't heard that in years.")
            ],
            isReady: { $0.bikeParts >= 3 }
        ),
        StoryEvent(
            id: "mo-5",
            title: "Chapter 2 · It's coming back",
            lines: [
                .mo("Five pages! I remember now. My book was about a village that fell asleep... and someone who woke it up."),
                .mo("Funny. That sounds a bit like you.")
            ],
            isReady: { $0.pagesFound >= 5 }
        ),
        StoryEvent(
            id: "pip-6",
            title: "Chapter 3 · Back on the road",
            lines: [
                .pip("The bell! That was the last piece! Listen..."),
                .narrator("Ring ring. For the first time in years, a bicycle bell echoes across Workdoro."),
                .pip("Now I can ride the whole town again. Every street in Workdoro gets its letters!")
            ],
            isReady: { $0.bikeFixed }
        ),
        StoryEvent(
            id: "mo-10",
            title: "Chapter 3 · Reading night",
            lines: [
                .mo("Ten pages. My book is finished. I don't know how to thank you."),
                .mo("Tonight there are lanterns on the library. Everyone's invited to reading night.")
            ],
            isReady: { $0.bookDone }
        ),
        StoryEvent(
            id: "bea-1",
            title: "Café · The first cup",
            lines: [
                .villager(.bea, "Look at that, the kettle still works! And someone actually stayed until the last sip."),
                .villager(.bea, "I'm turning the sign around. Workdoro Café is officially OPEN.")
            ],
            isReady: { $0.cafeLevel >= 1 }
        ),
        StoryEvent(
            id: "bea-100",
            title: "Café · Regulars",
            lines: [
                .pip("I hear this is the spot for getting things done."),
                .mo("We'll take the corner table. Quiet working only!"),
                .villager(.bea, "Regulars! I have regulars! I'm putting tables outside.")
            ],
            isReady: { $0.cafeLevel >= 2 }
        ),
        StoryEvent(
            id: "bea-300",
            title: "Café · Full house",
            lines: [
                .villager(.bea, "Flowers in every window... and a cat has decided he lives here now."),
                .villager(.bea, "Thank you for every cup. This place is alive again because of you.")
            ],
            isReady: { $0.cafeLevel >= 3 }
        ),
        StoryEvent(
            id: "season-1",
            title: "Season 1 complete",
            lines: [
                .narrator("Pip is riding again. The library is glowing. The café is full. Workdoro is awake."),
                .pip("Hey... have you noticed the clock tower? It hasn't moved in years."),
                .mo("Old Tock lives up there. He hasn't come down since it stopped. Maybe next season we'll find out why."),
                .narrator("Season 2 · The Silent Clock. Coming soon.")
            ],
            isReady: { $0.bikeFixed && $0.bookDone && $0.cafeLevel >= 3 }
        )
    ]
}

/// The little lines villagers say in their speech bubbles.
enum Chatter {
    static func lines(for villager: VillagerID, _ store: VillageStore) -> [String] {
        if store.isFocusing && villager == .bea {
            return ["Your drink is still warm.", "One thing at a time."]
        }
        switch villager {
        case .juniper:
            if store.habits.isEmpty { return ["The greenhouse is so empty...", "Plant a habit with me?", "Small things, every day."] }
            let left = store.habits.count - store.habitsDoneToday
            return left == 0
                ? ["Everything's watered!", "Look how they've grown!", "Same time tomorrow?"]
                : ["\(left) plant\(left == 1 ? "" : "s") still thirsty.", "Habits are like seeds.", "Water a little every day."]
        case .rosie:
            let treats = store.treatsBaked
            return treats == 0
                ? ["Ovens are warm!", "Finish a cup, earn a treat!", "Smells like cinnamon."]
                : ["\(count(treats, "treat")) baked for you!", "Fresh croissants!", "Every cup earns a treat."]
        case .bea:
            switch store.cafeLevel {
            case 0: return ["This place used to be so cozy...", "Stay for a cup?", "Pick one thing. Just one."]
            case 3: return ["Full house today!", "The cat says hi.", "Best café in the valley!"]
            default:
                let left = max(0, VillageStore.cafeGoal - store.focusMinutes)
                return ["Kettle's on!", "\(count(left, "minute")) to a full house!", "One cup, one task."]
            }
        case .pip:
            let open = store.openLetters.count
            var lines: [String]
            if store.bikeFixed {
                lines = ["My bike is fixed!", "Special delivery!", "Fastest postman in town!"]
            } else if store.bikeParts == 0 {
                lines = ["My bike's in pieces...", "Every letter helps me find a part!", "Anything that needs doing?"]
            } else {
                let left = VillageStore.bikeGoal - store.bikeParts
                lines = ["\(left) more part\(left == 1 ? "" : "s") to go!", "Found my \(BikePart(rawValue: store.bikeParts)?.name ?? "part")!", "Thanks for the help!"]
            }
            if open > 0 { lines.append("\(open) letter\(open == 1 ? "" : "s") waiting!") }
            return lines
        case .mo:
            if store.bookDone {
                return ["My book is finished!", "Reading night tonight!", "Thank you, truly."]
            } else if store.pagesFound == 0 {
                return ["The wind took my pages...", "Write me anything!", "It's so quiet in here."]
            } else {
                let left = VillageStore.bookGoal - store.pagesFound
                return ["\(left) page\(left == 1 ? "" : "s") to go!", "Page \(store.pagesFound)... lovely.", "Your notes are wonderful."]
            }
        }
    }

    static func line(for villager: VillagerID, _ store: VillageStore, t: Double) -> String {
        let all = lines(for: villager, store)
        return all[Int(t / 5) % all.count]
    }
}
