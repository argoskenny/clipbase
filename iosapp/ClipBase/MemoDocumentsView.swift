import SwiftUI
import UIKit

struct MemoDocumentsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDocumentId: String?
    @State private var searchText = ""
    @State private var activeSheet: MemoSheet?

    private var documents: [MemoDocument] {
        let rows = model.snapshot.activeMemoDocuments
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return rows
        }
        return rows.filter { document in
            [document.title, document.content].contains { $0.lowercased().contains(query) }
        }
    }

    private var selectedDocument: MemoDocument? {
        if let selectedDocumentId, let document = model.snapshot.activeMemoDocuments.first(where: { $0.id == selectedDocumentId }) {
            return document
        }
        return model.snapshot.activeMemoDocuments.first
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDocumentId) {
                Section {
                    ForEach(documents) { document in
                        NavigationLink(value: document.id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.title)
                                    .lineLimit(1)
                                Text("\(paragraphCount(document.content)) 段 / \(document.copyableRanges.count) 標記")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button {
                                activeSheet = .edit(document)
                            } label: {
                                Label("編輯", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                model.deleteMemoDocument(id: document.id)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    SectionHeaderCount(title: "文件", count: model.snapshot.activeMemoDocuments.count)
                }
            }
            .searchable(text: $searchText, prompt: "搜尋文件")
            .navigationTitle("備忘")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .new
                    } label: {
                        Label("新增文件", systemImage: "doc.badge.plus")
                    }
                }
            }
        } detail: {
            NavigationStack {
                if let document = selectedDocument {
                    MemoReaderView(document: document)
                        .navigationTitle(document.title)
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button {
                                    activeSheet = .edit(document)
                                } label: {
                                    Label("編輯", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    model.deleteMemoDocument(id: document.id)
                                } label: {
                                    Label("刪除", systemImage: "trash")
                                }
                            }
                        }
                } else {
                    EmptyStateView(title: "尚無文件", message: "建立長篇備忘，並把重要文字片段標記為可點擊複製。", systemImage: "doc.text")
                        .navigationTitle("備忘")
                        .toolbar {
                            Button {
                                activeSheet = .new
                            } label: {
                                Label("新增文件", systemImage: "doc.badge.plus")
                            }
                        }
                }
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: model.snapshot.activeMemoDocuments) {
            ensureSelection()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .new:
                MemoEditorView(title: "新增文件") { title, content, ranges in
                    if let id = model.createMemoDocument(title: title, content: content, copyableRanges: ranges) {
                        selectedDocumentId = id
                    }
                }
            case .edit(let document):
                MemoEditorView(title: "編輯文件", document: document) { title, content, ranges in
                    model.updateMemoDocument(id: document.id, title: title, content: content, copyableRanges: ranges)
                }
            }
        }
    }

    private func ensureSelection() {
        if let selectedDocumentId, model.snapshot.activeMemoDocuments.contains(where: { $0.id == selectedDocumentId }) {
            return
        }
        selectedDocumentId = model.snapshot.activeMemoDocuments.first?.id
    }

    private func paragraphCount(_ content: String) -> Int {
        DomainRules.splitMemoText(content: content, ranges: []).count
    }

private enum MemoSheet: Identifiable {
    case new
    case edit(MemoDocument)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let document):
            return document.id
        }
    }
}

private struct MemoReaderView: View {
    var document: MemoDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    EmptyStateView(title: "文件沒有內容", message: "編輯文件後即可在這裡閱讀與複製標記文字。", systemImage: "doc.text")
                } else {
                    Text("\(document.copyableRanges.count) 個文字片段已標記為可複製")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    CopyableMemoTextView(content: document.content, ranges: document.copyableRanges)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

private struct CopyableMemoTextView: UIViewRepresentable {
    var content: String
    var ranges: [CopyableRange]

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.label,
            .underlineStyle: 0
        ]
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.content = DomainRules.normalizeLineEndings(content)
        uiView.attributedText = makeAttributedText()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: DomainRules.normalizeLineEndings(content))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 32
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    private func makeAttributedText() -> NSAttributedString {
        let normalized = DomainRules.normalizeLineEndings(content)
        let nsText = normalized as NSString
        let attributed = NSMutableAttributedString(
            string: normalized,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
        )

        for range in DomainRules.normalizeCopyableRanges(ranges, content: normalized) {
            guard range.start >= 0, range.end <= nsText.length, range.start < range.end else {
                continue
            }
            if let url = URL(string: "clipbase-range://\(range.start)-\(range.end)") {
                attributed.addAttributes([
                    .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.35),
                    .link: url
                ], range: NSRange(location: range.start, length: range.end - range.start))
            }
        }

        return attributed
    }

    private var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 12
        return style
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var content: String

        init(content: String) {
            self.content = content
        }

        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            let nsText = content as NSString
            guard characterRange.location >= 0, characterRange.location + characterRange.length <= nsText.length else {
                return false
            }
            UIPasteboard.general.string = nsText.substring(with: characterRange)
            return false
        }
    }
}

