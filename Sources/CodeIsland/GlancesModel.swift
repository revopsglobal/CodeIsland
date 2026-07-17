import Foundation
import Combine
import EventKit
import CoreLocation
import SwiftUI
import os.log

/// Backing store for the Glances surface: next calendar event (+ one-tap join),
/// reminders you can check off, and local weather. Crest-parity notch utility.
///
/// The app is non-sandboxed, so EventKit + CoreLocation need only Info.plist
/// usage strings (NSCalendars/RemindersFullAccessUsageDescription,
/// NSLocationWhenInUseUsageDescription). Weather uses Open-Meteo (no API key,
/// no WeatherKit entitlement).
@MainActor
final class GlancesModel: NSObject, ObservableObject {
    struct EventInfo: Equatable {
        let title: String
        let start: Date
        let end: Date
        let joinURL: URL?
        let isAllDay: Bool
    }

    struct ReminderInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
    }

    struct WeatherInfo: Equatable {
        let temperatureF: Int
        let symbolName: String
        let summary: String
    }

    @Published var nextEvent: EventInfo?
    @Published var reminders: [ReminderInfo] = []
    @Published var weather: WeatherInfo?
    @Published var calendarAuthorized = false
    @Published var remindersAuthorized = false
    @Published var statusLine: String?

    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()
    private let log = Logger(subsystem: "com.codeisland", category: "Glances")
    private var lastRefresh: Date = .distantPast
    private var refreshing = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Refresh everything. Throttled so opening the surface repeatedly doesn't
    /// hammer EventKit / the weather endpoint.
    func refresh(force: Bool = false) {
        let now = Date()
        if !force, refreshing || now.timeIntervalSince(lastRefresh) < 30 { return }
        refreshing = true
        lastRefresh = now
        requestAccessAndLoad()
        requestWeather()
    }

    // MARK: - EventKit

    private func requestAccessAndLoad() {
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.calendarAuthorized = granted
                if let error { self.log.error("calendar access: \(error.localizedDescription, privacy: .public)") }
                if granted { self.loadNextEvent() }
                self.refreshing = false
            }
        }
        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.remindersAuthorized = granted
                if let error { self.log.error("reminders access: \(error.localizedDescription, privacy: .public)") }
                if granted { self.loadReminders() }
            }
        }
    }

    private func loadNextEvent() {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 14, to: now) else { return }
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        guard let next = events.first else {
            nextEvent = nil
            return
        }
        nextEvent = EventInfo(
            title: next.title ?? "Untitled event",
            start: next.startDate,
            end: next.endDate,
            joinURL: Self.extractJoinURL(from: next),
            isAllDay: next.isAllDay
        )
    }

    private func loadReminders() {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        eventStore.fetchReminders(matching: predicate) { [weak self] fetched in
            let items = (fetched ?? [])
                .sorted { lhs, rhs in
                    (lhs.dueDateComponents?.date ?? .distantFuture) < (rhs.dueDateComponents?.date ?? .distantFuture)
                }
                .prefix(8)
                .map { reminder in
                    ReminderInfo(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        due: reminder.dueDateComponents?.date
                    )
                }
            Task { @MainActor in
                self?.reminders = Array(items)
            }
        }
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

    /// Find a video-call link in the event's url / location / notes.
    static func extractJoinURL(from event: EKEvent) -> URL? {
        if let url = event.url, Self.isJoinURL(url.absoluteString) { return url }
        let haystacks = [event.location, event.notes].compactMap { $0 }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in haystacks {
            let range = NSRange(text.startIndex..., in: text)
            let matches = detector?.matches(in: text, options: [], range: range) ?? []
            for match in matches {
                if let url = match.url, Self.isJoinURL(url.absoluteString) { return url }
            }
        }
        return nil
    }

    private static func isJoinURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.contains("zoom.us/j/")
            || lower.contains("zoom.us/my/")
            || lower.contains("meet.google.com/")
            || lower.contains("teams.microsoft.com/l/meetup")
            || lower.contains("teams.live.com/meet")
            || lower.contains("webex.com/meet")
    }

    // MARK: - Weather (CoreLocation + Open-Meteo)

    private func requestWeather() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorized:
            locationManager.requestLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            statusLine = "Location off — enable it for weather"
        }
    }

    fileprivate func fetchWeather(for location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code&temperature_unit=fahrenheit"
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = json["current"] as? [String: Any],
                  let temp = current["temperature_2m"] as? Double else {
                if let error {
                    Task { @MainActor in self?.log.error("weather: \(error.localizedDescription, privacy: .public)") }
                }
                return
            }
            let code = (current["weather_code"] as? Int) ?? (current["weather_code"] as? Double).map(Int.init) ?? 0
            let (symbol, summary) = Self.describe(weatherCode: code)
            Task { @MainActor in
                self?.weather = WeatherInfo(temperatureF: Int(temp.rounded()), symbolName: symbol, summary: summary)
            }
        }.resume()
    }

    /// Map WMO weather codes (Open-Meteo) to an SF Symbol + short label.
    static func describe(weatherCode code: Int) -> (String, String) {
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
        Task { @MainActor in self.log.error("location: \(error.localizedDescription, privacy: .public)") }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorized:
                manager.requestLocation()
            default:
                break
            }
        }
    }
}
