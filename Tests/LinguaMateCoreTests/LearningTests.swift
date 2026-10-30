import XCTest
@testable import LinguaMateCore

final class LearningTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testForgottenWordReturnsSoonerAndLanguageDoesNotLeak() throws {
        var state = AppSnapshot()
        let en = try state.addWord(language: .english, term: "evidence", meaning: "证据", now: now)
        let ko = try state.addWord(language: .korean, term: "근거", meaning: "依据", now: now)
        try state.reviewWord(id: en, rating: .easy, now: now)
        let longInterval = state.vocabulary.first { $0.id == en }!.review.due
        try state.reviewWord(id: en, rating: .again, now: now)
        XCTAssertLessThan(state.vocabulary.first { $0.id == en }!.review.due, longInterval)
        XCTAssertEqual(state.vocabulary.first { $0.id == ko }!.review.repetitions, 0)
        XCTAssertTrue(state.events.allSatisfy { $0.language == .english })
    }

    func testReviewIntervalsStayBounded() {
        var state = ReviewState(due: now)
        for _ in 0..<100 { state = ReviewScheduler.next(state, rating: .easy, now: now) }
        XCTAssertLessThanOrEqual(state.intervalDays, 365)
        for _ in 0..<100 { state = ReviewScheduler.next(state, rating: .again, now: now) }
        XCTAssertGreaterThanOrEqual(state.ease, 1.3)
        XCTAssertEqual(state.due.timeIntervalSince(now), 600, accuracy: 0.1)
    }

    func testWordsDeduplicateWithinLanguageOnly() throws {
        var state = AppSnapshot()
        let id = try state.addWord(language: .english, term: " Evidence ", meaning: "证据")
        XCTAssertEqual(try state.addWord(language: .english, term: "evidence", meaning: "证据"), id)
        XCTAssertNotEqual(try state.addWord(language: .korean, term: "evidence", meaning: "自建表达"), id)
        XCTAssertThrowsError(try state.addWord(language: .english, term: " ", meaning: "解释"))
    }

    func testBundledPracticeGradingAndInvalidAnswers() throws {
        let catalog = try ContentCatalog.bundled()
        XCTAssertEqual(catalog.practices.count, 4)
        XCTAssertEqual(catalog.words.count, 12)
        for practice in catalog.practices {
            let correct = Dictionary(uniqueKeysWithValues: practice.questions.map { ($0.id, $0.correctIndex) })
            let result = try PracticeGrader.grade(practice, answers: correct, now: now)
            XCTAssertEqual(result.correct, practice.questions.count)
            let wrong = Dictionary(uniqueKeysWithValues: practice.questions.map { ($0.id, ($0.correctIndex + 1) % $0.options.count) })
            XCTAssertEqual(try PracticeGrader.grade(practice, answers: wrong).correct, 0)
            XCTAssertThrowsError(try PracticeGrader.grade(practice, answers: [:]))
            var invalid = correct; invalid[practice.questions[0].id] = -1
            XCTAssertThrowsError(try PracticeGrader.grade(practice, answers: invalid))
        }
    }

    func testSubmissionIsIdempotent() throws {
        let practice = try ContentCatalog.bundled().practices[0]
        let result = try PracticeGrader.grade(practice, answers: Dictionary(uniqueKeysWithValues: practice.questions.map { ($0.id, $0.correctIndex) }))
        var state = AppSnapshot()
        state.recordExam(result); state.recordExam(result)
        XCTAssertEqual(state.examSessions.count, 1)
        XCTAssertEqual(state.events.count, 1)
    }

    func testConversationFeedbackCountsOnceAndClearRemovesDerivedData() throws {
        var session = ConversationSession(language: .english, level: .beginner, scene: .daily, mode: .offline, now: now)
        session.messages = [.init(role: .user, content: "I am agree"), .init(role: .assistant, content: "What do you think?")]
        var state = AppSnapshot(); state.conversations = [session]
        let feedback = OfflineTutor.feedback(for: session)
        XCTAssertEqual(feedback.corrections.count, 1)
        try state.finishConversation(id: session.id, feedback: feedback, now: now)
        try state.finishConversation(id: session.id, feedback: feedback, now: now)
        XCTAssertEqual(state.errors.first?.occurrences, 1)
        XCTAssertEqual(state.events.count, 1)
        XCTAssertEqual(LearningStatistics(snapshot: state, language: .korean, now: now).conversationCount, 0)
        state.clearConversationHistory()
        XCTAssertTrue(state.errors.isEmpty)
        XCTAssertTrue(state.events.isEmpty)
    }

    func testPendingConversationCannotBeCompleted() throws {
        var session = ConversationSession(language: .english, level: .beginner, scene: .daily, mode: .live)
        session.messages = [.init(role: .user, content: "Hello"), .init(role: .assistant, content: "Hi")]
        session.pendingRequestID = UUID()
        var state = AppSnapshot(); state.conversations = [session]
        XCTAssertThrowsError(try state.finishConversation(id: session.id, feedback: OfflineTutor.feedback(for: session)))
    }

    func testDailyPlanUsesActualDistinctReviewsAndBudget() throws {
        let catalog = try ContentCatalog.bundled()
        var state = AppSnapshot(vocabulary: catalog.seedVocabulary(now: now))
        state.profile.english.dailyMinutes = 17
        let en = state.vocabulary.filter { $0.language == .english }
        try state.reviewWord(id: en[0].id, rating: .again, now: now)
        try state.reviewWord(id: en[0].id, rating: .good, now: now)
        let tasks = LearningPlanner.tasks(snapshot: state, language: .english, now: now)
        XCTAssertEqual(tasks.map(\.minutes).reduce(0, +), 17)
        XCTAssertEqual(tasks.first { $0.activity == .review }?.completed, 1)
        XCTAssertFalse(tasks.allSatisfy(\.isComplete))
        XCTAssertEqual(LearningPlanner.tasks(snapshot: state, language: .korean, now: now).first { $0.activity == .review }?.completed, 0)
    }

    func testStreakRespectsCalendarDaysAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        var state = AppSnapshot()
        for offset in [-1, -2, -3] {
            let date = calendar.date(byAdding: .day, value: offset, to: day)!
            state.events.append(.init(language: .english, activity: .review, referenceID: UUID(), date: date, detail: "test"))
        }
        XCTAssertEqual(LearningStatistics(snapshot: state, language: .english, now: day, calendar: calendar).streak, 3)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
        XCTAssertEqual(LearningStatistics(snapshot: state, language: .english, now: tomorrow, calendar: calendar).streak, 0)
    }

    func testFileStoreRoundTripAndCorruptionPreservation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SnapshotStore(url: folder.appendingPathComponent("learning.json"))
        XCTAssertNil(try store.load())
        var state = AppSnapshot(vocabulary: try ContentCatalog.bundled().seedVocabulary(now: now))
        state.profile.onboarded = true
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), corrupt)
        let backup = try XCTUnwrap(store.preserveBackup())
        XCTAssertEqual(try Data(contentsOf: backup), corrupt)
        try Data("{\"schemaVersion\":999}".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load()) { error in
            guard case PersistenceError.unsupportedVersion(999) = error else { return XCTFail("Wrong version handling") }
        }
    }

    func testNoDataMeansNoFabricatedStatistics() {
        let stats = LearningStatistics(snapshot: AppSnapshot(), language: .english)
        XCTAssertEqual(stats.totalAnswers, 0)
        XCTAssertEqual(stats.conversationCount, 0)
        XCTAssertEqual(stats.streak, 0)
    }

    func testAPIConfigurationRejectsInsecureAndCredentialURLs() throws {
        XCTAssertThrowsError(try TutorClient(address: "http://remote.example", token: "test"))
        XCTAssertThrowsError(try TutorClient(address: "https://user:password@example.com", token: "test"))
        XCTAssertThrowsError(try TutorClient(address: "https://example.com?token=private", token: "test"))
        XCTAssertThrowsError(try TutorClient(address: "https://example.com", token: ""))
        _ = try TutorClient(address: "https://example.com", token: "test")
        _ = try TutorClient(address: "http://localhost:8000", token: "test")
    }

    func testCompleteLearningLoopSurvivesRelaunchInBothSpaces() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SnapshotStore(url: folder.appendingPathComponent("learning.json"))
        let catalog = try ContentCatalog.bundled()
        var state = AppSnapshot(vocabulary: catalog.seedVocabulary(now: now))
        state.profile.onboarded = true
        for language in StudyLanguage.allCases {
            for word in state.vocabulary.filter({ $0.language == language }).prefix(3) {
                try state.reviewWord(id: word.id, rating: .good, now: now)
            }
            var session = ConversationSession(language: language, level: .beginner, scene: .daily, mode: .offline, now: now)
            session.messages = [.init(role: .user, content: language == .english ? "I am agree" : "친구을 만나요")]
            session.messages.append(.init(role: .assistant, content: OfflineTutor.reply(to: session)))
            state.conversations.append(session)
            try state.finishConversation(id: session.id, feedback: OfflineTutor.feedback(for: session), now: now)
            let practice = catalog.practices.first { $0.language == language }!
            let answers = Dictionary(uniqueKeysWithValues: practice.questions.map { ($0.id, $0.correctIndex) })
            state.practiceDrafts[practice.id] = PracticeDraft(answers: answers)
            try store.save(state)
            state = try XCTUnwrap(store.load())
            let draft = try XCTUnwrap(state.practiceDrafts[practice.id])
            state.recordExam(try PracticeGrader.grade(practice, answers: draft.answers, id: draft.id, now: now))
            state.practiceDrafts.removeValue(forKey: practice.id)
            try store.save(state)
            state = try XCTUnwrap(store.load())
            XCTAssertTrue(LearningPlanner.tasks(snapshot: state, language: language, now: now).allSatisfy(\.isComplete))
            let stats = LearningStatistics(snapshot: state, language: language, now: now)
            XCTAssertEqual(stats.reviewCount, 3)
            XCTAssertEqual(stats.conversationCount, 1)
            XCTAssertEqual(stats.correctAnswers, 3)
            XCTAssertEqual(state.errors.filter { $0.language == language }.count, 1)
        }
        XCTAssertEqual(state.events.count, 10)
        let backup = try XCTUnwrap(store.preserveBackup())
        try store.removeRecoveryBackups()
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertNotNil(try store.load())
    }

    func testOfflineKoreanCorrectionAndNoInventedDiagnosis() {
        var session = ConversationSession(language: .korean, level: .beginner, scene: .daily, mode: .offline)
        session.messages = [.init(role: .user, content: "친구을 만나요")]
        XCTAssertEqual(OfflineTutor.feedback(for: session).corrections.first?.improved, "친구를")
        session.messages = [.init(role: .user, content: "알 수 없는 긴 문장")]
        XCTAssertTrue(OfflineTutor.feedback(for: session).corrections.isEmpty)
    }
}
