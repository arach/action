import Foundation

// MARK: - Agentic loop: Start → Edit → Review

enum ActionLoopPhase: String, Codable, CaseIterable, Identifiable {
    case start
    case edit
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start: return "Start"
        case .edit: return "Edit"
        case .review: return "Review"
        }
    }

    var subtitle: String {
        switch self {
        case .start: return "Kick off a goal or seed a scenario"
        case .edit: return "Inspect the plan and leave scenario feedback"
        case .review: return "Watch the take and mark truth on media"
        }
    }
}

struct ActionLoopStepFeedback: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let createdAt: String
    var instruction: String
}

struct ActionLoopScenarioStep: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var index: Int
    var action: String
    var description: String
    var targetSummary: String?
    /// pending | approved | flagged | skipped
    var status: String
    var feedback: [ActionLoopStepFeedback]

    var isSkipped: Bool { status == "skipped" }
    var isFlagged: Bool { status == "flagged" || !feedback.isEmpty }
}

struct ActionLoopDocument: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var goal: String
    var phase: ActionLoopPhase
    /// Built-in scenario seed id (e.g. calculator-demo).
    var scenarioId: String
    var targetAppName: String
    var targetBundleId: String
    var steps: [ActionLoopScenarioStep]
    /// Session ids (take folders) produced by runs of this loop.
    var sessionIds: [String]
    var latestSessionId: String?
    var createdAt: String
    var updatedAt: String
    var lastRunStatus: String?

    var feedbackCount: Int {
        steps.reduce(0) { $0 + $1.feedback.count }
    }
}

enum ActionLoopPresets {
    /// Seed scenario matching scenarios/calculator-demo.json for the first closed circuit.
    static func calculatorDemoSteps() -> [ActionLoopScenarioStep] {
        [
            step(1, action: "type", description: "Enter 12", target: "keyboard"),
            step(2, action: "click", description: "Click plus", target: "calculator.operator.plus · +"),
            step(3, action: "type", description: "Enter 30", target: "keyboard"),
            step(4, action: "press-key", description: "Press equals", target: "calculator.operator.equals · ="),
        ]
    }

    static func makeCalculatorLoop(goal: String? = nil) -> ActionLoopDocument {
        let now = ISO8601DateFormatter().string(from: Date())
        let id = "loop-\(Int(Date().timeIntervalSince1970))-\(String(UUID().uuidString.prefix(6)).lowercased())"
        let resolvedGoal = (goal?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Show a short Calculator demo with keyboard and click input"

        return ActionLoopDocument(
            id: id,
            title: "Calculator demo",
            goal: resolvedGoal,
            phase: .edit,
            scenarioId: "calculator-demo",
            targetAppName: "Calculator",
            targetBundleId: "com.apple.calculator",
            steps: calculatorDemoSteps(),
            sessionIds: [],
            latestSessionId: nil,
            createdAt: now,
            updatedAt: now,
            lastRunStatus: nil
        )
    }

    private static func step(
        _ index: Int,
        action: String,
        description: String,
        target: String?
    ) -> ActionLoopScenarioStep {
        ActionLoopScenarioStep(
            id: "step_\(index)",
            index: index,
            action: action,
            description: description,
            targetSummary: target,
            status: "pending",
            feedback: []
        )
    }
}

@MainActor
final class ActionLoopStore {
    static let shared = ActionLoopStore()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    private var loopsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Action/loops", isDirectory: true)
    }

    func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: loopsDirectoryURL, withIntermediateDirectories: true)
    }

    func loadAll() -> [ActionLoopDocument] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: loopsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let sorted = urls
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }

        return sorted.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ActionLoopDocument.self, from: data)
        }
    }

    func save(_ document: ActionLoopDocument) throws {
        try ensureDirectory()
        var copy = document
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = try encoder.encode(copy)
        let url = loopsDirectoryURL.appendingPathComponent("\(copy.id).json")
        try data.write(to: url, options: .atomic)
    }

    func delete(id: String) throws {
        let url = loopsDirectoryURL.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func fileURL(for id: String) -> URL {
        loopsDirectoryURL.appendingPathComponent("\(id).json")
    }
}
