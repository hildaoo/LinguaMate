import SwiftUI
import LinguaMateCore

extension StudyLanguage {
    var tint: Color { self == .english ? Color(red: 0.05, green: 0.47, blue: 0.43) : Color(red: 0.48, green: 0.29, blue: 0.66) }
}

struct Panel<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PageScroll<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) { content }.padding(20) }
            .background(Color(.systemGroupedBackground))
    }
}

struct SpaceHeader: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("独立学习空间", selection: Binding(get: { store.language }, set: { store.select($0) })) {
                ForEach(StudyLanguage.allCases) { language in Text("\(language.title) · \(language.nativeTitle)").tag(language) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("languagePicker")
            Text(store.language.goal).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct MetricTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

struct Notice: View {
    let text: String
    var body: some View { Label(text, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

struct EmptyMessage: View {
    let title: String
    let detail: String
    let icon: String
    var body: some View { ContentUnavailableView(title, systemImage: icon, description: Text(detail)) }
}

struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(.title3.bold()).accessibilityAddTraits(.isHeader) }
}
