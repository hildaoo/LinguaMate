import SwiftUI

@main
struct LinguaMateApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .alert("提示", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("知道了", role: .cancel) { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
        }
    }
}
