import XCTest
@testable import LinguaMateCore

final class TutorContractTests: XCTestCase {
    func testSwiftClientAgainstLoopbackBackend() async throws {
        guard let address = ProcessInfo.processInfo.environment["LINGUAMATE_TEST_BASE_URL"] else {
            throw XCTSkip("Start server/tests/contract_server.py and set LINGUAMATE_TEST_BASE_URL to run the HTTP contract test.")
        }
        let client = try TutorClient(address: address, token: "test-only-private-token-not-for-deployment-12345")
        for language in StudyLanguage.allCases {
            var session = ConversationSession(language: language, level: .beginner, scene: .daily, mode: .live)
            session.messages.append(ChatMessage(role: .user, content: language == .english ? "I am agree" : "친구을 만나요"))
            let request = TutorRequest(session: session, requestID: UUID())
            let reply = try await client.reply(request)
            XCTAssertEqual(reply, language == .english ? "What do you think?" : "어떻게 생각하세요?")
            let retry = try await client.reply(request)
            XCTAssertEqual(reply, retry)
            session.messages.append(ChatMessage(role: .assistant, content: reply))
            let feedback = try await client.feedback(TutorRequest(session: session, requestID: UUID()))
            XCTAssertEqual(feedback.summary, "测试反馈，不是真实 AI")
        }
        let unauthorized = try TutorClient(address: address, token: "wrong-token")
        var session = ConversationSession(language: .english, level: .beginner, scene: .daily, mode: .live)
        session.messages = [ChatMessage(role: .user, content: "Hello")]
        do {
            _ = try await unauthorized.reply(TutorRequest(session: session, requestID: UUID()))
            XCTFail("Unauthorized request must fail")
        } catch let error as TutorClientError {
            XCTAssertTrue(error.localizedDescription.contains("令牌"))
        }
    }
}
