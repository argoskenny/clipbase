import SwiftUI

struct MemoDocumentsView: View {
    @ObservedObject var store: ClipBaseStore
    @State private var selectedDocumentId: String?
    @State private var searchText = ""
    @State private var editorState: MemoEditorState?
    @State private var pendingDelete: MemoDocument?

    private var selectedDocument: MemoDocument? {
        if let selectedDocumentId, let document = store.memoDocuments.first(where: { $0.id == selectedDocumentId }) {
            return document
        }
        return store.memoDocuments.first
    }

    private var filteredDocuments: [MemoDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.memoDocuments }
        return store.memoDocuments.filter { document in
            [document.title, document.content].contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        HSplitView {
            documentList
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            detail
                .frame(minWidth: 680)
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: store.memoDocuments) { _ in reconcileSelection() }
        .confirmationDialog("刪除文件", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            if let document = pendingDelete {
                Button("刪除「\(document.title)」", role: .destructive) {
                    store.deleteMemoDocument(id: document.id)
                    pendingDelete = nil
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var documentList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("備忘文件")
                        .font(.headline)
                    Text("\(store.memoDocuments.count) 份文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editorState = MemoEditorState(mode: .create)
                } label: {
                    Label("新增文件", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("新增文件")
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜尋標題或內容", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            List(selection: $selectedDocumentId) {
                ForEach(filteredDocuments) { document in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(document.title)
                            .lineLimit(1)
                        Text("\(paragraphCount(document.content)) 段 / \(document.copyableRanges.count) 標記")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(document.id as String?)
                    .contextMenu {
                        Button("編輯") {
                            editorState = MemoEditorState(mode: .edit(document))
                        }
                        Button("刪除", role: .destructive) {
                            pendingDelete = document
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let editorState {
            MemoEditorView(state: editorState, store: store) {
                self.editorState = nil
            }
        } else if let selectedDocument {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedDocument.title)
                            .font(.title2.bold())
                        Text("\(selectedDocument.copyableRanges.count) 個文字片段已標記為可複製")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editorState = MemoEditorState(mode: .edit(selectedDocument))
                    } label: {
                        Label("編輯文件", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        pendingDelete = selectedDocument
                    } label: {
                        Label("刪除", systemImage: "trash")
                    }
                }
                .panelPadding()

                Divider()

                if selectedDocument.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(title: "這份文件目前沒有內容", systemImage: "doc.text")
                } else {
                    MemoReaderTextView(content: selectedDocument.content, ranges: selectedDocument.copyableRanges) { text in
                        store.copy(text, notice: "文字已複製")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            EmptyStateView(title: "請先新增一份備忘文件", systemImage: "doc.badge.plus")
        }
    }

    private func reconcileSelection() {
        if let selectedDocumentId, store.memoDocuments.contains(where: { $0.id == selectedDocumentId }) {
            return
        }
        selectedDocumentId = store.memoDocuments.first?.id
    }

    private func paragraphCount(_ content: String) -> Int {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .count
    }
}

struct MemoEditorState: Identifiable {
    enum Mode {
        case create
        case edit(MemoDocument)
    }

    let id = UUID()
    let mode: Mode
}

private struct MemoEditorView: View {
    let state: MemoEditorState
    @ObservedObject var store: ClipBaseStore
    let onClose: () -> Void

    @State private var title: String
    @State private var content: String
    @State private var ranges: [CopyableRange]
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var localError = ""

    init(state: MemoEditorState, store: ClipBaseStore, onClose: @escaping () -> Void) {
        self.state = state
        self.store = store
        self.onClose = onClose
        switch state.mode {
        case .create:
            _title = State(initialValue: "")
            _content = State(initialValue: "")
            _ranges = State(initialValue: [])
        case .edit(let document):
            _title = State(initialValue: document.title)
            _content = State(initialValue: document.content)
            _ranges = State(initialValue: document.copyableRanges)
        }
    }

    private var normalizedRanges: [CopyableRange] {
        TextRangeHelpers.normalize(ranges, content: content)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sheetTitle)
                        .font(.title2.bold())
                    Text("\(normalizedRanges.count) 個文字片段已標記")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Label("返回瀏覽", systemImage: "eye")
                }
                Button {
                    save()
                } label: {
                    Label("儲存文件", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .panelPadding()

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("文件標題", text: $title)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button {
                            markSelection()
                        } label: {
                            Label("標記為可複製", systemImage: "highlighter")
                        }
                        Text("\(paragraphCount(content)) 段內容")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    SelectableMemoTextEditor(text: $content, selectedRange: $selectedRange)
                        .frame(minHeight: 420)
                        .onChange(of: content) { newValue in
                            ranges = TextRangeHelpers.normalize(ranges, content: newValue)
                        }

                    if !localError.isEmpty {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
                .frame(minWidth: 460)

                VStack(alignment: .leading, spacing: 12) {
                    Text("文字標記")
                        .font(.headline)

                    MemoReaderTextView(content: content, ranges: normalizedRanges) { text in
                        store.copy(text, notice: "文字已複製")
                    }
                    .frame(minHeight: 260)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))

                    if normalizedRanges.isEmpty {
                        Text("尚未標記文字")
                            .foregroundStyle(.secondary)
                    } else {
                        List {
                            ForEach(normalizedRanges, id: \.self) { range in
                                Button {
                                    ranges.removeAll { $0 == range }
                                } label: {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                            .foregroundStyle(.secondary)
                                        Text(TextRangeHelpers.substring(content, in: range))
                                            .lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(minHeight: 180)
                    }
                }
                .padding(20)
                .frame(minWidth: 320)
            }
        }
    }

    private var sheetTitle: String {
        switch state.mode {
        case .create: return "新增文件"
        case .edit: return "編輯文件"
        }
    }

    private func markSelection() {
        guard let range = TextRangeHelpers.copyableRange(forSelection: selectedRange, content: content) else {
            localError = "請先選取要標記的文字"
            return
        }
        localError = ""
        ranges = TextRangeHelpers.normalize(normalizedRanges + [range], content: content)
    }

    private func save() {
        let finalRanges = TextRangeHelpers.normalize(ranges, content: content)
        switch state.mode {
        case .create:
            store.createMemoDocument(title: title, content: content, copyableRanges: finalRanges)
        case .edit(let document):
            store.updateMemoDocument(id: document.id, title: title, content: content, copyableRanges: finalRanges)
        }
        onClose()
    }

    private func paragraphCount(_ content: String) -> Int {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .count
    }
}
