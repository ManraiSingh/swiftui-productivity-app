# Workdoro

A SwiftUI productivity app set in a sleepy pixel-art town that wakes up as you get things done.

Every building is a tool, and every tool has a villager who runs it. Tasks become letters for Pip the postman, notes become pages of Mo's book, focus time is spent at Bea's café, and habits grow into plants in Juniper's greenhouse. Finishing things fixes Pip's bike, fills Mo's book, brings regulars into the café and makes the garden bloom. There are no accounts and no servers: everything stays on the phone and in the user's own iCloud.

Coming soon to the App Store.

---

## Features

**The town**
The whole town is drawn in code on a SwiftUI `Canvas` from a 384 × 348 pixel grid, with no image assets. It runs through day, dusk and night with the real clock, changes with the seasons, and rolls its own weather each day. At night shop windows and lamp posts glow, fireflies come out over the woods, and villagers are redrawn above the lighting so they never sit in shadow. Ducks quack when tapped, trees drop apples, and a balloon drifts over now and then.

The map sits in a native `UIScrollView` for pinch zoom and panning. It snaps to whole-pixel zoom levels when a gesture ends, so the art never blurs, and the host view is re-framed to the zoom container on every frame so the drawing stays sharp at any scale.

**Post office (tasks)**
Tasks are typed the way people say them. "call mom fri 6pm" becomes a letter due Friday at six, and "gym every monday 7am" becomes a weekly repeat. The parser handles weekdays, relative days, times and repeat rules: daily, every weekday, weekly and monthly. Delivering a repeating letter creates the next copy straight away. Undelivering takes that copy back, and a quick double tap is ignored so next week's letter isn't ticked by accident. Every letter delivered finds a piece of Pip's broken bike.

**Library (notes)**
A block-based editor with text, headings, checklists, bullets, numbered lists, quotes, dividers and photos, set on lined, grid, dotted or plain paper in six tints. Beside the writing there are PencilKit pens, sticky notes and shapes, each on its own layer. A note can have as many pages as it needs, each with its own writing, drawing, stickies and shapes, flipped with a slide. Templates cover to-dos, journals, meetings and brainstorms. Notes can be pinned, filed in folders and searched across every page. Saving waits until typing pauses, because a save rewrites the whole notebook.

**Café (focus)**
Order a drink from Bea and pick a seat beside the regulars. Tea is 15 minutes, espresso 25 and latte 50, or set any work length, break length and number of rounds. During breaks the café can be wandered and the regulars chatted to. The end of every block and break is scheduled as a time-sensitive notification with its own chime, so the alarm rings even when the app is closed. A Live Activity and the Dynamic Island show the countdown on the Lock Screen.

**Strict mode**
The screen turns sideways into a quiet desk scene: a rainy window, a bookshelf, a large pixel clock and a sleeping cat. The character works on a laptop or reads a book, chosen from a hand-drawn dropdown (a system menu would open sideways, because only the scene is rotated). Lo-fi music plays, synthesised in real time on the audio thread so there is no recording to license. Workdoro's own notifications wait silently in Notification Center, the screen stays awake, and leaving early means holding a button. Stepping away and coming back is noticed, and the session carries on. The first visit shows a short introduction.

**Greenhouse (habits)**
Each habit grows into one of six plant species, through seven stages from seed to flourishing. Missing a day never undoes growth. A habit can be watered by hand or automatically when a café cup is finished, a page is written or a letter is delivered. Each plant has a history with current and best streaks, total days, this month's percentage and a Monday-first calendar where a forgotten past day can be filled in.

**Bakery and town hall**
Every finished cup and delivered letter bakes a treat. Treats can be eaten on a break, gifted to a villager to raise their hearts, or spent three at a time to save a broken streak. The town hall shows the week as a stacked chart of letters, pages and habits, alongside totals and the best day.

**iPad**
On iPad the whole town fits the screen and stays centred when the iPad turns. The café and greenhouse fill the screen edge to edge, carrying their walls, floor, lights and counter on past the original room. Strict mode keeps the phone's layout along the bottom with more cosy wall above, and shows the desk as it is when the iPad is already held sideways. Shop cards open centred instead of stretching.

**Guided tour**
The first launch starts zoomed out over the whole town and glides in to each villager in turn. A circular spotlight and a card with a pointer explain each one. Villagers stand still during the tour so the spotlight never chases a moving target.

**Widgets**
Small, medium and large Home Screen widgets show the town at the current time of day, today's letters and habit streaks. Letters can be ticked off from the widget itself through an App Intent, without opening the app. During a focus session the widgets switch to the desk scene with a live countdown. There are Lock Screen widgets too, and the widget sky follows any time of day picked in the app.

**iCloud sync**
The town is mirrored to the user's own iCloud Drive and merged item by item, rather than one copy overwriting the other. Two phones can each add letters, edit different notes and water habits, and both sets of changes survive. Deletions are kept as dated tombstones so a deleted note never comes back from an older copy.

---

## Performance

The world is about 384 × 348 art pixels, and drawing it rect by rect meant almost 50,000 fills on every frame. Everything that never moves (hills, grass, paths, the square and the dense forest) is now drawn once into a `CGImage` for each combination of time of day, weather and season. It is shown with nearest-neighbour scaling, which keeps pixel art perfect at any zoom without a redraw. Only things that move are drawn each frame. This took the idle town screen from about 34% of a CPU core to about 10%.

