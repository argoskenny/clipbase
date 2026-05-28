import SwiftUI
import UniformTypeIdentifiers

struct ClipLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSectionId: String?
    @State private var searchText = ""
    @State private var activeSheet: ClipSheet?
    @State private var pendingSectionDelete: ClipSection?
    @State private var isImportingCSV = false
    @State private var isExportingCSV = false
    @State private var exportedCSV = ""

    private var sections: [ClipSection] {
        model.snapshot.activeSections
    }

    private var selectedSection: ClipSection? {
        guard let selectedSectionId else {
            return sections.first
        }
        return sections.first { $0.id == selectedSectionId } ?? sections.first
    }

    private var filteredItems: [ClipItem] {
        guard let section = selectedSection else {
            return []
        }
        let items = model.snapshot.activeItems(in: section.id)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return items
        }
        return items.filter { item in
            [item.name, item.content, item.metadata ?? ""].contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSectionId) {
                Section {
                    ForEach(sections) { section in
                        let count = model.snapshot.activeItems(in: section.id).count
                        NavigationLink(value: section.id) {
                            HStack {
                                Text(section.title)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button {
                                activeSheet = .editSection(section)
                            } label: {
                                Label("編輯分類", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                pendingSectionDelete = section
                            } label: {
                                Label("刪除分類", systemImage: "trash")
                            }
                            .disabled(section.title == "其它")
                        }
                    }
                } header: {
                    SectionHeaderCount(title: "分類", count: sections.count)
                }
            }
            .navigationTitle("剪貼內容")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .newSection
                    } label: {
                        Label("新增分類", systemImage: "folder.badge.plus")
                    }
                    Menu {
                        Button {
                            isImportingCSV = true
                        } label: {
                            Label("匯入 CSV", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportedCSV = model.exportCSV()
                            isExportingCSV = true
                        } label: {
                            Label("匯出 CSV", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Label("CSV", systemImage: "tablecells")
                    }
                }
            }
        } detail: {
            NavigationStack {
                if let section = selectedSection {
                    List {
                        Section {
                            ForEach(filteredItems) { item in
                                ClipItemRow(
                                    item: item,
                                    sections: sections,
                                    currentSectionId: section.id,
                                    onMove: { destinationId in
                                        model.moveItem(id: item.id, to: destinationId)
                                        selectedSectionId = destinationId
                                    },
                                    onEdit: {
                                        activeSheet = .editItem(item)
                                    },
                                    onDelete: {
                                        model.deleteItem(id: item.id)
                                    }
                                )
                            }
                        } header: {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text("\(filteredItems.count)")
                            }
                        }

                        if model.snapshot.activeItems(in: section.id).isEmpty {
                            Section {
                                EmptyStateView(title: "沒有項目", message: "新增一筆剪貼內容，或從 CSV 匯入。", systemImage: "tray")
                                    .listRowInsets(EdgeInsets())
                            }
                        }
                    }
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋名稱、內容或備註")
                    .navigationTitle(section.title)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ToolbarSyncButton()
                            Button {
                                activeSheet = .newItem(section.id)
                            } label: {
                                Label("新增項目", systemImage: "plus")
                            }
                        }
                    }
                } else {
                    EmptyStateView(title: "尚無分類", message: "先新增分類，或匯入 Web 相容的四欄 CSV。", systemImage: "folder")
                        .navigationTitle("剪貼內容")
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarTrailing) {
                                Button {
                                    activeSheet = .newSection
                                } label: {
                                    Label("新增分類", systemImage: "folder.badge.plus")
                                }
                                Button {
                                    isImportingCSV = true
                                } label: {
                                    Label("匯入 CSV", systemImage: "square.and.arrow.down")
                                }
                            }
                        }
                }
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: sections) {
            ensureSelection()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newSection:
                SectionEditorView(title: "新增分類") { title in
                    if let id = model.createSection(title: title) {
                        selectedSectionId = id
                    }
                }
            case .editSection(let section):
                SectionEditorView(title: "編輯分類", initialTitle: section.title) { title in
                    model.updateSection(id: section.id, title: title)
                }
            case .newItem(let sectionId):
                ItemEditorView(title: "新增項目", sections: sections, initialSectionId: sectionId) { name, content, destinationId in
                    model.createItem(sectionId: destinationId, name: name, content: content)
                    selectedSectionId = destinationId
                }
            case .editItem(let item):
                ItemEditorView(title: "編輯項目", sections: sections, item: item, initialSectionId: item.sectionId) { name, content, destinationId in
                    model.updateItem(id: item.id, sectionId: destinationId, name: name, content: content)
                    selectedSectionId = destinationId
                }
            }
        }
        .alert("刪除分類？", isPresented: Binding(
            get: { pendingSectionDelete != nil },
            set: { if !$0 { pendingSectionDelete = nil } }
        )) {
            Button("取消", role: .cancel) {
                pendingSectionDelete = nil
            }
            Button("刪除", role: .destructive) {
                if let section = pendingSectionDelete, let fallback = model.deleteSection(id: section.id) {
                    selectedSectionId = fallback
                }
                pendingSectionDelete = nil
            }
        } message: {
            Text("分類內未刪除項目會移到「其它」。")
        }
        .fileImporter(isPresented: $isImportingCSV, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url):
                importCSV(from: url)
            case .failure(let error):
                model.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExportingCSV,
            document: CSVExportDocument(csv: exportedCSV),
            contentType: .commaSeparatedText,
            defaultFilename: "clipbase-export.csv"
        ) { result in
            if case .failure(let error) = result {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func ensureSelection() {
        if let selectedSectionId, sections.contains(where: { $0.id == selectedSectionId }) {
            return
        }
        selectedSectionId = sections.first?.id
    }

    private func importCSV(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let csv = try String(contentsOf: url, encoding: .utf8)
            model.importCSV(csv)
            ensureSelection()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private enum ClipSheet: Identifiable {
    case newSection
    case editSection(ClipSection)
    case newItem(String)
    case editItem(ClipItem)

    var id: String {
        switch self {
        case .newSection:
            return "new-section"
        case .editSection(let section):
            return "edit-section-\(section.id)"
        case .newItem(let sectionId):
            return "new-item-\(sectionId)"
        case .editItem(let item):
            return "edit-item-\(item.id)"
        }
    }
}

private struct ClipItemRow: View {
    var item: ClipItem
    var sections: [ClipSection]
    var currentSectionId: String
    var onMove: (String) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.headline)
                    if let metadata = item.metadata {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                CopyButton(text: item.content)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text(item.content)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(4)

            HStack {
                Menu {
                    ForEach(sections) { section in
                        Button(section.title) {
                            onMove(section.id)
                        }
                        .disabled(section.id == currentSectionId)
                    }
                } label: {
                    Label("移動", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    onEdit()
                } label: {
                    Label("編輯", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                DestructiveTrashButton(title: "刪除", action: onDelete)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var initialTitle = ""
    var onSave: (String) -> Void
    @State private var draftTitle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("分類") {
                    TextField("分類名稱", text: $draftTitle)
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
                        onSave(draftTitle)
                        dismiss()
                    }
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            draftTitle = initialTitle
        }
    }
}

private struct ItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var sections: [ClipSection]
    var item: ClipItem?
    var initialSectionId: String
    var onSave: (String, String, String) -> Void

    @State private var name = ""
    @State private var content = ""
    @State private var sectionId = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("分類") {
                    Picker("分類", selection: $sectionId) {
                        ForEach(sections) { section in
                            Text(section.title).tag(section.id)
                        }
                    }
                }
                Section("內容") {
                    TextField("項目名稱", text: $name)
                    TextEditor(text: $content)
                        .frame(minHeight: 180)
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
                        onSave(name, content, sectionId)
                        dismiss()
                    }
                    .disabled(
                        sectionId.isEmpty ||
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .onAppear {
            sectionId = initialSectionId
            name = item?.name ?? ""
            content = item?.content ?? ""
        }
    }
}

private struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    var csv: String

    init(csv: String = "") {
        self.csv = csv
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            csv = String(decoding: data, as: UTF8.self)
        } else {
            csv = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}
