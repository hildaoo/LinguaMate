import Foundation

/// A small deterministic practice aid. It is deliberately not labelled as AI.
public enum OfflineTutor {
    public static func reply(to session: ConversationSession) -> String {
        let turn = session.messages.filter { $0.role == .user }.count
        let prompts: [String]
        if session.language == .english {
            switch session.scene {
            case .daily: prompts = ["What do you usually do after work or school?", "What do you enjoy about it? Give one example.", "What would you like to try next week?"]
            case .travel: prompts = ["Welcome! What would you like to order?", "Would you prefer something hot or cold?", "How would you politely ask for the bill?"]
            case .campus: prompts = ["What subject are you studying?", "Which part of the course interests you most?", "How would you ask a classmate for help?"]
            case .interview: prompts = ["Tell me about a project you worked on.", "What challenge did you face?", "What did you learn from that experience?"]
            case .academic: prompts = ["Should universities offer more online courses?", "What evidence could support your opinion?", "How would you respond to an opposing view?"]
            }
        } else {
            switch session.scene {
            case .daily: prompts = ["쉬는 날에는 보통 무엇을 하세요?", "그 활동을 좋아하는 이유가 무엇인가요?", "다음 주에는 무엇을 하고 싶으세요?"]
            case .travel: prompts = ["어서 오세요. 무엇을 주문하시겠어요?", "따뜻한 음료와 차가운 음료 중 어떤 것을 원하세요?", "계산할 때 어떻게 말하면 좋을까요?"]
            case .campus: prompts = ["어떤 과목을 공부하고 계세요?", "그 과목에서 가장 흥미로운 부분은 무엇인가요?", "친구에게 도움을 어떻게 부탁하시겠어요?"]
            case .interview: prompts = ["참여했던 프로젝트를 소개해 주세요.", "어떤 어려움이 있었나요?", "그 경험을 통해 무엇을 배웠나요?"]
            case .academic: prompts = ["온라인 수업의 장점은 무엇이라고 생각하세요?", "그 의견을 뒷받침할 예를 들어 주세요.", "반대 의견에 대해서는 어떻게 생각하세요?"]
            }
        }
        return prompts[(max(1, turn) - 1) % prompts.count]
    }

    public static func feedback(for session: ConversationSession) -> TutorFeedback {
        let text = session.messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n")
        let rules: [Correction] = session.language == .english ? [
            Correction(kind: "grammar", original: "I am agree", improved: "I agree", explanation: "agree 是动词，表达同意时不需要在前面加 am。"),
            Correction(kind: "grammar", original: "discuss about", improved: "discuss", explanation: "discuss 后直接接讨论的对象，通常不加 about。"),
            Correction(kind: "grammar", original: "He go", improved: "He goes", explanation: "一般现在时中，第三人称单数主语使用 goes。请结合实际时态确认。")
        ] : [
            Correction(kind: "grammar", original: "친구을", improved: "친구를", explanation: "친구 没有收音，作为宾语时接 를；有收音的名词才接 을。"),
            Correction(kind: "grammar", original: "책를", improved: "책을", explanation: "책 有收音 ㄱ，作为宾语时应接 을。"),
            Correction(kind: "grammar", original: "저는 커피가 마셔요", improved: "저는 커피를 마셔요", explanation: "在这个句子中咖啡是喝的对象，使用宾格助词 를。")
        ]
        let corrections = rules.filter { text.contains($0.original) }
        return TutorFeedback(
            summary: "本地规则练习已完成。只检查少量固定表达；没有命中规则不代表没有错误，也不提供语言等级或发音评分。",
            corrections: corrections,
            followUp: corrections.first.map { "请用「\($0.improved)」写一个自己的句子。" } ?? "选一句自己的回答，补充一个具体例子。连接云端 AI 后可获得更全面的语境反馈。"
        )
    }
}