private struct FlowParagraphView: View {
    var segments: [MemoTextSegment]

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
            .font(.body)
            .lineSpacing(4)
            .contextMenu {
                ForEach(segments.filter(\.isCopyable)) { segment in
                    Button {
                        UIPasteboard.general.string = segment.text
                    } label: {
                        Label(segment.text, systemImage: "doc.on.doc")
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(segments.filter(\.isCopyable)) { segment in
                        Button {
                            UIPasteboard.general.string = segment.text
                        } label: {
                            Text(segment.text)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .opacity(0.01)
                        .accessibilityLabel("複製標記文字")
                    }
                }
            }
    }

    private var attributedText: AttributedString {
        var output = AttributedString()
        for segment in segments {
            var text = AttributedString(segment.text)
            if segment.isCopyable {
                text.backgroundColor = .yellow.opacity(0.35)
                text.foregroundColor = .primary
                text.inlinePresentationIntent = .stronglyEmphasized
            }
            output += text
        }
        return output
    }
}

private struct MemoEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var document: MemoDocument?
    var onSave: (String, String, [CopyableRange]) -> Void

    @State private var draftTitle = ""
    @State private var content = ""
    @State private var ranges: [CopyableRange] = []
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var validationMessage: String?

    private var normalizedRanges: [CopyableRange] {
        DomainRules.normalizeCopyableRanges(ranges, content: content)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("標題") {
                    TextField("文件標題", text: $draftTitle)
                }

                Section {
                    SelectableTextEditor(text: $content, selectedRange: $selectedRange)
                        .frame(minHeight: 280)
                        .onChange(of: content) {
                            ranges = DomainRules.normalizeCopyableRanges(ranges, content: content)
                        }
                } header: {
                    HStack {
                        Text("內容")
                        Spacer()
                        Text("\(normalizedRanges.count) 標記")
                    }
                }

                Section {
                    Button {
                        markSelection()
                    } label: {
                        Label("標記選取文字", systemImage: "highlighter")
                    }
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !normalizedRanges.isEmpty {
                    Section("已標記文字") {
                        ForEach(normalizedRanges) { range in
                            Button(role: .destructive) {
                                ranges.removeAll { $0 == range }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("移除")
                                        .font(.caption)
                                    Text(excerpt(for: range))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        onSave(draftTitle, content, normalizedRanges)
                        dismiss()
                    }
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            draftTitle = document?.title ?? ""
            content = document?.content ?? ""
            ranges = document?.copyableRanges ?? []
        }
    }

    private func markSelection() {
        guard let range = DomainRules.copyableRange(content: content, selectedRange: selectedRange) else {
            validationMessage = "請先選取要標記的文字"
            return
        }
        validationMessage = nil
        ranges = DomainRules.normalizeCopyableRanges(ranges + [range], content: content)
    }

    private func excerpt(for range: CopyableRange) -> String {
        let normalized = DomainRules.normalizeLineEndings(content) as NSString
        guard range.start >= 0, range.end <= normalized.length, range.start < range.end else {
            return ""
        }
        return normalized.substring(with: NSRange(location: range.start, length: range.end - range.start))
    }
}

private struct SelectableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var selectedRange: NSRange

        init(text: Binding<String>, selectedRange: Binding<NSRange>) {
            _text = text
            _selectedRange = selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            selectedRange = textView.selectedRange
        }
    }
}
}
