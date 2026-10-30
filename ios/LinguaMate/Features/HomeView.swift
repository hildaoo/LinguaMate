import SwiftUI
import LinguaMateCore

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var tab: AppTab
    @State private var showReview = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let tasks = LearningPlanner.tasks(snapshot: store.snapshot, language: store.language, now: context.date)
            let stats = LearningStatistics(snapshot: store.snapshot, language: store.language, now: context.date)
            PageScroll {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                    Text("今天，也向前一步。").font(.largeTitle.bold())
                    Text("\(store.language.title)空间 · 每日建议 \(store.profile.dailyMinutes) 分钟")
                        .foregroundStyle(.secondary)
                }
                Panel {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("今日计划").font(.headline)
                            Spacer()
                            Text("\(tasks.filter(\.isComplete).count)/\(tasks.count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(tasks.filter(\.isComplete).count), total: Double(tasks.count))
                        ForEach(tasks) { task in
                            Button {
                                switch task.activity {
                                case .conversation: tab = .conversation
                                case .review: showReview = true
                                case .practice: tab = .exams
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(task.isComplete ? store.language.tint : .secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(task.title).font(.headline).foregroundStyle(.primary)
                                        Text(task.reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                        Text("\(task.completed)/\(task.target) · 建议 \(task.minutes) 分钟").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                            if task.id != tasks.last?.id { Divider() }
                        }
                    }
                }
                Panel {
                    HStack {
                        MetricTile(value: "\(stats.streak)", label: "连续学习天数")
                        MetricTile(value: "\(store.dueWords.count)", label: "待复习词汇")
                        MetricTile(value: "\(stats.practiceCount)", label: "已完成专项")
                    }
                }
                Button { tab = .conversation } label: {
                    Label("开始\(store.language.title)对话", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                if let latest = store.snapshot.examSessions.last(where: { $0.language == store.language }) {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("最近专项 · \(latest.title)").font(.headline)
                            Text("答对 \(latest.correct)/\(latest.total) 题 · \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                            Notice(text: "原创练习结果，不是官方考试成绩。")
                        }
                    }
                }
                NavigationLink { LearningHistoryView() } label: { Label("查看真实学习记录", systemImage: "clock.arrow.circlepath") }
            }
        }
        .navigationTitle("今日学习").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReview) { NavigationStack { ReviewView(language: store.language) } }
    }
}
