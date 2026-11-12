import UserNotifications
import Photos
import UIKit
import SwiftUI

@MainActor
final class ReminderService: ObservableObject {
    @Published var message: String?
    func schedule(hour: Int, minute: Int, timezone: String) async {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { message = "Notifications are disabled. Enable them in iPhone Settings."; return }
            center.removePendingNotificationRequests(withIdentifiers: ["daily-moment", "weekly-episode"])
            let daily = UNMutableNotificationContent(); daily.title = "Your story needs you."; daily.body = "Add today's moment to your cast's week."; daily.sound = .default
            var time = DateComponents(); time.hour = hour; time.minute = minute; time.timeZone = TimeZone(identifier: timezone)
            try await center.add(UNNotificationRequest(identifier: "daily-moment", content: daily, trigger: UNCalendarNotificationTrigger(dateMatching: time, repeats: true)))
            let weekly = UNMutableNotificationContent(); weekly.title = "A new week. A new episode."; weekly.body = "Open PlotTwist to create an episode if your cast added moments last week."; weekly.sound = .default
            var monday = DateComponents(); monday.weekday = 2; monday.hour = 9; monday.minute = 0; monday.timeZone = TimeZone(identifier: timezone)
            try await center.add(UNNotificationRequest(identifier: "weekly-episode", content: weekly, trigger: UNCalendarNotificationTrigger(dateMatching: monday, repeats: true)))
            message = "Reminders enabled in your group's time zone."
        } catch { message = error.localizedDescription }
    }
    func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-moment", "weekly-episode"])
        message = "Reminders disabled."
    }
}
enum PhotoLibrary {
    static func saveVideo(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PlotError.message("Allow Photos access in Settings to save your video.") }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
