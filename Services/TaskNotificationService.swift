import Foundation
import UserNotifications

final class TaskNotificationService {

    static let shared = TaskNotificationService()
    private init() {}

    private let notificationsAuthRequestedKey = "bc.notifications.authRequested"

    /// Запросить разрешение на уведомления один раз (покажет системный попап, если статус .notDetermined).
    func requestAuthorizationOnce() {
        if UserDefaults.standard.bool(forKey: notificationsAuthRequestedKey) { return }
        UserDefaults.standard.set(true, forKey: notificationsAuthRequestedKey)

        requestAuthorizationIfNeeded(allowPrompt: true) { _ in
            // цель — показать системный запрос в правильный момент (осознанное действие пользователя)
        }
    }

    // MARK: - Публичное API

    /// Перепланирование уведомлений без показа системного prompt (фоновый вызов из bootstrap и т.д.).
    func rescheduleAllNotifications(tasks: [TaskItem]) {
        let center = UNUserNotificationCenter.current()

        requestAuthorizationIfNeeded(allowPrompt: false) { granted in
            guard granted else { return }

            center.removeAllPendingNotificationRequests()

            let activeTasks = tasks.filter { task in
                guard !task.isCompleted, let date = task.dueDate else { return false }
                return date > Date()
            }

            for task in activeTasks {
                self.scheduleNotification(for: task)
            }
        }
    }

    func rescheduleNotification(for task: TaskItem) {
        let center = UNUserNotificationCenter.current()

        requestAuthorizationIfNeeded(allowPrompt: false) { granted in
            guard granted else { return }

            center.removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])

            guard !task.isCompleted,
                  let date = task.dueDate,
                  date > Date()
            else {
                return
            }

            self.scheduleNotification(for: task)
        }
    }

    func cancelNotification(for taskID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [taskID.uuidString])
    }

    // MARK: - Приватное

    private func scheduleNotification(for task: TaskItem) {
        guard let dueDate = task.dueDate else { return }

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

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// allowPrompt: true — при .notDetermined показать системный запрос (только для requestAuthorizationOnce).
    /// allowPrompt: false — при .notDetermined не показывать prompt, вернуть false (фоновое перепланирование).
    private func requestAuthorizationIfNeeded(allowPrompt: Bool, completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                if allowPrompt {
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        DispatchQueue.main.async { completion(granted) }
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            case .denied:
                DispatchQueue.main.async { completion(false) }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(true) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}
