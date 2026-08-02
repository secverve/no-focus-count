import AppKit
import Foundation
import UserNotifications

final class FocusAlarm {
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func fire(participantName: String) {
        NSSound(named: "Glass")?.play()
        NSApp.requestUserAttention(.criticalRequest)

        let content = UNMutableNotificationContent()
        content.title = "집중 세션 완료 🏆"
        content.body = "\(participantName)님의 타이머가 끝났습니다. 잠깐 쉬어가세요."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "focus-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
