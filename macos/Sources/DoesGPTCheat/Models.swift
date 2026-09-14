import Foundation

/// Mirrors the JSON produced by `dgc snapshot --json` (snake_case keys, decoded with convertFromSnakeCase).
struct Snapshot: Codable {
    var generated: String
    var version: String
    var dgcBin: String?
    var ledger: String?
    var config: DGCConfig
    var hooksLastEvent: String?
    var hooksLastEventAgo: String?
    var overall: Overall
    var defaultModel: String?
    var defaultEffort: String?
    var globalProbe: ProbeSummary?
    var globalRunning: Bool?
    var globalAlert: Bool?
    var threads: [ThreadInfo]
    var recentProbes: [ProbeSummary]
    var demo: Bool?
}

struct Overall: Codable {
    var status: String
    var downgraded: Int
    var suspicious: Int?
    var running: Int
    var message: String
}

struct DGCConfig: Codable {
    var frequency: String
    var mode: String
    var queries: Int
    var parallel: Bool
    var languages: [String]
    var passive: Bool
    var notify: Bool
    var notifyOnOk: Bool
    var announceOk: Bool
    var sound: Bool
    var haltOnMismatch: Bool
    var mismatchConfidence: Double?
    var confirmUncertain: Bool?
    var petName: String
}

struct ThreadInfo: Codable, Identifiable {
    var id: String
    var title: String
    var cwd: String?
    var model: String?
    var effort: String?
    var updated: String?
    var updatedAgo: String?
    var active: Bool
    var alert: Bool
    var suspicious: Bool?
    var turns: Int
    var turnsSinceProbe: Int
    var due: Bool
    var probeRunning: Bool
    var halted: Bool
    var requested: Bool
    var hardEvidence: Int
    var softEvidence: Int
    var lastEvidence: String?
    var lastProbe: ProbeSummary?
}

struct ProbeSummary: Codable, Identifiable {
    var id: String
    var threadId: String?
    var mode: String?
    var status: String?
    var finished: String?
    var finishedAgo: String?
    var verdict: String?
    var direction: String?
    var expected: String?
    var prediction: String?
    var probability: Double?
    var pExpected: Double?
    var margin: Double?
    var confidence: String?
    var usedOutputs: Int?
    var queries: Int?
    var rounds: Int?
    var elapsedS: Double?
    var errors: [String]?
    var quote: String?
    var isDowngrade: Bool?
    var isSuspicious: Bool?
    var retryable: Bool?
    var retries: Int?

    static func pct(_ p: Double?) -> String {
        guard let p else { return "" }
        return "\(Int((p * 100).rounded()))%"
    }

    var probabilityText: String { Self.pct(probability) }
}
