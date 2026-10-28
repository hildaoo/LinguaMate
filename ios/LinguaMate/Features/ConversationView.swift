import SwiftUI
import LinguaMateCore

struct ConversationView: View {
    @EnvironmentObject private var store: AppStore
    @State private var scene: ConversationScene = .daily
    @State private var englishDraft = ""
    @State private var koreanDraft = ""
    @State private var operation: Task<Void, Never>?
    @State private var showHistory = false
    private var draft: Binding<String> {
        store.language == .english ? $englishDraft : $koreanDraft
    }
    var body: some View {
        VStack(spacing: 0) {
            if let session = store.currentSession {
                conversation(session)
            } else {
                PageScroll {
                    Panel {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "bubble.left.and.bubble.right.fill").font(.largeTitle).foregroundStyle(.tint)
                            Text("从一个真实表达开始").font(.title2.bold())
                            Text("选择场景，用\(store.language.title)表达自己的想法。结束后再集中查看纠错建议。")
                            scenePicker
                            Text(store.tutorMode.title).font(.footnote).foregroundStyle(.secondary)
                            Button("开始新对话") { store.newConversation(scene: scene) }.buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("newConversation")
                        }
                    }
                    modeNotice(store.tutorMode)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(store.language.title)对话").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("对话历史")
            }
        }
        .sheet(isPresented: $showHistory) { NavigationStack { ConversationHistoryView(language: store.language) } }
    }

    private var scenePicker: some View {
        Picker("对话场景", selection: $scene) { ForEach(ConversationScene.allCases) { Text($0.title).tag($0) } }
    }

    private func modeNotice(_ mode: TutorMode) -> some View {
        Notice(text: mode == .offline
               ? "本地模式使用固定追问和少量纠错规则，不是 AI。真实 AI 请在「我的」中配置；切换模式后开启新会话。"
               : "本次会话文字会经个人后端发往模型服务。无音频，不评价发音；AI 建议可能有误。")
    }

    private func conversation(_ session: ConversationSession) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("\(session.scene.title) · \(session.level.title)").font(.subheadline.bold())
                            Spacer()
                            Text(session.mode == .live ? "AI" : "本地规则").font(.caption).padding(6)
                                .background(store.language.tint.opacity(0.12), in: Capsule())
                        }
                        modeNotice(session.mode)
                        if session.messages.isEmpty {
                            Text(session.language == .english ? "试着写：I would like to talk about my day." : "试着写：오늘 있었던 일에 대해 이야기하고 싶어요.")
                                .foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        ForEach(session.messages) { message in
                            MessageBubble(message: message, tint: session.language.tint)
                        }
                        if store.busy {
                            HStack {
                                ProgressView()
                                Text("正在处理…").font(.footnote)
                                Spacer()
                                Button("取消") { operation?.cancel() }
                            }
                        } else if session.pendingRequestID != nil {
                            Panel {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("输入已保存，回复尚未完成。").font(.subheadline)
                                    Button("重试回复") { operation = Task { await store.retryReply(sessionID: session.id) } }
                                }
                            }
                        }
                        if let feedback = session.feedback {
                            FeedbackView(feedback: feedback, language: session.language, mode: session.mode)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(20)
                }
                .onChange(of: session.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            Divider()
            if session.finishedAt != nil {
                VStack {
                    scenePicker
                    Button("开始新对话") { store.newConversation(scene: scene) }.buttonStyle(.borderedProminent)
                }.padding().disabled(store.busy)
            } else {
                VStack(spacing: 10) {
                    if session.pendingFeedbackID == nil {
                        HStack(alignment: .bottom) {
                            TextField("用\(session.language.title)表达…", text: draft, axis: .vertical)
                                .lineLimit(1...5).textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("chatInput")
                                .disabled(store.busy || session.pendingRequestID != nil)
                            Button {
                                let text = draft.wrappedValue
                                let language = session.language
                                operation = Task {
                                    await store.send(text, sessionID: session.id)
                                    if store.snapshot.conversations.first(where: { $0.id == session.id })?.messages.last(where: { $0.role == .user })?.content == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                                        if language == .english { englishDraft = "" } else { koreanDraft = "" }
                                    }
                                }
                            } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                                .accessibilityLabel("发送").accessibilityIdentifier("sendMessage")
                                .disabled(store.busy || session.pendingRequestID != nil || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    HStack {
                        Button(session.pendingFeedbackID == nil ? "结束并查看纠错" : "重试生成反馈") {
                            operation = Task { await store.finish(sessionID: session.id) }
                        }
                        .accessibilityIdentifier("finishConversation")
                        .disabled(store.busy || session.pendingRequestID != nil || session.messages.count < 2)
                        Spacer()
                        if !store.busy {
                            Button("新会话") { store.newConversation(scene: scene) }.font(.footnote)
                        }
                    }
                }.padding().background(.regularMaterial)
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let tint: Color
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "我" : "练习伙伴").font(.caption).foregroundStyle(.secondary)
                Text(message.content).textSelection(.enabled)
            }.padding(14).background(message.role == .user ? tint.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            if message.role == .assistant { Spacer(minLength: 24) }
        }
    }
}

