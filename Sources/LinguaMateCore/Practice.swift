import Foundation

public struct PracticeDraft: Codable, Equatable, Sendable {
    public var id: UUID
    public var answers: [String: Int]
    public init(id: UUID = UUID(), answers: [String: Int] = [:]) { self.id = id; self.answers = answers }
}

public struct PracticeQuestion: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let prompt: String
    public let options: [String]
    public let correctIndex: Int
    public let explanation: String
}

public struct PracticeSet: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let language: StudyLanguage
    public let exam: String
    public let title: String
    public let difficulty: String
    public let passage: String
    public let source: String
    public let questions: [PracticeQuestion]
}

public struct ExamSession: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var language: StudyLanguage
    public var practiceID: String
    public var title: String
    public var answers: [String: Int]
    public var correct: Int
    public var total: Int
    public var date: Date
    public var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }
}

public enum PracticeError: Error, LocalizedError {
    case incomplete, invalidAnswer
    public var errorDescription: String? {
        switch self { case .incomplete: return "请完成全部题目后提交。"; case .invalidAnswer: return "答案与当前试卷不匹配，请重新打开练习。" }
    }
}

public enum PracticeGrader {
    public static func grade(_ practice: PracticeSet, answers: [String: Int], id: UUID = UUID(), now: Date = Date()) throws -> ExamSession {
        guard answers.count == practice.questions.count else { throw PracticeError.incomplete }
        var correct = 0
        for question in practice.questions {
            guard let answer = answers[question.id] else { throw PracticeError.incomplete }
            guard question.options.indices.contains(answer) else { throw PracticeError.invalidAnswer }
            if answer == question.correctIndex { correct += 1 }
        }
        return ExamSession(id: id, language: practice.language, practiceID: practice.id, title: practice.title,
                           answers: answers, correct: correct, total: practice.questions.count, date: now)
    }
}

public struct ContentCatalog: Codable, Sendable {
    public struct Word: Codable, Sendable {
        public let language: StudyLanguage
        public let term: String
        public let meaning: String
        public let example: String
    }
    public let words: [Word]
    public let practices: [PracticeSet]
    public static func bundled() throws -> ContentCatalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let result = try JSONDecoder().decode(ContentCatalog.self, from: Data(contentsOf: url))
        guard Set(result.practices.map(\.id)).count == result.practices.count,
              result.practices.allSatisfy({ !$0.questions.isEmpty && Set($0.questions.map(\.id)).count == $0.questions.count &&
                  $0.questions.allSatisfy { $0.options.indices.contains($0.correctIndex) } }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }
    public func seedVocabulary(now: Date = Date()) -> [VocabularyItem] {
        words.map { VocabularyItem(language: $0.language, term: $0.term, meaning: $0.meaning,
                                   example: $0.example, source: "原创教学示例 · 非权威词典", now: now) }
    }
}
