import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct RestRoutineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var navigation = AppNavigation.shared
    @StateObject private var reminders = ReminderController()
    private let container: ModelContainer

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            fatalError("Rest & Routine could not open its local database: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup("Rest & Routine", id: "main") {
            ContentView()
                .environmentObject(navigation)
                .environmentObject(reminders)
                .frame(minWidth: 820, minHeight: 520)
        }
        .modelContainer(container)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Log Sleep…") { navigation.selection = .today; navigation.sleepEntryRequest += 1 }
                    .keyboardShortcut("l", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(reminders)
                .frame(width: 520)
        }
        .modelContainer(container)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setting the delegate does not ask for permission.
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        Task { @MainActor in
            if let kind = ReminderKind(notificationIdentifier: identifier) {
                NSApp.activate(ignoringOtherApps: true)
                AppNavigation.shared.handleReminder(kind)
            }
            completionHandler()
        }
    }
}