struct FeedbackView: View {
    @EnvironmentObject private var store: AppStore
    let feedback: TutorFeedback
    let language: StudyLanguage
    let mode: TutorMode
    @State private var saved: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "本轮反馈")
            Text(feedback.summary).textSelection(.enabled)
            if feedback.corrections.isEmpty { Notice(text: "本次没有返回具体纠错，不代表表达完全没有问题。") }
            ForEach(feedback.corrections) { correction in CorrectionCard(correction: correction) }
            ForEach(feedback.suggestions) { suggestion in
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.term).font(.headline)
                        Text(suggestion.meaning)
                        Text(suggestion.example).font(.subheadline).foregroundStyle(.secondary)
                        Button(saved.contains(suggestion.id) ? "已在词汇本中" : "加入词汇本") {
                            if store.saveSuggestion(suggestion, language: language, source: mode == .live ? "AI 学习建议 · 未审校" : "本地练习表达") {
                                saved.insert(suggestion.id)
                            }
                        }.disabled(saved.contains(suggestion.id))
                    }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    Label("下一步练习", systemImage: "arrow.turn.down.right").font(.headline)
                    Text(feedback.followUp)
                }
            }
        }
    }
}

struct CorrectionCard: View {
    let correction: Correction
    private var label: String {
        ["grammar": "语法", "vocabulary": "词汇", "naturalness": "自然度", "logic": "逻辑"][correction.kind] ?? "表达"
    }
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(.caption.bold()).foregroundStyle(.secondary)
                Label(correction.original, systemImage: "pencil.line").foregroundStyle(.secondary)
                Label(correction.improved, systemImage: "arrow.right").font(.headline)
                Text(correction.explanation).font(.subheadline)
            }.textSelection(.enabled)
        }
    }
}

struct ConversationHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let language: StudyLanguage
    var body: some View {
        List {
            ForEach(store.snapshot.conversations.filter { $0.language == language }.reversed()) { session in
                NavigationLink {
                    PageScroll {
                        Text(session.mode.title).font(.caption).foregroundStyle(.secondary)
                        ForEach(session.messages) { MessageBubble(message: $0, tint: language.tint) }
                        if let feedback = session.feedback { FeedbackView(feedback: feedback, language: language, mode: session.mode) }
                        else { Notice(text: "这段会话尚未生成结束反馈。") }
                    }.navigationTitle(session.scene.title)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.scene.title)
                        Text("\(session.mode.title) · \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.overlay {
            if !store.snapshot.conversations.contains(where: { $0.language == language }) {
                EmptyMessage(title: "还没有对话", detail: "新会话会自动保存在当前语言空间。", icon: "bubble.left")
            }
        }
        .navigationTitle("\(language.title)对话历史")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
    }
}
