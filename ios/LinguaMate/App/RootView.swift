import SwiftUI
import LinguaMateCore

enum AppTab: Hashable { case home, conversation, learn, exams, profile }

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab: AppTab = .home
    @State private var confirmRecovery = false
    var body: some View {
        Group {
            if let message = store.recoveryMessage {
                NavigationStack {
                    PageScroll {
                        EmptyMessage(title: "数据需要恢复", detail: message, icon: "externaldrive.badge.exclamationmark")
                        ShareLink("导出原始文件", item: store.persistence.url)
                        Button("重新读取") { store.load() }
                        Button("备份原文件并重新开始", role: .destructive) { confirmRecovery = true }
                    }.navigationTitle("保护学习记录")
                }
                .confirmationDialog("原文件会先备份，然后创建空白学习档案。", isPresented: $confirmRecovery, titleVisibility: .visible) {
                    Button("备份并重新开始", role: .destructive) { store.recover() }
                }
            } else if !store.snapshot.profile.onboarded {
                OnboardingView()
            } else {
                TabView(selection: $tab) {
                    NavigationStack { HomeView(tab: $tab).safeAreaInset(edge: .top) { SpaceHeader() } }
                        .tabItem { Label("首页", systemImage: "house") }.tag(AppTab.home)
                    NavigationStack { ConversationView().safeAreaInset(edge: .top) { SpaceHeader() } }
                        .tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right") }.tag(AppTab.conversation)
                    NavigationStack { VocabularyView().safeAreaInset(edge: .top) { SpaceHeader() } }
                        .id("learn-" + store.language.rawValue)
                        .tabItem { Label("学习", systemImage: "book") }.tag(AppTab.learn)
                    NavigationStack { ExamListView().safeAreaInset(edge: .top) { SpaceHeader() } }
                        .id("exam-" + store.language.rawValue)
                        .tabItem { Label("练习", systemImage: "checkmark.square") }.tag(AppTab.exams)
                    NavigationStack { ProfileView().safeAreaInset(edge: .top) { SpaceHeader() } }
                        .id("profile-" + store.language.rawValue)
                        .tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(AppTab.profile)
                }
            }
        }.tint(store.language.tint)
    }
}
