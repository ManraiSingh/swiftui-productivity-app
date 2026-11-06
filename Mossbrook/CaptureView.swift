import SwiftUI

enum Capture {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    private static let taskWords = [
        "buy", "call", "email", "text", "pay", "send", "book", "finish", "submit", "remind", "clean",
        "fix", "pick up", "meet", "todo", "to do", "return", "renew", "cancel", "order", "study", "workout",
        "go to", "get", "make", "do "
    ]

    /// Pulls a repeat out of the text, like "gym every monday 7am" or "water plants daily".
    /// Returns the text with the repeat words removed (keeping a weekday so the date can still be read).
    static func repeatRule(_ text: String) -> (text: String, rule: RepeatRule?) {
        let days = "monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun"
        let patterns: [(String, RepeatRule, Bool)] = [
            ("\\bevery\\s+(\(days))\\b", .weekly, true),
            ("\\b(every\\s+weekday|on\\s+weekdays|weekdays)\\b", .weekdays, false),
            ("\\b(every\\s+day|everyday|daily|every\\s+morning|every\\s+night|every\\s+evening)\\b", .daily, false),
            ("\\b(every\\s+week|weekly)\\b", .weekly, false),
            ("\\b(every\\s+month|monthly)\\b", .monthly, false)
        ]
        for (pattern, rule, keepDay) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range, in: text) else { continue }
            var out = text
            if keepDay, let dr = Range(m.range(at: 1), in: text) {
                out.replaceSubrange(r, with: String(text[dr]))   // "every monday" -> "monday"
            } else {
                // Keep "morning/night/evening" as a time hint.
                let word = text[r].lowercased()
                let hint = word.hasSuffix("morning") ? "9am" : (word.hasSuffix("night") || word.hasSuffix("evening") ? "8pm" : "")
                out.replaceSubrange(r, with: hint)
            }
            return (out.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces), rule)
        }
        return (text, nil)
    }

    /// Pulls a date and repeat out of the text, like "call mom every friday 6pm".
    static func parse(_ text: String) -> (title: String, due: Date?, repeats: RepeatRule?) {
        let (rest, rule) = repeatRule(text)
        let p = parseDate(rest)
        return (p.title, p.due, rule)
    }

    /// Pulls a date out of the text, like "call mom friday 6pm".
    static func parseDate(_ text: String) -> (title: String, due: Date?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector,
              let match = detector.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let date = match.date,
              let range = Range(match.range, in: trimmed) else {
            return (trimmed, nil)
        }
        var title = trimmed
        title.removeSubrange(range)
        title = title.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for suffix in [" at", " on", " by", " for"] where title.lowercased().hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }
        return (title.isEmpty ? trimmed : title, date)
    }

    static func suggest(_ text: String) -> VillagerID {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.isEmpty { return .pip }
        let p = parse(text)
        if p.due != nil || p.repeats != nil { return .pip }
        if lower.count > 90 || lower.contains("\n") { return .mo }
        if taskWords.contains(where: { lower.hasPrefix($0) || lower.contains(" \($0) ") }) { return .pip }
        return .mo
    }
}

struct CaptureView: View {
    @Environment(VillageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var target: VillagerID = .pip
    @State private var picked = false
    @FocusState private var focused: Bool

    private var parsed: (title: String, due: Date?, repeats: RepeatRule?) { Capture.parse(text) }
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What's on your mind?")
                .font(.pixel(20, .heavy))
                .foregroundStyle(Theme.ink)

            TextField("call mom friday 6pm · an idea for my app…", text: $text, axis: .vertical)
                .font(.pixel(16, .medium))
                .lineLimit(2...5)
                .focused($focused)
                .padding(14)
                .pixelBox(Theme.card)

            Text("WHO SHOULD TAKE IT?")
                .font(.pixel(11))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 14) {
                choice(.pip, title: "A letter", detail: [parsed.repeats?.label, parsed.due.map { DueFormat.text($0) }].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "a task to do")
                choice(.mo, title: "A page", detail: "a note to keep")
            }

            Button {
                save()
            } label: {
                Text(target == .pip ? "Give to Pip" : "Give to Mo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PixelButtonStyle(fill: target.color, foreground: Theme.cream))
            .disabled(isEmpty)
            .opacity(isEmpty ? 0.5 : 1)
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
        .presentationDetents([.height(420), .large])
        .presentationDragIndicator(.visible)
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            focused = true
        }
        .onChange(of: text) {
            if !picked { withAnimation(.snappy) { target = Capture.suggest(text) } }
        }
    }

    private func choice(_ villager: VillagerID, title: String, detail: String) -> some View {
        let selected = target == villager
        return Button {
            picked = true
            withAnimation(.snappy) { target = villager }
        } label: {
            HStack(spacing: 10) {
                SpriteView(sprite: villager.sprite, pixel: 2.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.pixel(14, .heavy))
                        .foregroundStyle(selected ? villager.color : Theme.ink)
                    Text(detail)
                        .font(.pixel(10, .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64)
            .pixelBox(selected ? Color(hex: 0xFFF1C9) : Theme.card, shadow: selected ? 3 : 1)
            .offset(x: selected ? 0 : 2, y: selected ? 0 : 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        guard !isEmpty else { return }
        if target == .pip {
            store.addLetter(parsed.title, due: parsed.due, repeats: parsed.repeats)
        } else {
            store.addPage(text)
        }
        dismiss()
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
