import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TutorRequest: Codable, Sendable {
    public struct Message: Codable, Sendable {
        public let role: MessageRole
        public let content: String
    }
    public let requestID: UUID
    public let language: StudyLanguage
    public let level: StudyLevel
    public let scene: ConversationScene
    public let messages: [Message]
    public init(session: ConversationSession, requestID: UUID) {
        self.requestID = requestID; language = session.language; level = session.level; scene = session.scene
        messages = session.messages.map { Message(role: $0.role, content: $0.content) }
    }
}

public enum TutorClientError: Error, LocalizedError {
    case invalidURL, missingToken, unavailable(String), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "请在设置中填写有效的 HTTPS 后端地址。"
        case .missingToken: return "请在设置中填写个人后端访问令牌，不是模型供应商 API 密钥。"
        case .unavailable(let detail): return detail
        case .invalidResponse: return "服务返回的格式不正确，请重试。"
        }
    }
}

public struct TutorClient: Sendable {
    public let baseURL: URL
    private let token: String
    public init(address: String, token: String) throws {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw TutorClientError.invalidURL
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TutorClientError.missingToken }
        baseURL = url; self.token = token
    }

    public func reply(_ request: TutorRequest) async throws -> String {
        struct Reply: Decodable { let reply: String }
        let result: Reply = try await post(request, path: "v1/tutor/reply")
        guard !result.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TutorClientError.invalidResponse }
        return result.reply
    }

    public func feedback(_ request: TutorRequest) async throws -> TutorFeedback {
        try await post(request, path: "v1/tutor/feedback")
    }

    private func post<T: Decodable>(_ payload: TutorRequest, path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TutorClientError.invalidResponse }
        guard http.statusCode == 200 else {
            let message: String
            switch http.statusCode {
            case 401, 403: message = "访问令牌无效或已过期，请更新设置。"
            case 409: message = "该请求编号已用于不同内容，请开启新会话。"
            case 413, 422: message = "内容过长或格式不支持，请缩短输入或开启新会话。"
            case 429: message = "请求频率或今日额度已达上限，请稍后重试。"
            case 503: message = "AI 后端尚未配置或暂时不可用。可以继续本地学习。"
            default: message = "AI 服务暂时没有完成请求，请重试。"
            }
            throw TutorClientError.unavailable(message)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw TutorClientError.invalidResponse }
    }
}
