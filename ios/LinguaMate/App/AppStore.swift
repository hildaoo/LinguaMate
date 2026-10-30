import SwiftUI
import LinguaMateCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot = AppSnapshot()
    @Published var errorMessage: String?
    @Published var recoveryMessage: String?
    @Published private(set) var busy = false
    @Published var tutorMode: TutorMode {
        didSet { UserDefaults.standard.set(tutorMode.rawValue, forKey: "tutor.mode") }
    }
    let persistence: SnapshotStore
    private(set) var catalog: ContentCatalog?

    var language: StudyLanguage { snapshot.language }
    var profile: LanguageProfile { snapshot.profile.forLanguage(language) }
    var currentSession: ConversationSession? { snapshot.conversations.last { $0.language == language } }
    var words: [VocabularyItem] { snapshot.vocabulary.filter { $0.language == language } }
    var dueWords: [VocabularyItem] { words.filter { $0.review.due <= Date() }.sorted { $0.review.due < $1.review.due } }
    var practices: [PracticeSet] { catalog?.practices.filter { $0.language == language } ?? [] }

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LinguaMate", isDirectory: true)
        #if DEBUG
        let filename = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "ui-test-learning.json" : "learning.json"
        #else
        let filename = "learning.json"
        #endif
        persistence = SnapshotStore(url: root.appendingPathComponent(filename))
        tutorMode = TutorMode(rawValue: UserDefaults.standard.string(forKey: "tutor.mode") ?? "") ?? .offline
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-testing") && filename == "ui-test-learning.json" {
            try? FileManager.default.removeItem(at: persistence.url)
            tutorMode = .offline
        }
        #endif
        load()
    }

    func load() {
        do {
            catalog = try ContentCatalog.bundled()
            snapshot = try persistence.load() ?? AppSnapshot(vocabulary: catalog!.seedVocabulary())
            recoveryMessage = nil
        } catch { recoveryMessage = error.localizedDescription }
    }

    @discardableResult
    func change(_ action: (inout AppSnapshot) throws -> Void) -> Bool {
        guard recoveryMessage == nil else { return false }
        var next = snapshot
        do {
            try action(&next)
            try persistence.save(next)
            snapshot = next
            return true
        } catch {
            errorMessage = "未保存更改：\(error.localizedDescription)"
            return false
        }
    }

    func select(_ language: StudyLanguage) { change { $0.language = language } }

    func recover() {
        do {
            try persistence.preserveBackup()
            let contents = try ContentCatalog.bundled()
            let clean = AppSnapshot(vocabulary: contents.seedVocabulary())
            try persistence.save(clean)
            catalog = contents; snapshot = clean; recoveryMessage = nil
        } catch { recoveryMessage = error.localizedDescription }
    }

    func newConversation(scene: ConversationScene) {
        guard !busy else { return }
        let session = ConversationSession(language: language, level: profile.level, scene: scene, mode: tutorMode)
        change { $0.conversations.append(session) }
    }

    func send(_ text: String, sessionID: UUID) async {
        guard !busy, let session = snapshot.conversations.first(where: { $0.id == sessionID }),
              session.finishedAt == nil, session.pendingRequestID == nil, session.pendingFeedbackID == nil else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 1500 else { errorMessage = "每次请输入 1–1500 个字符。"; return }
        guard session.messages.count < 20,
              session.messages.reduce(0, { $0 + $1.content.count }) + clean.count <= 20000 else {
            errorMessage = "本轮内容已达到长度上限，请结束并查看反馈，再开始新对话。"; return
        }
        let saved = change { state in
            guard let index = state.conversations.firstIndex(where: { $0.id == sessionID }) else { throw StudyError.missingItem }
            state.conversations[index].messages.append(ChatMessage(role: .user, content: clean))
            state.conversations[index].pendingRequestID = UUID()
        }
        if saved { await retryReply(sessionID: sessionID) }
    }

    private func client() throws -> TutorClient {
        guard UserDefaults.standard.bool(forKey: "cloud.consent") else {
            throw TutorClientError.unavailable("请先在「我的」中阅读并开启文字上传授权。")
        }
        return try TutorClient(address: UserDefaults.standard.string(forKey: "backend.url") ?? "", token: KeychainStore.read())
    }

    func retryReply(sessionID: UUID) async {
        guard !busy, let session = snapshot.conversations.first(where: { $0.id == sessionID }),
              let requestID = session.pendingRequestID else { return }
        busy = true
        defer { busy = false }
        do {
            let reply: String
            if session.mode == .offline { reply = OfflineTutor.reply(to: session) }
            else { reply = try await client().reply(TutorRequest(session: session, requestID: requestID)) }
            try Task.checkCancellation()
            change { state in
                guard let index = state.conversations.firstIndex(where: { $0.id == sessionID }),
                      state.conversations[index].pendingRequestID == requestID else { return }
                state.conversations[index].messages.append(ChatMessage(role: .assistant, content: reply))
                state.conversations[index].pendingRequestID = nil
            }
        } catch is CancellationError {
            errorMessage = "请求已取消，输入已保留，可稍后重试。"
        } catch { errorMessage = error.localizedDescription }
    }

    func finish(sessionID: UUID) async {
        guard !busy, let session = snapshot.conversations.first(where: { $0.id == sessionID }),
              session.finishedAt == nil, session.pendingRequestID == nil, session.messages.count >= 2 else { return }
        let requestID = session.pendingFeedbackID ?? UUID()
        guard change({ state in
            guard let index = state.conversations.firstIndex(where: { $0.id == sessionID }) else { throw StudyError.missingItem }
            state.conversations[index].pendingFeedbackID = requestID
        }) else { return }
        busy = true
        defer { busy = false }
        do {
            let feedback: TutorFeedback
            if session.mode == .offline { feedback = OfflineTutor.feedback(for: session) }
            else { feedback = try await client().feedback(TutorRequest(session: session, requestID: requestID)) }
            try Task.checkCancellation()
            change { state in
                guard state.conversations.contains(where: { $0.id == sessionID }) else { return }
                try state.finishConversation(id: sessionID, feedback: feedback)
            }
        } catch is CancellationError {
            errorMessage = "反馈请求已取消，对话仍已保存在本机。"
        } catch { errorMessage = error.localizedDescription }
    }

    func saveSuggestion(_ suggestion: VocabularySuggestion, language: StudyLanguage, source: String) -> Bool {
        change { state in
            try state.addWord(language: language, term: suggestion.term, meaning: suggestion.meaning,
                              example: suggestion.example, source: source)
        }
    }

    func answer(practice: PracticeSet, questionID: String, choice: Int) {
        change { state in
            var draft = state.practiceDrafts[practice.id] ?? PracticeDraft()
            draft.answers[questionID] = choice
            state.practiceDrafts[practice.id] = draft
        }
    }

    func submit(_ practice: PracticeSet) -> ExamSession? {
        do {
            let draft = snapshot.practiceDrafts[practice.id] ?? PracticeDraft()
            let result = try PracticeGrader.grade(practice, answers: draft.answers, id: draft.id)
            guard change({ state in
                state.recordExam(result)
                state.practiceDrafts.removeValue(forKey: practice.id)
            }) else { return nil }
            return result
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func clearAll() {
        guard !busy else { return }
        do {
            try persistence.removeRecoveryBackups()
            try KeychainStore.delete()
            guard let catalog else { throw PersistenceError.unreadable }
            if change({ $0 = AppSnapshot(vocabulary: catalog.seedVocabulary()) }) {
                tutorMode = .offline
                ["backend.url", "cloud.consent"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
