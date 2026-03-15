import Foundation

struct ActionSessionFeedbackDocument: Codable, Sendable {
    struct Item: Codable, Identifiable, Sendable {
        let id: String
        let createdAt: String
        let startTimeSeconds: Double
        let endTimeSeconds: Double?
        let region: Region?
        let instruction: String
    }

    struct Region: Codable, Sendable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    let sessionId: String
    var updatedAt: String
    var items: [Item]

    static func empty(for sessionId: String) -> ActionSessionFeedbackDocument {
        ActionSessionFeedbackDocument(
            sessionId: sessionId,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            items: []
        )
    }
}
