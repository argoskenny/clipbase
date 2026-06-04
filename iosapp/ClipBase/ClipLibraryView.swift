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
        guard let selectedSectionId = DomainRules.validSectionSelection(current: selectedSectionId, sections: sections) else {
            return nil
        }
        return sections.first { $0.id == selectedSectionId }
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
                                    onMove: {
                                        activeSheet = .moveItem(item)
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
                            Button {
                                activeSheet = .newItem(section.id)
                            } label: {
                                Label("新增項目", systemImage: "plus")
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        title: sections.isEmpty ? "尚無分類" : "選擇分類",
                        message: sections.isEmpty ? "先新增分類，或匯入 Web 相容的四欄 CSV。" : "從左側分類列表選擇一個分類後，查看與管理項目。",
                        systemImage: "folder"
                    )
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
        .onChange(of: sections) {
            selectedSectionId = DomainRules.validSectionSelection(current: selectedSectionId, sections: sections)
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
            case .moveItem(let item):
                MoveItemView(title: "移動項目", sections: sections, currentSectionId: item.sectionId) { destinationId in
                    model.moveItem(id: item.id, to: destinationId)
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
            selectedSectionId = nil
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
    case moveItem(ClipItem)

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
        case .moveItem(let item):
            return "move-item-\(item.id)"
        }
    }
}

private struct ClipItemRow: View {
    var item: ClipItem
    var onMove: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.content)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .textSelection(.enabled)

                Text(item.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let metadata = item.metadata {
                    Text(metadata)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CopyButton(text: item.content)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityLabel("複製 \(item.name)")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onMove()
            } label: {
                Label("移動", systemImage: "folder")
            }
            .tint(.indigo)

            Button {
                onEdit()
            } label: {
                Label("編輯", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("編輯", systemImage: "pencil")
            }

            Button {
                onMove()
            } label: {
                Label("移動", systemImage: "folder")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
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

private struct MoveItemView: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var sections: [ClipSection]
    var currentSectionId: String
    var onMove: (String) -> Void

    @State private var destinationSectionId = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("目的分類") {
                    Picker("分類", selection: $destinationSectionId) {
                        ForEach(sections) { section in
                            Text(section.title).tag(section.id)
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
                    Button("移動") {
                        onMove(destinationSectionId)
                        dismiss()
                    }
                    .disabled(destinationSectionId.isEmpty || destinationSectionId == currentSectionId)
                }
            }
        }
        .onAppear {
            destinationSectionId = currentSectionId
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
