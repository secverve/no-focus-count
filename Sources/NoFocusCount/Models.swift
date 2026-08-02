import Foundation

struct TrackedWindow: Identifiable, Hashable, Codable {
    let id: UInt32
    let ownerPID: Int32
    let appName: String
    let bundleIdentifier: String?
    let title: String

    var displayName: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(appName) — 제목 없는 창 #\(id)"
            : "\(appName) — \(title)"
    }
}

enum FocusStatus: String, Codable, Equatable {
    case focused
    case differentApplication
    case differentWindow
    case targetCovered
    case targetUnavailable

    var label: String {
        switch self {
        case .focused: "집중 중"
        case .differentApplication: "다른 앱 사용"
        case .differentWindow: "다른 창 사용"
        case .targetCovered: "집중 창이 가려짐"
        case .targetUnavailable: "집중 창을 찾을 수 없음"
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
}

enum FocusPolicy {
    static func evaluate(
        snapshot: ActivitySnapshot,
        target: TrackedWindow,
        minimumVisibleFraction: Double
    ) -> FocusStatus {
        guard snapshot.targetIsOnScreen else { return .targetUnavailable }
        guard snapshot.frontmostPID == target.ownerPID else { return .differentApplication }
        guard snapshot.frontmostWindowID == target.id else { return .differentWindow }
        guard snapshot.targetVisibleFraction >= minimumVisibleFraction else { return .targetCovered }
        return .focused
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

    var duration: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }
}

struct FocusSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    let plannedFocusSeconds: TimeInterval
    var completedFocusSeconds: TimeInterval
    let target: TrackedWindow
    var distractions: [DistractionEvent]

    var distractionCount: Int { distractions.count }

    var totalDistractionSeconds: TimeInterval {
        distractions.reduce(0) { $0 + $1.duration }
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
}

extension Date {
    var shortDateTimeText: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
