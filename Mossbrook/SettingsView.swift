import SwiftUI
import UserNotifications

enum AppInfo {
    /// Where "Contact support" sends email. Change this to your support address before launch.
    static let supportEmail = "smanraisingh@gmail.com"
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

struct SettingsView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false
    @State private var showPrivacy = false
    @AppStorage(SoundFX.enabledKey) private var tapSounds = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Notifications") {
                        row(icon: "bell.fill", title: "Reminders & alarms", detail: notificationText) {
                            if notifications == .notDetermined {
                                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                                    Task { await refresh() }
                                }
                            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }

                    section("Sound") {
                        Toggle(isOn: $tapSounds) {
                            HStack(spacing: 12) {
                                Image(systemName: tapSounds ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.gold.opacity(0.35))
                                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tap sounds").font(.pixel(14, .heavy)).foregroundStyle(Theme.ink)
                                    Text("Little chimes, pops and quacks").font(.pixel(11, .medium)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .tint(Theme.leaf)
                        .padding(12)
                        .pixelBox(Theme.card)
                        .onChange(of: tapSounds) { _, on in if on { SoundFX.shared.play(.toggle) } }
                    }

                    section("Town") {
                        row(icon: "map.fill", title: "Replay the town tour", detail: "Meet everyone again") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.replayTour() }
                        }
                    }

                    section("Your data") {
                        row(icon: "icloud.fill", title: "iCloud sync", detail: cloudText) {
                            CloudSync.shared.refresh()
                            if store.cloudStatus == .off, let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                rowLabel(icon: "square.and.arrow.up.fill", title: "Export my data", detail: "Tasks, notes, habits and focus time")
                            }
                            .buttonStyle(.plain)
                        }
                        row(icon: "trash.fill", title: "Delete all data", detail: "Start a brand-new town", danger: true) {
                            confirmDelete = true
                        }
                    }

                    section("About") {
                        row(icon: "hand.raised.fill", title: "Privacy policy", detail: "No tracking, nothing collected") {
                            showPrivacy = true
                        }
                        row(icon: "envelope.fill", title: "Contact support", detail: "Bugs, ideas, or just hi") {
                            let subject = "Workdoro \(AppInfo.version)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "mailto:\(AppInfo.supportEmail)?subject=\(subject)") { openURL(url) }
                        }
                        Text("Workdoro \(AppInfo.version) · made with care in your little town")
                            .font(.pixel(11, .medium))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.pixel(15, .heavy))
                }
            }
            .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
            .confirmationDialog("Delete everything?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive) { confirmDeleteAgain = true }
            } message: {
                Text("All your letters, notes, habits, focus time and progress will be removed from this iPhone. Export first if you want a copy.")
            }
            .alert("This can't be undone", isPresented: $confirmDeleteAgain) {
                Button("Delete", role: .destructive) {
                    store.deleteAllData()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your town will start fresh.")
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await refresh() } } }
    }

    private var cloudText: String {
        switch store.cloudStatus {
        case .off: "Sign in to iCloud to back up your town"
        case .starting: "Connecting…"
        case .failed: "Couldn't sync · tap to retry"
        case .synced(let at): "On · synced \(at.formatted(.relative(presentation: .named)))"
        }
    }

    private var notificationText: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "On · tap to change"
        case .denied: "Off · tap to turn on in Settings"
        default: "Tap to turn on"
        }
    }

    private func refresh() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        exportURL = store.exportFile()
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.pixel(11, .heavy)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func row(icon: String, title: String, detail: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon: icon, title: title, detail: detail, danger: danger) }
            .buttonStyle(.plain)
    }

    private func rowLabel(icon: String, title: String, detail: String, danger: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(danger ? Theme.red : Theme.ink)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.pixel(15, .heavy)).foregroundStyle(danger ? Theme.red : Theme.ink)
                Text(detail).font(.pixel(11, .medium)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .pixelBox(Theme.card)
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(PrivacyPolicy.text)
                    .font(.pixel(13, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper)
            .navigationTitle("Privacy policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

enum PrivacyPolicy {
    static let text = """
    Last updated: 6 November 2026

    Workdoro is built to keep your things private. In short: your things stay on your devices and in your own iCloud, and we never see them.

    What the app stores
    Your tasks (letters), notes, drawings, photos you add to notes, habits, focus sessions and town progress are saved on your device. If you are signed in to iCloud, a copy is also kept in your own private iCloud Drive so your town appears on your other devices; only you can access it. Your widgets read a small summary of them so they can show your day.

    What we collect
    Nothing. Workdoro has no account, no analytics, no ads and no tracking. It does not send your data to us or to anyone else.

    Notifications
    If you allow notifications, Workdoro schedules reminders and focus alarms on your device. They are never sent through a server.

    Photos
    When you add a photo to a note, only that photo is copied into the app. Workdoro cannot see the rest of your library.

    Your control
    You can export all your data or delete it at any time in Settings. Delete all data also removes the iCloud copy. You can turn off iCloud for Workdoro in your iPhone Settings at any time.

    Children
    Workdoro does not knowingly collect any information from anyone, including children.

    Changes
    If this policy ever changes, the new version will appear here in the app.

    Contact
    Questions? Write to \(AppInfo.supportEmail).
    """
}
