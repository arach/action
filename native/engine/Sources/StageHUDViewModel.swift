import Foundation

@MainActor
final class StageHUDViewModel: ObservableObject {
    enum ButtonTone {
        case primary
        case secondary
        case destructive
    }

    struct ButtonModel: Identifiable {
        let id: String
        let title: String
        let enabled: Bool
        let tone: ButtonTone
    }

    @Published var phase: String = "staging"
    @Published var targetApp: String = "Action"
    @Published var summary: String = "Guided capture session"
    @Published var detail: String?
    @Published var stepLabel: String?
    @Published var recentLogs: [String] = []
    @Published var elapsedMs: Double?

    var onCommand: ((String) -> Void)?

    var phaseLabel: String {
        phase.replacingOccurrences(of: "-", with: " ").uppercased()
    }

    var phaseAccent: StageHUDThemePhaseAccent {
        switch phase {
        case "recording":
            return .recording
        case "paused":
            return .paused
        default:
            return .neutral
        }
    }

    var detailText: String {
        if let stepLabel, !stepLabel.isEmpty {
            return stepLabel
        }
        if let detail, !detail.isEmpty {
            return detail
        }
        return "Guided capture session"
    }

    var elapsedText: String? {
        guard let elapsedMs else {
            return nil
        }
        let totalSeconds = Int(max(0, elapsedMs) / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var buttons: [ButtonModel] {
        [
            ButtonModel(id: "start", title: phase == "paused" ? "Resume" : "Start", enabled: isEnabled("start"), tone: .primary),
            ButtonModel(id: "stop", title: phase == "paused" ? "End" : "Stop", enabled: isEnabled("stop"), tone: .destructive),
            ButtonModel(id: "replay", title: "Replay", enabled: isEnabled("replay"), tone: .secondary),
            ButtonModel(id: "clear", title: "Clear", enabled: isEnabled("clear"), tone: .secondary),
            ButtonModel(id: "quit", title: "Quit", enabled: isEnabled("quit"), tone: .secondary),
        ]
    }

    func send(_ id: String) {
        guard isEnabled(id) else {
            return
        }
        onCommand?(id)
    }

    private func isEnabled(_ id: String) -> Bool {
        switch id {
        case "start":
            return phase == "staging" || phase == "completed" || phase == "failed" || phase == "paused" || phase == "created"
        case "stop":
            return phase == "countdown" || phase == "recording" || phase == "paused"
        case "replay":
            return phase == "completed"
        case "clear", "quit":
            return true
        default:
            return false
        }
    }
}

enum StageHUDThemePhaseAccent {
    case neutral
    case paused
    case recording
}
