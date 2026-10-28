import SwiftUI
import LinguaMateCore

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("backend.url") private var address = ""
    @AppStorage("cloud.consent") private var consent = false
    @State private var token = ""
    @State private var hasToken = false
    @State private var connectionMessage: String?
    @State private var checking = false
    @State private var deleteHistory = false
    @State private var deleteAll = false
    private var level: Binding<StudyLevel> {
        Binding(get: { store.profile.level }, set: { value in
            store.change { if $0.language == .english { $0.profile.english.level = value } else { $0.profile.korean.level = value } }
        })
    }
    private var minutes: Binding<Int> {
        Binding(get: { store.profile.dailyMinutes }, set: { value in
            store.change { if $0.language == .english { $0.profile.english.dailyMinutes = value } else { $0.profile.korean.dailyMinutes = value } }
        })
    }
    var body: some View {
        Form {
            Section("\(store.language.title)学习目标") {
                Text(store.language.goal)
                Picker("自报水平", selection: level) { ForEach(StudyLevel.allCases) { Text($0.title).tag($0) } }
                Stepper("每日建议 \(store.profile.dailyMinutes) 分钟", value: minutes, in: 10...60, step: 5)
                NavigationLink("学习记录") { LearningHistoryView() }
                NavigationLink("纠错本") { ErrorNotebookView() }
            }
            Section {
                Picker("新会话使用", selection: $store.tutorMode) { ForEach(TutorMode.allCases) { Text($0.title).tag($0) } }
                TextField("HTTPS 后端地址", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(hasToken ? "已保存令牌；填写可替换" : "个人后端访问令牌", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("保存访问令牌") {
                    do {
                        try KeychainStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
                        token = ""; hasToken = true; connectionMessage = "令牌已保存到本机 Keychain。"
                    } catch { store.errorMessage = "无法保存令牌：\(error.localizedDescription)" }
                }.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                Toggle("允许将会话文字发往 AI 服务", isOn: $consent)
                Button(checking ? "正在检查…" : "检查后端连接") { Task { await checkConnection() } }
                    .disabled(checking || address.isEmpty)
                if let connectionMessage { Text(connectionMessage).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("AI 服务") } footer: {
                Text("客户端只保存个人后端令牌，不能填写模型 API 密钥。云端模式发送当前会话的文字、语言、水平和场景；后端成功结果最多暂存在内存 10 分钟用于重试，供应商可能另有保留策略。断网时可继续本地词汇和专项。切换服务模式后请开启新会话。")
            }
            Section("数据与隐私") {
                Text("本版本不采集录音，没有语音识别或发音评分。学习档案保存在本机，不提供跨设备同步。")
                    .font(.footnote)
                ShareLink("导出本地学习数据", item: store.persistence.url)
                Button("清除两种语言的对话与纠错", role: .destructive) { deleteHistory = true }.disabled(store.busy)
                Button("删除全部本地学习数据", role: .destructive) { deleteAll = true }.disabled(store.busy)
            }
            Section {
                Text("LinguaMate 0.1 · 原创练习版")
                Text("学习建议与正确率不等于官方成绩。韩语口语练习和 TOPIK 备考独立记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的学习").navigationBarTitleDisplayMode(.inline)
        .onAppear { hasToken = !KeychainStore.read().isEmpty }
        .confirmationDialog("清除所有对话、纠错及对应学习记录？词汇和专项保留。", isPresented: $deleteHistory, titleVisibility: .visible) {
            Button("清除对话与纠错", role: .destructive) { store.change { $0.clearConversationHistory() } }
        }
        .confirmationDialog("删除两种语言的档案、会话、词汇进度、练习和访问令牌？该操作无法撤销。不会删除外部模型供应商的数据。", isPresented: $deleteAll, titleVisibility: .visible) {
            Button("删除并重新开始", role: .destructive) { store.clearAll(); token = ""; hasToken = false }
        }
    }

    @MainActor private func checkConnection() async {
        checking = true
        defer { checking = false }
        do {
            // Validate the endpoint without reading or sending the private token.
            let client = try TutorClient(address: address, token: "health-check-only")
            var request = URLRequest(url: client.baseURL.appendingPathComponent("health"))
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            struct Health: Decodable { let status: String; let aiConfigured: Bool }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TutorClientError.invalidResponse }
            let health = try JSONDecoder().decode(Health.self, from: data)
            connectionMessage = health.aiConfigured ? "后端可达且报告已配置。仍需实际对话验证令牌和模型权限。" : "后端可达，但模型或访问令牌尚未配置完成。"
        } catch { connectionMessage = "连接未通过：\(error.localizedDescription)" }
    }
}
