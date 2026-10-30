import SwiftUI
import LinguaMateCore

struct ExamListView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        PageScroll {
            Text("从理解，到会用。").font(.largeTitle.bold())
            Notice(text: "这里是原创专项练习。自动判分只统计当前题目，不换算 IELTS、CET-6 或 TOPIK 官方成绩。")
            ForEach(store.practices) { practice in
                NavigationLink { PracticeView(practice: practice) } label: {
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(practice.exam).font(.caption.bold()).foregroundStyle(store.language.tint)
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(store.language.tint)
                            }
                            Text(practice.title).font(.title3.bold()).foregroundStyle(.primary)
                            Text("\(practice.difficulty) · \(practice.questions.count) 题").font(.subheadline).foregroundStyle(.secondary)
                            if let draft = store.snapshot.practiceDrafts[practice.id] {
                                Text("继续作答 · 已选 \(draft.answers.count) 题").font(.caption).foregroundStyle(store.language.tint)
                            }
                        }
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("practice-\(practice.id)")
            }
            let records = store.snapshot.examSessions.filter { $0.language == store.language }.reversed()
            if !records.isEmpty {
                SectionTitle(text: "已完成的练习")
                ForEach(Array(records)) { result in
                    if let practice = store.practices.first(where: { $0.id == result.practiceID }) {
                        NavigationLink { PracticeResultView(practice: practice, result: result) } label: {
                            Panel {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(result.title).foregroundStyle(.primary)
                                        Text(result.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(result.correct)/\(result.total)").font(.headline)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.navigationTitle("\(store.language.title)专项").navigationBarTitleDisplayMode(.inline)
    }
}

struct PracticeView: View {
    @EnvironmentObject private var store: AppStore
    let practice: PracticeSet
    @State private var result: ExamSession?
    private var answers: [String: Int] { store.snapshot.practiceDrafts[practice.id]?.answers ?? [:] }
    var body: some View {
        Group {
            if let result { PracticeResultView(practice: practice, result: result) }
            else {
                PageScroll {
                    Notice(text: practice.source)
                    Panel { Text(practice.passage).lineSpacing(7).textSelection(.enabled) }
                    ForEach(Array(practice.questions.enumerated()), id: \.element.id) { index, question in
                        Panel {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("\(index + 1). \(question.prompt)").font(.headline)
                                ForEach(Array(question.options.enumerated()), id: \.offset) { choice, option in
                                    Button {
                                        store.answer(practice: practice, questionID: question.id, choice: choice)
                                    } label: {
                                        HStack(alignment: .top) {
                                            Image(systemName: answers[question.id] == choice ? "checkmark.circle.fill" : "circle")
                                            Text(option).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                            Spacer(minLength: 0)
                                        }.padding(12).background(answers[question.id] == choice ? practice.language.tint.opacity(0.10) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain).accessibilityIdentifier("answer-\(question.id)-\(choice)")
                                }
                            }
                        }
                    }
                    Text("已答 \(answers.count)/\(practice.questions.count) 题 · 选择自动保存在本机")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("提交并查看解析") { result = store.submit(practice) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(answers.count != practice.questions.count)
                        .accessibilityIdentifier("submitPractice")
                }
            }
        }.navigationTitle(practice.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct PracticeResultView: View {
    let practice: PracticeSet
    let result: ExamSession
    var body: some View {
        PageScroll {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("练习已完成").font(.title2.bold()).accessibilityIdentifier("practiceCompleted")
                    Text("\(result.correct) / \(result.total)").font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()
                    Text("正确率 \(Int((result.accuracy * 100).rounded()))%")
                    Notice(text: "仅为这组原创题的客观判分，不是官方考试成绩或等级评定。")
                }
            }
            Panel { Text(practice.passage).lineSpacing(6).textSelection(.enabled) }
            ForEach(practice.questions) { question in
                let selected = result.answers[question.id]
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(question.prompt, systemImage: selected == question.correctIndex ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.headline)
                        if let selected, question.options.indices.contains(selected) {
                            Text("你的答案：\(question.options[selected])").foregroundStyle(.secondary)
                        }
                        Text("正确答案：\(question.options[question.correctIndex])").fontWeight(.semibold)
                        Text(question.explanation).font(.subheadline)
                    }.textSelection(.enabled)
                }
            }
        }.navigationTitle("答案与解析").navigationBarTitleDisplayMode(.inline)
    }
}
