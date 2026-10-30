import Foundation

public enum StudyError: Error, LocalizedError {
    case missingItem, emptyWord, sessionIncomplete
    public var errorDescription: String? {
        switch self {
        case .missingItem: return "学习记录不存在，可能已被删除。"
        case .emptyWord: return "请填写词语和中文释义。"
        case .sessionIncomplete: return "请先完成至少一轮对话，再生成反馈。"
        }
    }
}

extension AppSnapshot {
    @discardableResult
    public mutating func addWord(language: StudyLanguage, term: String, meaning: String,
                                 example: String = "", source: String = "用户自建 · 未审校", now: Date = Date()) throws -> UUID {
        let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let definition = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !definition.isEmpty else { throw StudyError.emptyWord }
        if let found = vocabulary.first(where: { $0.language == language && $0.term.caseInsensitiveCompare(clean) == .orderedSame }) {
            return found.id
        }
        let word = VocabularyItem(language: language, term: clean, meaning: definition, example: example, source: source, now: now)
        vocabulary.append(word)
        return word.id
    }

    public mutating func reviewWord(id: UUID, rating: ReviewRating, now: Date = Date()) throws {
        guard let index = vocabulary.firstIndex(where: { $0.id == id }) else { throw StudyError.missingItem }
        vocabulary[index].review = ReviewScheduler.next(vocabulary[index].review, rating: rating, now: now)
        let word = vocabulary[index]
        events.append(LearningEvent(language: word.language, activity: .review, referenceID: id, date: now,
                                    detail: "复习「\(word.term)」· \(rating.title)"))
    }

    public mutating func recordExam(_ result: ExamSession) {
        guard !examSessions.contains(where: { $0.id == result.id }) else { return }
        examSessions.append(result)
        events.append(LearningEvent(language: result.language, activity: .practice, referenceID: result.id, date: result.date,
                                    detail: "\(result.title) · \(result.correct)/\(result.total)"))
    }

    public mutating func finishConversation(id: UUID, feedback: TutorFeedback, now: Date = Date()) throws {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { throw StudyError.missingItem }
        guard conversations[index].finishedAt == nil else { return }
        guard conversations[index].pendingRequestID == nil,
              conversations[index].messages.contains(where: { $0.role == .user }),
              conversations[index].messages.contains(where: { $0.role == .assistant }) else { throw StudyError.sessionIncomplete }
        conversations[index].feedback = feedback
        conversations[index].pendingFeedbackID = nil
        conversations[index].finishedAt = now
        let session = conversations[index]
        events.append(LearningEvent(language: session.language, activity: .conversation, referenceID: id,
                                    date: now, detail: "\(session.scene.title) · \(session.mode == .live ? "AI 对话" : "本地规则练习")"))
        for correction in feedback.corrections {
            if let errorIndex = errors.firstIndex(where: {
                $0.language == session.language && $0.source == session.mode &&
                $0.correction.original.lowercased() == correction.original.lowercased() && $0.correction.kind == correction.kind
            }) {
                errors[errorIndex].occurrences += 1
                errors[errorIndex].lastSeen = now
                errors[errorIndex].correction = correction
            } else {
                errors.append(ErrorRecord(language: session.language, correction: correction, now: now, source: session.mode))
            }
        }
    }

    public mutating func clearConversationHistory() {
        conversations.removeAll()
        errors.removeAll()
        events.removeAll { $0.activity == .conversation }
    }
}

public struct DailyTask: Identifiable, Sendable {
    public var id: String { activity.rawValue }
    public let activity: LearningActivity
    public let title: String
    public let reason: String
    public let minutes: Int
    public let completed: Int
    public let target: Int
    public var isComplete: Bool { completed >= target }
}

public enum LearningPlanner {
    public static func tasks(snapshot: AppSnapshot, language: StudyLanguage, now: Date = Date(), calendar: Calendar = .current) -> [DailyTask] {
        let today = snapshot.events.filter { $0.language == language && calendar.isDate($0.date, inSameDayAs: now) }
        let reviewed = Set(today.filter { $0.activity == .review }.map(\.referenceID))
        let due = Set(snapshot.vocabulary.filter { $0.language == language && $0.review.due <= now }.map(\.id))
        let budget = max(10, min(90, snapshot.profile.forLanguage(language).dailyMinutes))
        let chunk = budget / 3
        let weakest = snapshot.errors.filter { $0.language == language }.max { $0.occurrences < $1.occurrences }
        let reason = weakest.map { "巩固近期表达：\($0.correction.improved)" } ?? "用主动表达练习目标语言"
        return [
            DailyTask(activity: .conversation, title: "完成一轮对话与反馈", reason: reason,
                      minutes: budget - 2 * chunk, completed: min(1, today.filter { $0.activity == .conversation }.count), target: 1),
            DailyTask(activity: .review, title: "复习到期词汇", reason: due.isEmpty ? "已到期词汇已处理，按计划继续复习" : "先巩固需要再次回忆的词汇",
                      minutes: chunk, completed: min(3, reviewed.count), target: min(3, due.union(reviewed).count)),
            DailyTask(activity: .practice, title: "完成一组专项练习", reason: "用客观题检查理解，再看解析",
                      minutes: chunk, completed: min(1, today.filter { $0.activity == .practice }.count), target: 1)
        ]
    }
}

public struct LearningStatistics: Sendable {
    public let reviewCount: Int
    public let conversationCount: Int
    public let practiceCount: Int
    public let correctAnswers: Int
    public let totalAnswers: Int
    public let streak: Int
    public init(snapshot: AppSnapshot, language: StudyLanguage, now: Date = Date(), calendar: Calendar = .current) {
        let events = snapshot.events.filter { $0.language == language }
        reviewCount = events.filter { $0.activity == .review }.count
        conversationCount = events.filter { $0.activity == .conversation }.count
        let exams = snapshot.examSessions.filter { $0.language == language }
        practiceCount = exams.count
        correctAnswers = exams.reduce(0) { $0 + $1.correct }
        totalAnswers = exams.reduce(0) { $0 + $1.total }
        let dates = Set(events.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: now)
        if !dates.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while dates.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day), previous != day else { break }
            day = previous
        }
        streak = count
    }
}
