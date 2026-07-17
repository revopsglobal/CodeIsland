import Foundation
import Combine
import CodeIslandCore
import EventKit
import CoreLocation
import AppKit
import os.log

/// Backing store for the Glances surface: next calendar event (+ one-tap join),
/// selected reminder lists, and local weather. Crest-parity notch utility.
///
/// EventKit and Core Location authorization are requested only from explicit
/// controls in the frontmost Settings window. Weather can instead use a saved
/// city or ZIP through Open-Meteo's geocoder, with no API key or location grant.
@MainActor
final class GlancesModel: NSObject, ObservableObject {
    static let shared = GlancesModel()

    struct EventInfo: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let joinURL: URL?
        let isAllDay: Bool
        let calendarTitle: String
    }

    struct ReminderInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let calendarTitle: String
    }

    struct ReminderCalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let sourceTitle: String
    }

    struct WeatherInfo: Equatable {
        let temperatureF: Int
        let symbolName: String
        let summary: String
    }

    struct GeocodedLocation: Equatable {
        let latitude: Double
        let longitude: Double
        let label: String
    }

    @Published private(set) var nextEvent: EventInfo?
    @Published private(set) var upcomingEvents: [EventInfo] = []
    @Published private(set) var reminders: [ReminderInfo] = []
    @Published private(set) var reminderCalendars: [ReminderCalendarInfo] = []
    @Published private(set) var selectedReminderCalendarIDs: Set<String> = []
    @Published private(set) var weather: WeatherInfo?
    @Published private(set) var weatherLocationLabel: String?
    @Published private(set) var calendarAuthorized = false
    @Published private(set) var remindersAuthorized = false
    @Published private(set) var locationAuthorized = false
    @Published private(set) var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var remindersAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var statusLine: String?
    @Published private(set) var reminderMutationError: String?
    @Published private(set) var calendarMutationError: String?

    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()
    private let log = Logger(subsystem: "com.codeisland", category: "Glances")
    private var lastRefresh: Date = .distantPast
    private var refreshing = false

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        updateAuthorizationStatuses()
    }

    /// Refresh everything. Throttled so opening the surface repeatedly doesn't
    /// hammer EventKit or the weather endpoints. This never prompts for access.
    func refresh(force: Bool = false) {
        let now = Date()
        if !force, refreshing || now.timeIntervalSince(lastRefresh) < 30 { return }
        refreshing = true
        lastRefresh = now
        refreshPermissions()
        requestWeather()
        refreshing = false
    }

    /// Re-read TCC state after a person changes System Settings. Authorized
    /// stores load immediately; unresolved access waits for an explicit button.
    func refreshPermissions() {
        updateAuthorizationStatuses()
        if calendarAuthorized { loadUpcomingEvents() }
        if remindersAuthorized { loadReminderCalendarsAndReminders() }
    }

    // MARK: - EventKit authorization

    func requestCalendarAccess() {
        NSApp.activate(ignoringOtherApps: true)
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarAuthorizationStatus = status
        if status == .fullAccess {
            calendarAuthorized = true
            loadUpcomingEvents()
            return
        }
        guard status == .notDetermined else { return }

        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.log.error("calendar access: \(error.localizedDescription, privacy: .public)")
                }
                self.eventStore.reset()
                self.updateAuthorizationStatuses()
                if granted || self.calendarAuthorized { self.loadUpcomingEvents() }
            }
        }
    }

    func requestRemindersAccess() {
        NSApp.activate(ignoringOtherApps: true)
        let status = EKEventStore.authorizationStatus(for: .reminder)
        remindersAuthorizationStatus = status
        if status == .fullAccess {
            remindersAuthorized = true
            loadReminderCalendarsAndReminders()
            return
        }
        guard status == .notDetermined else { return }

        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.log.error("reminders access: \(error.localizedDescription, privacy: .public)")
                }
                self.eventStore.reset()
                self.updateAuthorizationStatuses()
                if granted || self.remindersAuthorized {
                    self.loadReminderCalendarsAndReminders()
                }
            }
        }
    }

    func refreshCalendar() {
        updateAuthorizationStatuses()
        if calendarAuthorized { loadUpcomingEvents() }
    }

    private func updateAuthorizationStatuses() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        remindersAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        locationAuthorizationStatus = locationManager.authorizationStatus
        calendarAuthorized = Self.hasFullAccess(calendarAuthorizationStatus)
        remindersAuthorized = Self.hasFullAccess(remindersAuthorizationStatus)
        locationAuthorized = Self.hasLocationAccess(locationAuthorizationStatus)
    }

    nonisolated private static func hasFullAccess(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess
    }

    nonisolated private static func hasLocationAccess(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorized || status == .authorizedAlways
    }

    // MARK: - Calendar

    private func loadUpcomingEvents() {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 14, to: now) else { return }
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        upcomingEvents = events.prefix(40).compactMap(Self.eventInfo)
        nextEvent = upcomingEvents.first
    }

    private static func eventInfo(_ event: EKEvent) -> EventInfo? {
        guard let id = event.eventIdentifier else { return nil }
        return EventInfo(
            id: id,
            title: event.title ?? "Untitled event",
            start: event.startDate,
            end: event.endDate,
            joinURL: extractJoinURL(from: event),
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title
        )
    }

    @discardableResult
    func addEvent(_ draft: PersonalHubCalendarDraft) -> Bool {
        calendarMutationError = nil
        guard calendarAuthorized else {
            calendarMutationError = "Calendar access is required"
            return false
        }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            calendarMutationError = "Enter an event title"
            return false
        }
        guard draft.end > draft.start else {
            calendarMutationError = "Event end must be after its start"
            return false
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            calendarMutationError = "No writable default calendar is available"
            return false
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = draft.start
        event.endDate = draft.end
        event.calendar = calendar
        event.notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        event.url = draft.joinURL
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            loadUpcomingEvents()
            return true
        } catch {
            log.error("add event: \(error.localizedDescription, privacy: .public)")
            calendarMutationError = "Could not add the event"
            return false
        }
    }

    @discardableResult
    func deleteEvent(id: String) -> Bool {
        calendarMutationError = nil
        guard calendarAuthorized else {
            calendarMutationError = "Calendar access is required"
            return false
        }
        guard let event = eventStore.event(withIdentifier: id) else {
            calendarMutationError = "Event is no longer available"
            return false
        }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            loadUpcomingEvents()
            return true
        } catch {
            log.error("delete event: \(error.localizedDescription, privacy: .public)")
            calendarMutationError = "Could not delete the event"
            return false
        }
    }

    /// Find a video-call link in the event's URL, location, or notes.
    static func extractJoinURL(from event: EKEvent) -> URL? {
        if let url = event.url, Self.isTrustedJoinURL(url) { return url }
        let haystacks = [event.location, event.notes].compactMap { $0 }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in haystacks {
            let range = NSRange(text.startIndex..., in: text)
            let matches = detector?.matches(in: text, options: [], range: range) ?? []
            for match in matches {
                if let url = match.url, Self.isTrustedJoinURL(url) { return url }
            }
        }
        return nil
    }

    /// Only show the one-click action for known meeting providers. Parsing the
    /// host (instead of substring matching) prevents URLs such as
    /// `attacker.example/?next=meet.google.com` from being treated as trusted.
    nonisolated static func isTrustedJoinURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let rawHost = url.host?.lowercased()
        else { return false }

        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        let path = url.path.lowercased()
        let isHost: (String) -> Bool = { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }

        if isHost("zoom.us") || isHost("zoom.com") {
            return path.hasPrefix("/j/") || path.hasPrefix("/my/") || path.hasPrefix("/wc/")
        }
        if host == "meet.google.com" { return path.count > 1 }
        if host == "teams.microsoft.com" {
            return path.hasPrefix("/l/meetup-join/") || path.hasPrefix("/meet/")
        }
        if host == "teams.live.com" { return path.hasPrefix("/meet/") }
        if isHost("webex.com") {
            return path.contains("/meet/")
                || path.contains("/join/")
                || path.contains("/wbxmjs/joinservice/")
        }
        if host == "meet.jit.si" || isHost("whereby.com") || host == "chime.aws" {
            return path.count > 1
        }
        return host == "facetime.apple.com" && path.count > 1
    }

    // MARK: - Reminders

    private func loadReminderCalendarsAndReminders() {
        let calendars = eventStore.calendars(for: .reminder)
        reminderCalendars = calendars
            .map {
                ReminderCalendarInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source.title
                )
            }
            .sorted {
                if $0.sourceTitle == $1.sourceTitle { return $0.title < $1.title }
                return $0.sourceTitle < $1.sourceTitle
            }

        let stored = SettingsManager.shared.glancesReminderCalendarIDs
        let available = Set(calendars.map(\.calendarIdentifier))
        let selected = Self.resolveReminderCalendarIDs(
            stored: stored,
            available: available,
            defaultID: eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
        )
        selectedReminderCalendarIDs = selected
        if selected != stored {
            SettingsManager.shared.glancesReminderCalendarIDs = selected
        }
        loadReminders(from: calendars.filter { selected.contains($0.calendarIdentifier) })
    }

    nonisolated static func resolveReminderCalendarIDs(
        stored: Set<String>,
        available: Set<String>,
        defaultID: String?
    ) -> Set<String> {
        let validStored = stored.intersection(available)
        if !validStored.isEmpty { return validStored }
        if let defaultID, available.contains(defaultID) { return [defaultID] }
        if let first = available.sorted().first { return [first] }
        return []
    }

    /// Prefer the system default when it is one of the selected lists; otherwise
    /// use the first selected list in the same stable order shown in Settings.
    nonisolated static func preferredReminderCalendarID(
        selectedIDs: Set<String>,
        orderedAvailableIDs: [String],
        defaultID: String?
    ) -> String? {
        if let defaultID,
           selectedIDs.contains(defaultID),
           orderedAvailableIDs.contains(defaultID) {
            return defaultID
        }
        return orderedAvailableIDs.first(where: selectedIDs.contains)
    }

    nonisolated static func normalizedReminderTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func setReminderCalendar(id: String, selected: Bool) {
        guard reminderCalendars.contains(where: { $0.id == id }) else { return }
        var next = selectedReminderCalendarIDs
        if selected {
            next.insert(id)
        } else {
            guard next.count > 1 else { return }
            next.remove(id)
        }
        guard next != selectedReminderCalendarIDs else { return }
        selectedReminderCalendarIDs = next
        SettingsManager.shared.glancesReminderCalendarIDs = next

        let calendars = eventStore.calendars(for: .reminder)
            .filter { next.contains($0.calendarIdentifier) }
        loadReminders(from: calendars)
    }

    private func loadReminders(from calendars: [EKCalendar]) {
        guard !calendars.isEmpty else {
            reminders = []
            return
        }
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )
        eventStore.fetchReminders(matching: predicate) { [weak self] fetched in
            let items = (fetched ?? [])
                .sorted { lhs, rhs in
                    (lhs.dueDateComponents?.date ?? .distantFuture)
                        < (rhs.dueDateComponents?.date ?? .distantFuture)
                }
                .prefix(8)
                .map { reminder in
                    ReminderInfo(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        due: reminder.dueDateComponents?.date,
                        calendarTitle: reminder.calendar.title
                    )
                }
            Task { @MainActor in
                self?.reminders = Array(items)
            }
        }
    }

    /// Add a quick task to one of the lists selected for Glances. Natural-language
    /// parsing can call this same write path later after presenting a preview.
    @discardableResult
    func addReminder(title rawTitle: String, due: Date? = nil) -> Bool {
        reminderMutationError = nil
        guard remindersAuthorized else {
            reminderMutationError = "Reminders access is required"
            return false
        }

        let title = Self.normalizedReminderTitle(rawTitle)
        guard !title.isEmpty else {
            reminderMutationError = "Enter a task"
            return false
        }

        let calendars = eventStore.calendars(for: .reminder)
        let orderedIDs = reminderCalendars.map(\.id)
        guard let calendarID = Self.preferredReminderCalendarID(
            selectedIDs: selectedReminderCalendarIDs,
            orderedAvailableIDs: orderedIDs,
            defaultID: eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
        ), let calendar = calendars.first(where: { $0.calendarIdentifier == calendarID }) else {
            reminderMutationError = "Choose a Reminders list in settings"
            return false
        }

        let item = EKReminder(eventStore: eventStore)
        item.title = title
        item.calendar = calendar
        if let due {
            item.dueDateComponents = Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: due
            )
        }
        do {
            try eventStore.save(item, commit: true)
            loadReminders(from: calendars.filter {
                selectedReminderCalendarIDs.contains($0.calendarIdentifier)
            })
            return true
        } catch {
            log.error("add reminder: \(error.localizedDescription, privacy: .public)")
            reminderMutationError = "Could not add the task"
            return false
        }
    }

    func clearReminderMutationError() {
        reminderMutationError = nil
    }

    /// Mark a reminder complete and drop it from the list.
    func complete(_ reminder: ReminderInfo) {
        guard let item = eventStore.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        do {
            try eventStore.save(item, commit: true)
            reminders.removeAll { $0.id == reminder.id }
        } catch {
            log.error("complete reminder: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func deleteReminder(_ reminder: ReminderInfo) -> Bool {
        reminderMutationError = nil
        guard let item = eventStore.calendarItem(withIdentifier: reminder.id) as? EKReminder else {
            reminderMutationError = "Task is no longer available"
            return false
        }
        do {
            try eventStore.remove(item, commit: true)
            reminders.removeAll { $0.id == reminder.id }
            return true
        } catch {
            log.error("delete reminder: \(error.localizedDescription, privacy: .public)")
            reminderMutationError = "Could not delete the task"
            return false
        }
    }

    // MARK: - Weather (Core Location or Open-Meteo geocoding)

    func refreshWeather() {
        weather = nil
        weatherLocationLabel = nil
        statusLine = nil
        requestWeather()
    }

    func requestLocationAccess() {
        SettingsManager.shared.glancesWeatherLocation = ""
        weather = nil
        weatherLocationLabel = nil
        statusLine = nil
        updateAuthorizationStatuses()
        if locationAuthorized {
            locationManager.requestLocation()
            return
        }
        guard locationAuthorizationStatus == .notDetermined else {
            statusLine = "Location access is off — use a city or ZIP instead"
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        locationManager.requestWhenInUseAuthorization()
    }

    private func requestWeather() {
        let manualLocation = SettingsManager.shared.glancesWeatherLocation
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !manualLocation.isEmpty {
            geocodeAndFetchWeather(manualLocation)
            return
        }

        updateAuthorizationStatuses()
        if locationAuthorized {
            locationManager.requestLocation()
        } else {
            statusLine = "Set a city or ZIP in Glances settings"
        }
    }

    nonisolated static func geocodingURL(for query: String) -> URL? {
        let searchTerm = geocodingSearchTerm(for: query)
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: searchTerm),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }

    /// Open-Meteo accepts either a place name or postal code, but not a mixed
    /// phrase such as "San Francisco 94107". Prefer an embedded five-digit ZIP
    /// so the Settings field supports the natural combined form too.
    nonisolated static func geocodingSearchTerm(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitRuns = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted)
        if let zip = digitRuns.first(where: { $0.count == 5 }) { return zip }
        return trimmed
    }

    nonisolated static func parseGeocodedLocation(from data: Data) -> GeocodedLocation? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let latitude = first["latitude"] as? Double,
              let longitude = first["longitude"] as? Double,
              let name = first["name"] as? String else { return nil }
        let region = first["admin1"] as? String
        let label = [name, region]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return GeocodedLocation(latitude: latitude, longitude: longitude, label: label)
    }

    private func geocodeAndFetchWeather(_ query: String) {
        statusLine = "Finding \(query)…"
        guard let url = Self.geocodingURL(for: query) else {
            statusLine = "Invalid weather location"
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, let location = Self.parseGeocodedLocation(from: data) else {
                Task { @MainActor in
                    if let error {
                        self.log.error("weather geocoding: \(error.localizedDescription, privacy: .public)")
                    }
                    self.statusLine = "Location not found — check Glances settings"
                }
                return
            }
            Task { @MainActor in
                self.weatherLocationLabel = location.label
                self.fetchWeather(latitude: location.latitude, longitude: location.longitude)
            }
        }.resume()
    }

    fileprivate func fetchWeather(for location: CLLocation) {
        weatherLocationLabel = "Current location"
        fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func fetchWeather(latitude: Double, longitude: Double) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
        ]
        guard let url = components?.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temp = current["temperature_2m"] as? Double else {
                Task { @MainActor in
                    if let error {
                        self?.log.error("weather: \(error.localizedDescription, privacy: .public)")
                    }
                    self?.statusLine = "Weather unavailable"
                }
                return
            }
            let code = (current["weather_code"] as? Int)
                ?? (current["weather_code"] as? Double).map(Int.init)
                ?? 0
            let (symbol, summary) = Self.describe(weatherCode: code)
            Task { @MainActor in
                self?.weather = WeatherInfo(
                    temperatureF: Int(temp.rounded()),
                    symbolName: symbol,
                    summary: summary
                )
                self?.statusLine = nil
            }
        }.resume()
    }

    /// Map WMO weather codes (Open-Meteo) to an SF Symbol and short label.
    nonisolated static func describe(weatherCode code: Int) -> (String, String) {
        switch code {
        case 0: return ("sun.max.fill", "Clear")
        case 1, 2: return ("cloud.sun.fill", "Partly cloudy")
        case 3: return ("cloud.fill", "Overcast")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67: return ("cloud.rain.fill", "Rain")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "Snow")
        case 80, 81, 82: return ("cloud.heavyrain.fill", "Showers")
        case 85, 86: return ("cloud.snow.fill", "Snow showers")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "Thunderstorm")
        default: return ("cloud.fill", "—")
        }
    }
}

extension GlancesModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.fetchWeather(for: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.log.error("location: \(error.localizedDescription, privacy: .public)")
            self.statusLine = "Location unavailable — use a city or ZIP instead"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.locationAuthorizationStatus = manager.authorizationStatus
            self.locationAuthorized = Self.hasLocationAccess(manager.authorizationStatus)
            let manualLocation = SettingsManager.shared.glancesWeatherLocation
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if self.locationAuthorized, manualLocation.isEmpty { manager.requestLocation() }
        }
    }
}
