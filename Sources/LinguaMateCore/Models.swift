import Foundation

public enum StudyLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en", korean = "ko"
    public var id: String { rawValue }
    public var title: String { self == .english ? "英语" : "韩语" }
    public var nativeTitle: String { self == .english ? "English" : "한국어" }
    public var goal: String { self == .english ? "IELTS 7.0+ · CET-6" : "TOPIK II 5–6 级 · 独立口语训练" }
}

public enum StudyLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, advanced
    public var id: String { rawValue }
    public var title: String {
        switch self { case .beginner: return "初级"; case .intermediate: return "中级"; case .advanced: return "高级" }
    }
}

public enum TutorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case offline, live
    public var id: String { rawValue }
    public var title: String { self == .offline ? "本地规则练习 · 非 AI" : "云端 AI 教师" }
}

public enum ConversationScene: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily, travel, campus, interview, academic
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .daily: return "日常交流"
        case .travel: return "旅行与点餐"
        case .campus: return "校园生活"
        case .interview: return "求职面试"
        case .academic: return "观点与学术"
        }
    }
}

public struct LanguageProfile: Codable, Equatable, Sendable {
    public var level: StudyLevel
    public var dailyMinutes: Int
    public init(level: StudyLevel = .beginner, dailyMinutes: Int = 15) {
        self.level = level; self.dailyMinutes = dailyMinutes
    }
}

public struct UserProfile: Codable, Equatable, Sendable {
    public var english = LanguageProfile(level: .intermediate)
    public var korean = LanguageProfile()
    public var onboarded = false
    public init() {}
    public func forLanguage(_ language: StudyLanguage) -> LanguageProfile {
        language == .english ? english : korean
    }
}

public struct VocabularyItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var language: StudyLanguage
    public var term: String
    public var meaning: String
    public var example: String
    public var source: String
    public var favorite: Bool
    public var review: ReviewState
    public init(id: UUID = UUID(), language: StudyLanguage, term: String, meaning: String,
                example: String = "", source: String = "用户自建 · 未审校", now: Date = Date()) {
        self.id = id; self.language = language; self.term = term; self.meaning = meaning
        self.example = example; self.source = source; self.favorite = false
        self.review = ReviewState(due: now)
    }
}

public enum MessageRole: String, Codable, Sendable { case user, assistant }

public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var content: String
    public init(id: UUID = UUID(), role: MessageRole, content: String) {
        self.id = id; self.role = role; self.content = content
    }
}

public struct Correction: Codable, Identifiable, Equatable, Sendable {
    public var id: String { kind + original + improved }
    public let kind: String
    public let original: String
    public let improved: String
    public let explanation: String
    public init(kind: String, original: String, improved: String, explanation: String) {
        self.kind = kind; self.original = original; self.improved = improved; self.explanation = explanation
    }
}

public struct VocabularySuggestion: Codable, Identifiable, Equatable, Sendable {
    public var id: String { term }
    public let term: String
    public let meaning: String
    public let example: String
    public init(term: String, meaning: String, example: String) {
        self.term = term; self.meaning = meaning; self.example = example
    }
}

public struct TutorFeedback: Codable, Equatable, Sendable {
    public let summary: String
    public let corrections: [Correction]
    public let suggestions: [VocabularySuggestion]
    public let followUp: String
    public init(summary: String, corrections: [Correction], suggestions: [VocabularySuggestion] = [], followUp: String) {
        self.summary = summary; self.corrections = corrections; self.suggestions = suggestions; self.followUp = followUp
    }
}

public struct ConversationSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var language: StudyLanguage
    public var level: StudyLevel
    public var scene: ConversationScene
    public var mode: TutorMode
    public var createdAt: Date
    public var messages: [ChatMessage] = []
    public var pendingRequestID: UUID?
    public var pendingFeedbackID: UUID?
    public var feedback: TutorFeedback?
    public var finishedAt: Date?
    public init(id: UUID = UUID(), language: StudyLanguage, level: StudyLevel, scene: ConversationScene,
                mode: TutorMode, now: Date = Date()) {
        self.id = id; self.language = language; self.level = level; self.scene = scene; self.mode = mode; self.createdAt = now
    }
}

public struct ErrorRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var language: StudyLanguage
    public var correction: Correction
    public var occurrences: Int
    public var lastSeen: Date
    public var source: TutorMode
    public init(language: StudyLanguage, correction: Correction, now: Date, source: TutorMode) {
        self.id = UUID(); self.language = language; self.correction = correction
        self.occurrences = 1; self.lastSeen = now; self.source = source
    }
}

public enum LearningActivity: String, Codable, Sendable { case review, conversation, practice }

public struct LearningEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let language: StudyLanguage
    public let activity: LearningActivity
    public let referenceID: UUID
    public let date: Date
    public let detail: String
    public init(id: UUID = UUID(), language: StudyLanguage, activity: LearningActivity, referenceID: UUID,
                date: Date = Date(), detail: String) {
        self.id = id; self.language = language; self.activity = activity
        self.referenceID = referenceID; self.date = date; self.detail = detail
    }
}

public struct AppSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var schemaVersion = currentVersion
    public var profile = UserProfile()
    public var language: StudyLanguage = .english
    public var vocabulary: [VocabularyItem] = []
    public var conversations: [ConversationSession] = []
    public var errors: [ErrorRecord] = []
    public var events: [LearningEvent] = []
    public var examSessions: [ExamSession] = []
    public var practiceDrafts: [String: PracticeDraft] = [:]
    public init(vocabulary: [VocabularyItem] = []) { self.vocabulary = vocabulary }
}
