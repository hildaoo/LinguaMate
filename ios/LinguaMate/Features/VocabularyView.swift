import SwiftUI
import LinguaMateCore

struct VocabularyView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var showAdd = false
    @State private var showReview = false
    private var filtered: [VocabularyItem] {
        store.words.filter {
            (!favoritesOnly || $0.favorite) && (search.isEmpty || $0.term.localizedCaseInsensitiveContains(search) || $0.meaning.contains(search))
        }
    }
    var body: some View {
        List {
            Section {
                Button { showReview = true } label: {
                    HStack {
                        Label("开始到期复习", systemImage: "rectangle.on.rectangle.angled")
                        Spacer()
                        Text("\(store.dueWords.count)").monospacedDigit()
                    }
                }.accessibilityIdentifier("startReview")
                Toggle("只看收藏", isOn: $favoritesOnly)
            } footer: { Text("种子词条为原创教学示例，不是权威词典。AI 建议与自建词条保留来源标记。") }
            Section("词汇本 · \(filtered.count)") {
                ForEach(filtered) { word in
                    NavigationLink { WordDetailView(id: word.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(word.term).font(.headline)
                                if word.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.orange) }
                            }
                            Text(word.meaning).font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
                if filtered.isEmpty { Text("没有符合条件的词条。").foregroundStyle(.secondary) }
            }
        }
        .searchable(text: $search, prompt: "搜索词语或中文释义")
        .navigationTitle("\(store.language.title)词汇本").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新增词条").accessibilityIdentifier("addWord")
            }
        }
        .sheet(isPresented: $showAdd) { NavigationStack { AddWordView(language: store.language) } }
        .sheet(isPresented: $showReview) { NavigationStack { ReviewView(language: store.language) } }
        .onChange(of: store.language) { _, _ in search = "" }
    }
}

struct AddWordView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let language: StudyLanguage
    @State private var term = ""
    @State private var meaning = ""
    @State private var example = ""
    var body: some View {
        Form {
            Section("\(language.title)词条") {
                TextField("单词或表达", text: $term).accessibilityIdentifier("wordTerm")
                TextField("中文释义", text: $meaning, axis: .vertical).accessibilityIdentifier("wordMeaning")
                TextField("例句（可选）", text: $example, axis: .vertical)
            }
            Section { Notice(text: "保存为用户自建词条；同一语言中的重复词语会保留已有记录。") }
        }
        .navigationTitle("新增词条")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if store.change({ try $0.addWord(language: language, term: term, meaning: meaning, example: example) }) { dismiss() }
                }.disabled(term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || term.count > 150 || meaning.count > 1000 || example.count > 2000)
                    .accessibilityIdentifier("saveWord")
            }
        }
    }
}

struct WordDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var confirmDelete = false
    var body: some View {
        Group {
            if let word = store.snapshot.vocabulary.first(where: { $0.id == id }) {
                PageScroll {
                    Panel {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(word.term).font(.largeTitle.bold()).textSelection(.enabled)
                            Text(word.meaning).font(.title3)
                            if !word.example.isEmpty { Text(word.example).textSelection(.enabled) }
                            Notice(text: word.source)
                            Button(word.favorite ? "取消收藏" : "收藏词条", systemImage: word.favorite ? "star.fill" : "star") {
                                store.change { state in
                                    if let i = state.vocabulary.firstIndex(where: { $0.id == id }) { state.vocabulary[i].favorite.toggle() }
                                }
                            }
                        }
                    }
                    Text("下次复习：\(word.review.due.formatted(date: .abbreviated, time: .shortened))")
                    Text("连续成功复习 \(word.review.repetitions) 次 · 遗忘 \(word.review.lapses) 次").font(.subheadline).foregroundStyle(.secondary)
                    Notice(text: "复习状态仅用于安排练习，不代表语言水平认证。")
                    Button("删除词条", role: .destructive) { confirmDelete = true }
                }
            } else { EmptyMessage(title: "词条已删除", detail: "可以返回词汇本继续学习。", icon: "book.closed") }
        }
        .navigationTitle("词条详情").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("删除该词条？已有复习事件仍保留在学习记录中。", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if store.change({ $0.vocabulary.removeAll { $0.id == id } }) { dismiss() }
            }
        }
    }
}

struct ReviewView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let language: StudyLanguage
    @State private var queue: [UUID] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var loaded = false
    var body: some View {
        PageScroll {
            if index < queue.count, let word = store.snapshot.vocabulary.first(where: { $0.id == queue[index] }) {
                Text("\(index + 1) / \(queue.count)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                ProgressView(value: Double(index), total: Double(max(1, queue.count)))
                Panel {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(word.term).font(.largeTitle.bold()).textSelection(.enabled)
                        if revealed {
                            Text(word.meaning).font(.title3)
                            Text(word.example).foregroundStyle(.secondary)
                            Notice(text: word.source)
                        } else {
                            Text("先在心里说出释义，试着用它造一个句子。").foregroundStyle(.secondary)
                            Button("显示释义") { revealed = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("revealWord")
                        }
                    }.frame(minHeight: 200, alignment: .topLeading)
                }
                if revealed {
                    Text("这次回忆感觉如何？").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ReviewRating.allCases) { rating in
                            Button(rating.title) {
                                if store.change({ try $0.reviewWord(id: word.id, rating: rating) }) { index += 1; revealed = false }
                            }.buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                                .accessibilityIdentifier("rate-\(rating.rawValue)")
                        }
                    }
                }
            } else {
                EmptyMessage(title: queue.isEmpty ? "暂时没有到期词汇" : "本轮复习完成", detail: "新词可加入词汇本；忘记的词会在稍后再次到期。", icon: "checkmark.seal")
                Button("返回学习") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("\(language.title)复习")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        .onAppear {
            if !loaded {
                queue = store.snapshot.vocabulary.filter { $0.language == language && $0.review.due <= Date() }
                    .sorted { $0.review.due < $1.review.due }.map(\.id)
                loaded = true
            }
        }
    }
}
