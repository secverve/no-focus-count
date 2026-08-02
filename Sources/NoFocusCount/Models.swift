import CoreGraphics
import Foundation

struct TrackedDisplay: Identifiable {
    let id: UInt32
    let name: String
    let bounds: CGRect
    let isMain: Bool

    var resolutionLabel: String {
        "\(Int(bounds.width)) × \(Int(bounds.height))"
    }

    var displayName: String {
        isMain ? "\(name) · 메인" : name
    }
}

struct TrackedWindow: Identifiable, Hashable, Codable {
    let id: UInt32
    let ownerPID: Int32
    let appName: String
    let bundleIdentifier: String?
    let title: String
    let monitorID: UInt32?
    let monitorName: String?
    let isOnScreen: Bool?

    init(
        id: UInt32,
        ownerPID: Int32,
        appName: String,
        bundleIdentifier: String?,
        title: String,
        monitorID: UInt32? = nil,
        monitorName: String? = nil,
        isOnScreen: Bool? = nil
    ) {
        self.id = id
        self.ownerPID = ownerPID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.monitorID = monitorID
        self.monitorName = monitorName
        self.isOnScreen = isOnScreen
    }

    var displayName: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(appName) — 제목 없는 창 #\(id)"
            : "\(appName) — \(title)"
    }

    var identityLabel: String {
        let baseName = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(appName) — 제목 없음"
            : displayName
        let location = monitorName.map { " · \($0)" } ?? ""
        let visibility = isOnScreen == false ? " · 다른 Space/최소화" : ""
        return "\(baseName) · 창 #\(id)\(location)\(visibility)"
    }
}

enum FocusStatus: String, Codable, Equatable {
    case focused
    case differentApplication
    case differentWindow
    case differentTab
    case targetCovered
    case targetUnavailable
    case differentMonitor

    var label: String {
        switch self {
        case .focused: "집중 중"
        case .differentApplication: "다른 앱 사용"
        case .differentWindow: "다른 창 사용"
        case .differentTab: "브라우저 탭 변경"
        case .targetCovered: "집중 창이 가려짐"
        case .targetUnavailable: "집중 창을 찾을 수 없음"
        case .differentMonitor: "선택 모니터를 벗어남"
        }
    }
}

struct ActivitySnapshot: Equatable {
    let capturedAt: Date
    let frontmostPID: Int32?
    let frontmostAppName: String
    let frontmostBundleIdentifier: String?
    let frontmostWindowID: UInt32?
    let frontmostWindowTitle: String
    let targetIsOnScreen: Bool
    let targetVisibleFraction: Double
    let targetMonitorID: UInt32?
    let frontmostMonitorName: String?
    let frontmostMonitorID: UInt32?

    init(
        capturedAt: Date,
        frontmostPID: Int32?,
        frontmostAppName: String,
        frontmostBundleIdentifier: String?,
        frontmostWindowID: UInt32?,
        frontmostWindowTitle: String,
        targetIsOnScreen: Bool,
        targetVisibleFraction: Double,
        targetMonitorID: UInt32? = nil,
        frontmostMonitorName: String? = nil,
        frontmostMonitorID: UInt32? = nil
    ) {
        self.capturedAt = capturedAt
        self.frontmostPID = frontmostPID
        self.frontmostAppName = frontmostAppName
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.frontmostWindowID = frontmostWindowID
        self.frontmostWindowTitle = frontmostWindowTitle
        self.targetIsOnScreen = targetIsOnScreen
        self.targetVisibleFraction = targetVisibleFraction
        self.targetMonitorID = targetMonitorID
        self.frontmostMonitorName = frontmostMonitorName
        self.frontmostMonitorID = frontmostMonitorID
    }
}

enum FocusPolicy {
    static func evaluate(
        snapshot: ActivitySnapshot,
        target: TrackedWindow,
        minimumVisibleFraction: Double,
        requiredMonitorID: UInt32? = nil
    ) -> FocusStatus {
        guard snapshot.targetIsOnScreen else { return .targetUnavailable }
        if let requiredMonitorID,
           snapshot.targetMonitorID != requiredMonitorID {
            return .differentMonitor
        }
        guard snapshot.frontmostPID == target.ownerPID else { return .differentApplication }
        guard snapshot.frontmostWindowID == target.id else { return .differentWindow }
        if isBrowser(bundleIdentifier: target.bundleIdentifier),
           !target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !snapshot.frontmostWindowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           target.title != snapshot.frontmostWindowTitle {
            return .differentTab
        }
        guard snapshot.targetVisibleFraction >= minimumVisibleFraction else { return .targetCovered }
        return .focused
    }

    private static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "org.mozilla.firefox"
        ].contains(bundleIdentifier)
    }
}

