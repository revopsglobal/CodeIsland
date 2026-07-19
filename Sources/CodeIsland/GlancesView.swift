import SwiftUI
import AppKit
import CoreLocation
import EventKit

/// Glances surface — weather, next meeting (+ one-tap join), and reminders.
/// Styled to match the notch panel: monospaced type, green accent, dark chrome.
struct GlancesView: View {
    @StateObject private var model = GlancesModel.shared
    @ObservedObject private var personalUtilities = PersonalUtilitiesModel.shared
    @State private var isAddingReminder = false
    @State private var newReminderTitle = ""
    @State private var calendarReferenceDate = Date()
    @State private var calendarSelectedDate = Date()
    @State private var calendarMonthInfo: GlancesModel.CalendarMonthInfo?
    @AppStorage(SettingsKey.glancesWeatherLocation)
    private var weatherLocation = SettingsDefaults.glancesWeatherLocation
    @FocusState private var reminderFieldFocused: Bool

    private static let accent = Color(red: 0.3, green: 0.85, blue: 0.4)
    private static let actionAccent = Color(red: 1.0, green: 0.69, blue: 0.0)
    private static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
    private static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                weatherRow
                if !personalUtilities.downloads.isEmpty || personalUtilities.recentDownloadCompleted != nil {
                    Divider().overlay(Color.white.opacity(0.08))
                    downloadsSection
                }
                Divider().overlay(Color.white.opacity(0.08))
                meetingSection
                if model.calendarAuthorized, let calendarMonthInfo {
                    Divider().overlay(Color.white.opacity(0.08))
                    calendarMonthSection(calendarMonthInfo)
                }
                if !personalUtilities.deviceBatteries.isEmpty {
                    Divider().overlay(Color.white.opacity(0.08))
                    devicesSection
                }
                Divider().overlay(Color.white.opacity(0.08))
                remindersSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: 560)
        .onAppear {
            model.refresh()
            refreshCalendarMonth()
            personalUtilities.start()
        }
        .onReceive(model.$upcomingEvents) { _ in refreshCalendarMonth() }
    }

    private func calendarMonthSection(_ info: GlancesModel.CalendarMonthInfo) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("CALENDAR")
            MacCalendarMonthView(month: info.month) { referenceDate, selectedDate in
                calendarReferenceDate = referenceDate
                calendarSelectedDate = selectedDate
                refreshCalendarMonth()
            }

            if info.selectedEvents.isEmpty {
                emptyText("No events on the selected day")
            } else {
                ForEach(info.selectedEvents, id: \.id) { event in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title)
                                .font(Self.monoSmall.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                            Text(Self.timeText(for: event))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.34))
                        }
                        Spacer(minLength: 4)
                        if let url = event.joinURL {
                            Button("JOIN") { NSWorkspace.shared.open(url) }
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .buttonStyle(.borderedProminent)
                                .tint(Self.actionAccent)
                                .controlSize(.mini)
                                .accessibilityLabel("Join \(event.title)")
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    private func refreshCalendarMonth() {
        guard model.calendarAuthorized else {
            calendarMonthInfo = nil
            return
        }
        calendarMonthInfo = model.calendarMonth(
            referenceDate: calendarReferenceDate,
            selectedDate: calendarSelectedDate
        )
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
                if let action = weatherRecoveryAction {
                    miniActionButton(action.title, action: action.perform)
                }
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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Self.actionAccent)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Join \(event.title)")
                        .accessibilityLabel("Join \(event.title)")
                    }
                }
            } else if model.calendarAuthorized {
                emptyText("Nothing on the calendar")
            } else {
                HStack {
                    emptyText("Calendar access needed")
                    Spacer()
                    miniActionButton(calendarRecoveryTitle, action: performCalendarRecovery)
                    settingsButton(label: "Calendar settings")
                }
            }
        }
    }

    // MARK: - Downloads

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionLabel("DOWNLOADS")
                Spacer()
                Button { personalUtilities.openDownloads() } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Self.accent.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Open Downloads")
            }

            ForEach(personalUtilities.downloads.prefix(3)) { download in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: download.isStalled ? "pause.circle" : "arrow.down.circle.fill")
                            .foregroundStyle(download.isStalled ? .white.opacity(0.35) : Self.accent)
                        Text(download.name)
                            .font(Self.monoSmall)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                        Text(downloadStatus(download))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    if let progress = download.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(Self.accent)
                            .scaleEffect(x: 1, y: 0.65, anchor: .center)
                    }
                }
            }

            if personalUtilities.downloads.isEmpty,
               let completed = personalUtilities.recentDownloadCompleted {
                Label("\(completed) finished", systemImage: "checkmark.circle.fill")
                    .font(Self.monoSmall)
                    .foregroundStyle(Self.accent)
            }
        }
    }

    // MARK: - Connected-device batteries

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionLabel("DEVICES")
                Spacer()
                Button { personalUtilities.refreshBluetooth(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Self.accent.opacity(0.8))
                }
                .buttonStyle(.plain)
                .disabled(personalUtilities.isRefreshingBluetooth)
                .help("Refresh device batteries")
            }

            ForEach(personalUtilities.deviceBatteries.prefix(4)) { device in
                HStack(spacing: 8) {
                    Image(systemName: batterySymbol(device.primaryPercent))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(device.primaryPercent <= 20 ? .orange : Self.accent)
                    Text(device.name)
                        .font(Self.monoSmall)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(device.summary)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
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
                if model.remindersAuthorized {
                    Button {
                        isAddingReminder.toggle()
                        model.clearReminderMutationError()
                        if isAddingReminder {
                            Task { @MainActor in reminderFieldFocused = true }
                        }
                    } label: {
                        Image(systemName: isAddingReminder ? "xmark" : "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Self.actionAccent)
                            .padding(3)
                    }
                    .buttonStyle(.plain)
                    .help(isAddingReminder ? "Cancel new task" : "Add task")
                    .accessibilityLabel(isAddingReminder ? "Cancel new task" : "Add task")
                }
                settingsButton(label: "Choose Reminders lists")
            }
            if isAddingReminder {
                HStack(spacing: 8) {
                    TextField("New task", text: $newReminderTitle)
                        .textFieldStyle(.plain)
                        .font(Self.monoSmall)
                        .foregroundStyle(.white)
                        .focused($reminderFieldFocused)
                        .onSubmit(addReminder)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                    Button("ADD", action: addReminder)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Self.actionAccent)
                        )
                        .buttonStyle(.plain)
                        .disabled(!canAddReminder)
                        .opacity(canAddReminder ? 1 : 0.45)
                }
                if let error = model.reminderMutationError {
                    Text(error)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.85))
                }
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
                HStack {
                    emptyText("Reminders access needed")
                    Spacer()
                    miniActionButton(remindersRecoveryTitle, action: performRemindersRecovery)
                    settingsButton(label: "Reminders settings")
                }
            }
        }
    }

    // MARK: - Helpers

    private var canAddReminder: Bool {
        !GlancesModel.normalizedReminderTitle(newReminderTitle).isEmpty
    }

    private func addReminder() {
        guard canAddReminder else { return }
        if model.addReminder(title: newReminderTitle) {
            newReminderTitle = ""
            isAddingReminder = false
            reminderFieldFocused = false
        }
    }

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

    private func miniActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Self.actionAccent)
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private var calendarRecoveryTitle: String {
        if model.calendarAuthorizationStatus == .writeOnly { return "UPGRADE" }
        if GlancesModel.canRequestFullCalendarAccess(model.calendarAuthorizationStatus) { return "GRANT" }
        return "PRIVACY"
    }

    private func performCalendarRecovery() {
        if GlancesModel.canRequestFullCalendarAccess(model.calendarAuthorizationStatus) {
            model.requestCalendarAccess()
        } else {
            openPrivacySettings("Privacy_Calendars")
        }
    }

    private var remindersRecoveryTitle: String {
        model.remindersAuthorizationStatus == .notDetermined ? "GRANT" : "PRIVACY"
    }

    private func performRemindersRecovery() {
        if model.remindersAuthorizationStatus == .notDetermined {
            model.requestRemindersAccess()
        } else {
            openPrivacySettings("Privacy_Reminders")
        }
    }

    private var weatherRecoveryAction: (title: String, perform: () -> Void)? {
        let manualLocation = weatherLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if manualLocation.isEmpty, model.locationAuthorizationStatus == .notDetermined {
            return ("GRANT", { model.requestLocationAccess() })
        }
        if manualLocation.isEmpty, !model.locationAuthorized {
            return ("PRIVACY", { openPrivacySettings("Privacy_LocationServices") })
        }
        return ("SET ZIP", { SettingsWindowController.shared.show(page: .glances) })
    }

    private func openPrivacySettings(_ pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func downloadStatus(_ download: PersonalUtilitiesModel.DownloadInfo) -> String {
        if download.isStalled { return "paused" }
        if let percent = download.percent { return "\(percent)%" }
        return ByteCountFormatter.string(fromByteCount: download.bytesReceived, countStyle: .file)
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ...10: return "battery.0percent"
        case ...35: return "battery.25percent"
        case ...60: return "battery.50percent"
        case ...85: return "battery.75percent"
        default: return "battery.100percent"
        }
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

enum HomePanelSelection: String, CaseIterable, Identifiable {
    case sessions
    case glances
    case hub

    var id: String { rawValue }
}

/// Segmented toggle shown atop the session-list surface.
struct GlancesToggleRow: View {
    @Binding var selection: HomePanelSelection

    private static let accent = Color.orange

    var body: some View {
        HStack(spacing: 1) {
            tab(label: "Now", selection: .sessions)
            tab(label: "Today", selection: .glances)
            tab(label: "Tools", selection: .hub)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func tab(label: String, selection target: HomePanelSelection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { selection = target }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(selection == target ? Self.accent : .white.opacity(0.3))
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selection == target ? Self.accent.opacity(0.14) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
