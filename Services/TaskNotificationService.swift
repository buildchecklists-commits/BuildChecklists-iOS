import Foundation
import UserNotifications

enum TaskNotificationAccess: Equatable {
    case notDetermined
    case authorized
    case provisional
    case ephemeral
    case denied
    case unknown
}

final class TaskNotificationService {

    static let shared = TaskNotificationService()
    private init() {}

    func currentAccess() async -> TaskNotificationAccess {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.access(from: settings.authorizationStatus)
    }

    /// Reads the live system status. Prompts only when `allowPrompt` is true and the status is still `.notDetermined`.
    /// A stored `bc.notifications.authRequested` value is not consulted.
    func accessForScheduling(allowPrompt: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard allowPrompt else { return false }
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            return granted
        case .denied:
            return false
        case .authorized, .provisional, .ephemeral:
            return true
        @unknown default:
            return false
        }
    }

    /// Rebuilds pending reminders after reading notification settings. Does not prompt.
    /// `currentTasks` is read only after that read returns, so a task deleted or completed during the wait is not scheduled.
    /// Return nil to leave existing requests untouched, including when the session is now DEMO.
    func rescheduleAllNotifications(currentTasks: @escaping () -> [TaskItem]?) {
        Task { @MainActor in
            let granted = await accessForScheduling(allowPrompt: false)
            guard granted else { return }
            guard let tasks = currentTasks() else { return }

            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            for task in tasks.filter(Self.canRemind) {
                self.scheduleNotification(for: task)
            }
        }
    }

    func replaceNotification(for task: TaskItem) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
        guard Self.canRemind(task) else { return }
        scheduleNotification(for: task)
    }

    func cancelNotification(for taskID: UUID) {
        cancelNotifications(for: [taskID])
    }

    func cancelNotifications(for taskIDs: Set<UUID>) {
        let identifiers = taskIDs.map(\.uuidString)
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    static func canRemind(_ task: TaskItem) -> Bool {
        guard !task.isCompleted, let date = task.dueDate else { return false }
        return date > Date()
    }

    private static func access(from status: UNAuthorizationStatus) -> TaskNotificationAccess {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }

    private func scheduleNotification(for task: TaskItem) {
        guard Self.canRemind(task), let dueDate = task.dueDate else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = (task.details?.isEmpty == false) ? (task.details ?? "") : "Срок задачи подошёл."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }
}
