import Foundation
import UserNotifications

enum ReminderKind: String, CaseIterable, Identifiable, Codable {
    case morning
    case evening

    var id: String { rawValue }

    var identifier: String { "com.example.RestRoutine.reminder.\(rawValue)" }

    var title: String {
        switch self {
        case .morning: "Morning logging reminder"
        case .evening: "Evening wind-down reminder"
        }
    }

    var defaultHour: Int { self == .morning ? 9 : 22 }

    /// Generic text only. Notifications never include health values.
    var notificationBody: String {
        switch self {
        case .morning: "Time to log last night's sleep."
        case .evening: "Time to start your wind-down routine."
        }
    }

    init?(notificationIdentifier: String) {
        guard let kind = ReminderKind.allCases.first(where: { $0.identifier == notificationIdentifier }) else {
            return nil
        }
        self = kind
    }
}

struct ReminderSetting: Equatable, Codable {
    var enabled: Bool
    var hour: Int
    var minute: Int

    static func defaults(for kind: ReminderKind) -> ReminderSetting {
        ReminderSetting(enabled: false, hour: kind.defaultHour, minute: 0)
    }
}

enum NotificationPermission: Equatable {
    case notDetermined, allowed, denied
}

/// The parts of the notification center the app uses, so tests can substitute it.
protocol NotificationScheduling: AnyObject {
    func permission() async -> NotificationPermission
    func requestPermission() async -> Bool
    func schedule(identifier: String, title: String, body: String, hour: Int, minute: Int) async throws
    func removePending(identifiers: [String])
}

final class SystemNotificationScheduler: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    func permission() async -> NotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(identifier: String, title: String, body: String, hour: Int, minute: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // A repeating calendar trigger fires at this local wall-clock time,
        // following daylight-saving and time-zone changes.
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func removePending(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

/// Owns the morning and evening reminder settings. Permission is requested
/// only when the person turns a reminder on.
@MainActor
final class ReminderController: ObservableObject {
    @Published private(set) var settings: [ReminderKind: ReminderSetting]
    @Published var message: String?

    private let scheduler: NotificationScheduling
    private let defaults: UserDefaults

    static let deniedMessage =
        "Notifications are turned off for Rest & Routine, so this reminder stays off. You can allow them in System Settings › Notifications. Logging works either way."

    init(scheduler: NotificationScheduling = SystemNotificationScheduler(), defaults: UserDefaults = .standard) {
        self.scheduler = scheduler
        self.defaults = defaults
        var loaded: [ReminderKind: ReminderSetting] = [:]
        for kind in ReminderKind.allCases {
            var setting = ReminderSetting.defaults(for: kind)
            if defaults.object(forKey: PreferenceKey.reminderHour(kind)) != nil {
                setting.hour = defaults.integer(forKey: PreferenceKey.reminderHour(kind))
                setting.minute = defaults.integer(forKey: PreferenceKey.reminderMinute(kind))
            }
            setting.enabled = defaults.bool(forKey: PreferenceKey.reminderEnabled(kind))
            loaded[kind] = setting
        }
        settings = loaded
    }

    func setting(_ kind: ReminderKind) -> ReminderSetting {
        settings[kind] ?? .defaults(for: kind)
    }

    func setEnabled(_ kind: ReminderKind, _ enabled: Bool) async {
        message = nil
        guard enabled else {
            scheduler.removePending(identifiers: [kind.identifier])
            store(kind) { $0.enabled = false }
            return
        }
        var permission = await scheduler.permission()
        if permission == .notDetermined {
            permission = await scheduler.requestPermission() ? .allowed : .denied
        }
        guard permission == .allowed else {
            store(kind) { $0.enabled = false }
            message = ReminderController.deniedMessage
            return
        }
        do {
            let current = setting(kind)
            try await scheduler.schedule(
                identifier: kind.identifier, title: "Rest & Routine", body: kind.notificationBody,
                hour: current.hour, minute: current.minute)
            store(kind) { $0.enabled = true }
        } catch {
            store(kind) { $0.enabled = false }
            message = "The reminder could not be scheduled. Logging still works."
        }
    }

    /// Changing a time replaces the pending request when the reminder is on.
    func setTime(_ kind: ReminderKind, hour: Int, minute: Int) async {
        store(kind) {
            $0.hour = hour
            $0.minute = minute
        }
        guard setting(kind).enabled else { return }
        scheduler.removePending(identifiers: [kind.identifier])
        do {
            try await scheduler.schedule(
                identifier: kind.identifier, title: "Rest & Routine", body: kind.notificationBody,
                hour: hour, minute: minute)
        } catch {
            store(kind) { $0.enabled = false }
            message = "The reminder could not be scheduled. Logging still works."
        }
    }

    /// Turns every reminder off and removes pending requests.
    func disableAll() {
        scheduler.removePending(identifiers: ReminderKind.allCases.map(\.identifier))
        for kind in ReminderKind.allCases { store(kind) { $0.enabled = false } }
    }

    /// Applies restored times. Reminders stay off so a restore never bypasses
    /// notification consent; the person turns them on again.
    func applyRestored(_ restored: [ReminderKind: ReminderSetting]) {
        disableAll()
        for (kind, setting) in restored {
            store(kind) {
                $0.hour = setting.hour
                $0.minute = setting.minute
                $0.enabled = false
            }
        }
    }

    private func store(_ kind: ReminderKind, _ change: (inout ReminderSetting) -> Void) {
        var setting = setting(kind)
        change(&setting)
        settings[kind] = setting
        defaults.set(setting.enabled, forKey: PreferenceKey.reminderEnabled(kind))
        defaults.set(setting.hour, forKey: PreferenceKey.reminderHour(kind))
        defaults.set(setting.minute, forKey: PreferenceKey.reminderMinute(kind))
    }
}