The town and sky pause their timelines whenever the café, greenhouse or a shop covers them. Translucent tints are filled as a single path rather than overlapping columns, which removes faint vertical seams at night. Ink in the notes editor is drawn in global coordinates under a high-priority gesture, so dragging stays smooth.

---

## Tech stack

| Area | Technology |
|------|------------|
| UI | SwiftUI, SwiftUI `Canvas`, `ImageRenderer` |
| Map | `UIScrollView` through `UIViewRepresentable`, `CADisplayLink` |
| Pixel art | Text-grid sprites rendered by a small `Painter` |
| State | Observation (`@Observable`) with one `VillageStore` |
| Persistence | JSON in the app's Documents folder, written atomically, with a verified backup |
| Sync | iCloud Drive ubiquity container, `NSMetadataQuery`, `NSFileCoordinator` |
| Drawing | PencilKit |
| Audio | `AVAudioEngine` with an `AVAudioSourceNode` synthesiser |
| Widgets | WidgetKit, App Intents, App Groups |
| Live Activity | ActivityKit, Dynamic Island |
| Notifications | UserNotifications, time-sensitive, with a custom sound |
| Photos | PhotosUI |
| Architecture | A single observable store, with renderers and views kept separate |

---

## Architecture

```
Views (SwiftUI)
   |  observe
   v
VillageStore                letters, pages, habits, focus, story, streaks, saving
   |
   +- CloudSync              iCloud Drive mirror and item-by-item merge
   +- LiveFocus              Live Activity and widget snapshot
   +- QuietNotifications     keeps alarms silent during strict mode
   +- LofiPlayer             real-time lo-fi synthesiser
   +- Story                  villager events and chatter

Renderers (pure drawing, no state)
   +- VillageRenderer        town, buildings, lights, villagers
   +- WildsRenderer          forest, trails, fireflies
   +- TownRenderer           square, market, farm
   +- CafeRenderer           café floor, regulars, seats
   +- StrictRenderer         the sideways desk
   +- PlantRenderer          six species through seven stages
```

`WidgetSnapshot`, the sprites and the theme are compiled into both the app and the widget extension, so the town looks the same in both.

### Data model

Everything is saved in one file, so a save is always complete or not done at all:

```
mossbrook.json
├─ letters[]          title, due, done, repeats, nextID
├─ pages[]            title, blocks, drawing, stickies, shapes, moreSheets[]
├─ habits[]           name, species, doneDays[], auto-watering
├─ activeFocus        drink, start, work and break lengths, round
├─ focusMinutes, focusSessions, activeDays[], treatsSpent, friendship
├─ seenEvents[]       which story moments have played
└─ deleted{}          tombstones for iCloud, by id and date
```

### Project structure

```
├─ Mossbrook/           App: store, models, town, café, library, post office,
│                       greenhouse, bakery, town hall, strict mode, tour,
│                       settings, iCloud sync, music, renderers
├─ MossbrookWidgets/    Widget extension and Live Activity
├─ Shared/              Pixel art, theme, plants, widget views and snapshot,
│                       the deliver-letter App Intent
└─ docs/                Privacy policy, support and terms pages
```

The folders and targets keep the working title *Mossbrook*. Everything a user sees says Workdoro.

---

## Privacy

Workdoro makes no network requests of its own. There is no account, no analytics, no ads and no tracking, and the privacy manifests declare that no data is collected. The only data that leaves the phone goes to the user's own iCloud Drive, which Apple does not count as collection.

The save file is never overwritten when it can't be read. A copy that loaded correctly is kept as a backup on every launch. If the main file is ever damaged, it is set aside and the town is restored from that backup. Delete all data removes the save file, the backups, photos in notes, the iCloud copy and every pending notification.

### Testing

A debug-only self-test checks the iCloud merge, deletion tombstones, the natural-language repeat parser and multi-page notes. Launch the app with `-mergeSelfTest` and filter the console for `MERGETEST`. All 18 checks should pass.

---

## Getting started

### Requirements

- Xcode 26 or later
- iOS 18 or later, iPhone and iPad

### Setup

1. Clone the repository and open `Mossbrook.xcodeproj`.
2. Set your own Development Team on the **Mossbrook** and **MossbrookWidgets** targets.
3. Change the bundle identifiers if `com.manraisingh.workdoro` isn't yours, then update the App Group (`group.com.manraisingh.workdoro`) on both targets and the iCloud container (`iCloud.com.manraisingh.workdoro`) on the app to match.
4. Run the **Mossbrook** scheme. No backend or keys are needed.

---

## Roadmap

- An Apple Watch app for ticking letters, starting a café cup and watering habits from the wrist, with watch face complications
- More strict mode activities, drawn to the same standard as reading
- Workdoro Plus: an optional one-time purchase for café themes, town decorations, extra plant species and more music
- Unit test coverage for the date parser, streaks and repeat rules, moving out of the debug self-test

---

## Licence

All rights reserved. This repository is public for reference; the app and its assets are not licensed for redistribution.
