import SwiftUI

/// Story scenes and little toasts float over whatever screen you're on.
struct VillageOverlays: ViewModifier {
    @Environment(VillageStore.self) private var store

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = store.toast, store.pendingEvent == nil {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                        .padding(.horizontal, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                }
            }
            .overlay {
                if let event = store.pendingEvent {
                    CutsceneView(event: event)
                        .id(event.id)
                        .transition(.opacity)
                }
            }
            .animation(.snappy, value: store.toast)
            .animation(.easeInOut(duration: 0.3), value: store.pendingEvent?.id)
            .task(id: store.toast?.id) {
                guard store.toast != nil else { return }
                try? await Task.sleep(for: .seconds(2.6))
                store.toast = nil
            }
            .sensoryFeedback(.success, trigger: store.lettersDelivered)
    }
}

extension View {
    func villageOverlays() -> some View {
        modifier(VillageOverlays())
    }
}

struct ToastView: View {
    let toast: VillageStore.Toast

    var body: some View {
        HStack(spacing: 10) {
            SpriteView(sprite: toast.speaker.sprite, pixel: 2.5)
            Text(toast.text)
                .font(.pixel(13, .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(10)
        .pixelBox(Theme.card)
    }
}

struct CutsceneView: View {
    @Environment(VillageStore.self) private var store
    let event: StoryEvent
    @State private var index = 0
    @State private var shown = 0

    private var line: Line { event.lines[index] }
    private var isTyping: Bool { shown < line.text.count }
    private var isLast: Bool { index == event.lines.count - 1 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            Button { store.finishEvent() } label: {
                Text("Skip ▸▸")
                    .font(.pixel(13, .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .pixelBox(Theme.card, shadow: 2)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityLabel("Skip the story")

            VStack(spacing: 16) {
                Text(event.title.uppercased())
                    .font(.pixel(13, .heavy))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .pixelBox(Theme.gold)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 12) {
                        if case .villager(let v) = line.speaker {
                            BobbingSprite(sprite: v.sprite, pixel: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(v.name)
                                    .font(.pixel(17, .heavy))
                                    .foregroundStyle(v.color)
                                Text(v.role.uppercased())
                                    .font(.pixel(10))
                                    .foregroundStyle(Theme.muted)
                            }
                        } else {
                            Text("~ Workdoro ~")
                                .font(.pixel(14, .heavy))
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    Text(line.text)
                        .font(.pixel(16, .semibold))
                        .foregroundStyle(.clear)
                        .overlay(alignment: .topLeading) {
                            Text(String(line.text.prefix(shown)))
                                .font(.pixel(16, .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(3)

                    HStack {
                        Text("\(index + 1)/\(event.lines.count)")
                            .font(.pixel(11))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text(isTyping ? " " : (isLast ? "close ▸" : "tap ▸"))
                            .font(.pixel(12, .heavy))
                            .foregroundStyle(Theme.ink)
                    }
                }
                .padding(18)
                .pixelBox(Theme.card)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(line.text)
        .accessibilityHint(isLast ? "Closes the scene" : "Shows the next line")
        .onChange(of: index, initial: true) {
            if line.text.contains("Ring ring") { SoundFX.shared.play(.bikeBell) }
        }
        .task(id: index) {
            // About 70 letters a second, measured by the clock so a busy screen can't slow it down.
            shown = 0
            let total = line.text.count
            let start = Date()
            while shown < total {
                try? await Task.sleep(for: .milliseconds(16))
                if Task.isCancelled { return }
                shown = min(total, Int(Date().timeIntervalSince(start) * 70) + 1)
            }
        }
    }

    private func advance() {
        SoundFX.shared.play(.page, volume: 0.6)
        if isTyping {
            shown = line.text.count
        } else if !isLast {
            index += 1
        } else {
            store.finishEvent()
        }
    }
}
