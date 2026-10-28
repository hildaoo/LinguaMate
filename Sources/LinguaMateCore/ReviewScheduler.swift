import Foundation

public enum ReviewRating: String, Codable, CaseIterable, Identifiable, Sendable {
    case again, hard, good, easy
    public var id: String { rawValue }
    public var title: String {
        switch self { case .again: return "忘记"; case .hard: return "困难"; case .good: return "熟悉"; case .easy: return "轻松" }
    }
}

public struct ReviewState: Codable, Equatable, Sendable {
    public var due: Date
    public var intervalDays: Double = 0
    public var ease: Double = 2.5
    public var repetitions: Int = 0
    public var lapses: Int = 0
    public var lastReviewed: Date?
    public init(due: Date = Date()) { self.due = due }
}

public enum ReviewScheduler {
    public static func next(_ previous: ReviewState, rating: ReviewRating, now: Date) -> ReviewState {
        var result = previous
        result.lastReviewed = now
        if rating == .again {
            result.repetitions = 0; result.lapses += 1
            result.ease = max(1.3, result.ease - 0.2)
            result.intervalDays = 10.0 / 1_440
        } else {
            let base = max(1, previous.intervalDays)
            switch rating {
            case .hard:
                result.ease = max(1.3, result.ease - 0.15)
                result.intervalDays = previous.repetitions == 0 ? 1 : base * 1.2
            case .good:
                result.intervalDays = previous.repetitions == 0 ? 1 : (previous.repetitions == 1 ? 3 : base * result.ease)
            case .easy:
                result.ease = min(3.0, result.ease + 0.15)
                result.intervalDays = previous.repetitions == 0 ? 4 : base * result.ease * 1.3
            case .again: break
            }
            result.repetitions += 1
        }
        result.intervalDays = min(365, result.intervalDays)
        result.due = now.addingTimeInterval(result.intervalDays * 86_400)
        return result
    }
}