struct DistractionEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let status: FocusStatus
    let appName: String
    let bundleIdentifier: String?
    let windowTitle: String
    var url: String?
    var visualReceiptPath: String? = nil

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    var destinationLabel: String {
        let cleanTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? appName : "\(appName) · \(cleanTitle)"
    }
}

struct FocusSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let participantName: String?
    let plannedFocusSeconds: TimeInterval
    var completedFocusSeconds: TimeInterval
    let target: TrackedWindow
    var targetMonitorID: UInt32? = nil
    var targetMonitorName: String? = nil
    var distractions: [DistractionEvent]

    var distractionCount: Int { distractions.count }

    var totalDistractionSeconds: TimeInterval {
        distractions.reduce(0) { $0 + $1.duration }
    }

    var participantDisplayName: String {
        let name = participantName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "나" : name
    }

    var focusScore: Double {
        let measured = completedFocusSeconds + totalDistractionSeconds
        guard measured > 0 else { return completedFocusSeconds > 0 ? 100 : 0 }
        return min(100, max(0, completedFocusSeconds / measured * 100))
    }

    var activityNarrative: String {
        guard !distractions.isEmpty else {
            return "이 세션에서는 다른 창으로 가지 않고 집중을 마쳤습니다."
        }
        let movements = distractions.prefix(5).map {
            "\($0.destinationLabel)에서 \($0.duration.koreanDurationText)"
        }
        let remainder = distractions.count > 5 ? " 외 \(distractions.count - 5)곳" : ""
        return "잘 집중하시다가 " + movements.joined(separator: " → ") + remainder + " 이동했습니다."
    }
}

struct ParticipantStats: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let totalFocusSeconds: TimeInterval
    let totalDistractionSeconds: TimeInterval
    let totalDistractionCount: Int

    var focusScore: Double {
        let measured = totalFocusSeconds + totalDistractionSeconds
        guard measured > 0 else { return totalFocusSeconds > 0 ? 100 : 0 }
        return min(100, max(0, totalFocusSeconds / measured * 100))
    }
}

enum LeaderboardCalculator {
    static func rankings(from sessions: [FocusSession]) -> [ParticipantStats] {
        let grouped = Dictionary(grouping: sessions, by: \.participantDisplayName)
        return grouped.map { name, sessions in
            ParticipantStats(
                name: name,
                sessionCount: sessions.count,
                totalFocusSeconds: sessions.reduce(0) { $0 + $1.completedFocusSeconds },
                totalDistractionSeconds: sessions.reduce(0) { $0 + $1.totalDistractionSeconds },
                totalDistractionCount: sessions.reduce(0) { $0 + $1.distractionCount }
            )
        }
        .sorted {
            if $0.focusScore == $1.focusScore {
                return $0.totalFocusSeconds > $1.totalFocusSeconds
            }
            return $0.focusScore > $1.focusScore
        }
    }
}

enum FocusCommentary {
    static func message(for score: Double, distractionCount: Int) -> String {
        switch score {
        case 90...:
            return distractionCount == 0
                ? "오늘의 인터넷은 당신을 유혹하는 데 실패했습니다. 🧘"
                : "흔들렸지만 돌아왔어요. 집중력 방어 성공. 🛡️"
        case 70..<90:
            return "딴짓 유혹을 꽤 잘 씹어먹었습니다. 다음 판은 더 깔끔하게. 🔥"
        case 45..<70:
            return "집중과 딴짓의 팽팽한 접전. 아직 승부는 안 끝났어요. 👀"
        case 20..<45:
            return "브라우저 탭이 이번 판을 가져갔습니다. 다음 세션은 10분부터. 🫠"
        default:
            return "자책하거나 약을 임의로 찾기보다, 짧게 쉬고 어려움이 계속되면 전문가와 상의해보세요. 🌱"
        }
    }
}

enum TimerPhase: Equatable {
    case idle
    case arming
    case focusing
    case pausedByUser
    case pausedByDistraction(FocusStatus)
    case completed

    var label: String {
        switch self {
        case .idle: "준비"
        case .arming: "집중 창으로 이동 중"
        case .focusing: "집중 중"
        case .pausedByUser: "사용자가 일시정지함"
        case let .pausedByDistraction(status): "자동 정지 · \(status.label)"
        case .completed: "완료"
        }
    }
}

extension TimeInterval {
    var clockText: String {
        let value = max(0, Int(self.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    var koreanDurationText: String {
        let seconds = max(0, Int(rounded()))
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes < 60 {
            return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
        }
        let hours = minutes / 60
        let minuteRemainder = minutes % 60
        return minuteRemainder == 0 ? "\(hours)시간" : "\(hours)시간 \(minuteRemainder)분"
    }
}

extension Date {
    var shortDateTimeText: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
