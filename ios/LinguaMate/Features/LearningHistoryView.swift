import SwiftUI
import LinguaMateCore

struct LearningHistoryView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let events = store.snapshot.events.filter { $0.language == store.language }.sorted { $0.date > $1.date }
        let stats = LearningStatistics(snapshot: store.snapshot, language: store.language)
        PageScroll {
            Panel {
                HStack {
                    MetricTile(value: "\(stats.reviewCount)", label: "复习次数")
                    MetricTile(value: "\(stats.conversationCount)", label: "完成对话")
                    MetricTile(value: stats.totalAnswers == 0 ? "—" : "\(stats.correctAnswers)/\(stats.totalAnswers)", label: "专项答对题数")
                }
            }
            Notice(text: "以上只统计实际练习事件。对话次数包含明确标注的本地规则练习，不用于推断真实语言等级。")
            if events.isEmpty {
                EmptyMessage(title: "还没有学习记录", detail: "完成复习、对话反馈或专项后，会自动记在这里。", icon: "clock")
            }
            ForEach(events) { event in
                Panel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.detail).font(.headline)
                        Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("\(store.language.title)学习记录").navigationBarTitleDisplayMode(.inline)
    }
}

struct ErrorNotebookView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let errors = store.snapshot.errors.filter { $0.language == store.language }.sorted { $0.lastSeen > $1.lastSeen }
        PageScroll {
            if errors.isEmpty { EmptyMessage(title: "还没有纠错记录", detail: "会话结束后的具体纠错会保存在这里。", icon: "pencil.and.outline") }
            ForEach(errors) { error in
                VStack(alignment: .leading, spacing: 8) {
                    Text("出现 \(error.occurrences) 次 · \(error.source.title)").font(.caption).foregroundStyle(.secondary)
                    CorrectionCard(correction: error.correction)
                }
            }
        }.navigationTitle("\(store.language.title)纠错本")
    }
}
