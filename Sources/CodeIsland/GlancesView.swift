import SwiftUI
import AppKit

/// Glances surface — weather, next meeting (+ one-tap join), and reminders.
/// Styled to match the notch panel: monospaced type, green accent, dark chrome.
struct GlancesView: View {
    @StateObject private var model = GlancesModel()

    private static let accent = Color(red: 0.3, green: 0.85, blue: 0.4)
    private static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
    private static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            weatherRow
            Divider().overlay(Color.white.opacity(0.08))
            meetingSection
            Divider().overlay(Color.white.opacity(0.08))
            remindersSection
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.refresh() }
    }

    // MARK: - Weather

    private var weatherRow: some View {
        HStack(spacing: 10) {
            if let weather = model.weather {
                Image(systemName: weather.symbolName)
                    .font(.system(size: 22))
                    .foregroundStyle(Self.accent)
                    .symbolRenderingMode(.hierarchical)
                Text("\(weather.temperatureF)°")
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.summary)
                        .font(Self.monoSmall)
                        .foregroundStyle(.white.opacity(0.55))
                    if let label = model.weatherLocationLabel {
                        Text(label)
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(1)
                    }
                }
                Spacer()
                settingsButton(label: "Weather settings")
            } else {
                Image(systemName: "location.slash")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.3))
                Text(model.statusLine ?? "Weather unavailable")
                    .font(Self.monoSmall)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                settingsButton(label: "Weather settings")
            }
        }
    }

    // MARK: - Next meeting

    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("NEXT MEETING")
            if let event = model.nextEvent {
                Text(event.title)
                    .font(Self.mono)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(Self.timeText(for: event))
                        .font(Self.monoSmall)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    if let url = event.joinURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Text("JOIN")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Rectangle().fill(Self.accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if model.calendarAuthorized {
                emptyText("Nothing on the calendar")
            } else {
                HStack {
                    emptyText("Calendar access needed")
                    Spacer()
                    settingsButton(label: "Calendar settings")
                }
            }
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("REMINDERS")
                Spacer()
                settingsButton(label: "Choose Reminders lists")
            }
            if !model.reminders.isEmpty {
                ForEach(model.reminders) { reminder in
                    HStack(spacing: 8) {
                        Button {
                            model.complete(reminder)
                        } label: {
                            Image(systemName: "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Self.accent.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        Text(reminder.title)
                            .font(Self.monoSmall)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                        if let due = reminder.due {
                            Text(Self.dueText(due))
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            } else if model.remindersAuthorized {
                emptyText("All clear in selected lists")
            } else {
                emptyText("Reminders access needed")
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.35))
            .tracking(1.5)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(Self.monoSmall)
            .foregroundStyle(.white.opacity(0.4))
    }

    private func settingsButton(label: String) -> some View {
        Button {
            SettingsWindowController.shared.show(page: .glances)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Self.accent.opacity(0.8))
                .padding(3)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private static func timeText(for event: GlancesModel.EventInfo) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        let start = formatter.string(from: event.start)
        let delta = event.start.timeIntervalSinceNow
        if delta > 0, delta < 3600 {
            return "in \(Int((delta / 60).rounded())) min · \(start)"
        }
        return start
    }

    private static func dueText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

/// Segmented toggle shown atop the session-list surface: Sessions vs Glances.
struct GlancesToggleRow: View {
    @Binding var showGlances: Bool

    private static let accent = Color(red: 0.3, green: 0.85, blue: 0.4)

    var body: some View {
        HStack(spacing: 1) {
            tab(label: "SESSIONS", active: !showGlances) { showGlances = false }
            tab(label: "GLANCES", active: showGlances) { showGlances = true }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func tab(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(active ? Self.accent : .white.opacity(0.3))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Rectangle().fill(active ? Color.white.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
    }
}
