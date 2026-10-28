import SwiftUI
import LinguaMateCore

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var english: StudyLevel = .intermediate
    @State private var korean: StudyLevel = .beginner
    @State private var englishMinutes = 15
    @State private var koreanMinutes = 15
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "text.bubble.fill").font(.largeTitle).foregroundStyle(.tint)
                        Text("两种语言，\n一步一步学会表达。").font(.largeTitle.bold())
                        Text("先建立你的学习空间。水平是自我描述，不是考试评定；以后随时可以调整。")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                Section("英语 · IELTS 7.0+ / CET-6") {
                    Picker("目前水平", selection: $english) { ForEach(StudyLevel.allCases) { Text($0.title).tag($0) } }
                    Stepper("每天建议 \(englishMinutes) 分钟", value: $englishMinutes, in: 10...60, step: 5)
                }
                Section("韩语 · TOPIK II / 日常交流") {
                    Picker("目前水平", selection: $korean) { ForEach(StudyLevel.allCases) { Text($0.title).tag($0) } }
                    Stepper("每天建议 \(koreanMinutes) 分钟", value: $koreanMinutes, in: 10...60, step: 5)
                }
                Section {
                    Text("每天总计 \(englishMinutes + koreanMinutes) 分钟。词汇与练习可离线使用；真实 AI 需在「我的」中配置个人后端并授权文字上传。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("建立学习空间") {
                        store.change { state in
                            state.profile.english = LanguageProfile(level: english, dailyMinutes: englishMinutes)
                            state.profile.korean = LanguageProfile(level: korean, dailyMinutes: koreanMinutes)
                            state.profile.onboarded = true
                        }
                    }.font(.headline).accessibilityIdentifier("finishOnboarding")
                }
            }.navigationTitle("LinguaMate")
        }
    }
}
