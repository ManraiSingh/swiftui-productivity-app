# Workdoro

**Your tiny town of productivity.** A cozy pixel-art iPhone app where every building in town is a tool, and every tool has a friend who runs it.

| Place | Villager | What it does |
|---|---|---|
| Post office | Pip | Tasks as letters, with natural dates ("call mom fri 6pm") and repeats ("every monday") |
| Library | Mo | Notes with pages, pens, stickies, shapes, photos, checklists and templates |
| Café | Bea | Focus timer (Tea 15, Espresso 25, Latte 50, or your own) with breaks, rounds, lo-fi music and strict mode |
| Greenhouse | Juniper | Habits that grow into plants, with streaks and a history calendar |
| Bakery | Rosie | Treats earned by focusing, to gift or to save a streak |
| Town hall | | A weekly report |

There are also home and lock screen widgets, a Live Activity, iCloud sync, a guided tour, day/dusk/night and seasons.

## Project layout
| Folder | Contents |
|---|---|
| `Mossbrook/` | The iPhone app (SwiftUI). `VillageStore.swift` holds all the app's data and saving. |
| `MossbrookWidgets/` | Widget extension and Live Activity |
| `Shared/` | Pixel art, theme and widget code used by both |
| `AppStore/` | Listing text, screenshots, raw captures and `Ready to publish/PUBLISH.md` |
| `privacy.html` | Privacy policy page |
| `Music previews/` | Samples of the in-app lo-fi tracks (the app makes its music in code; these are only for listening) |

The folder and target names still say *Mossbrook*, the app's working title. The app itself is named Workdoro everywhere a user can see.

## Building
- Xcode 26, iOS 18 or newer, iPhone only.
- Open `Mossbrook.xcodeproj`, pick the **Mossbrook** scheme and run.
- Bundle IDs: `com.manraisingh.workdoro` and `com.manraisingh.workdoro.widgets`.
- App group: `group.com.manraisingh.workdoro`. iCloud container: `iCloud.com.manraisingh.workdoro`.
- Debug self-tests: run with the launch argument `-mergeSelfTest` and look for `MERGETEST` in the console.

## Publishing
See [`AppStore/Ready to publish/PUBLISH.md`](AppStore/Ready%20to%20publish/PUBLISH.md).

© 2026 Manraisingh. All rights reserved.
