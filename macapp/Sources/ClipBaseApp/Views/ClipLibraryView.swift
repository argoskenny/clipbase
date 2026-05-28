import SwiftUI

struct ClipLibraryView: View {
    @ObservedObject var store: ClipBaseStore
    @State private var selectedSectionId: String?
    @State private var searchText = ""
    @State private var sectionSheet: SectionSheetState?
    @State private var itemSheet: ItemSheetState?
    @State private var pendingSectionDelete: ClipSection?
    @State private var pendingItemDelete: ClipItem?

    private var selectedSection: ClipSection? {
        if let selectedSectionId, let section = store.sections.first(where: { $0.id == selectedSectionId }) {
            return section
        }
        return store.sections.first
    }

    private var filteredItems: [ClipItem] {
        guard let selectedSection else { return [] }
        let items = store.items(in: selectedSection.id)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { item in
            [item.name, item.content, item.metadata ?? ""]
                .contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        HSplitView {
            sectionList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

            detail
                .frame(minWidth: 680)
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: store.sections) { _ in reconcileSelection() }
        .sheet(item: $sectionSheet) { state in
            SectionEditorSheet(state: state) { title in
                switch state.mode {
                case .create:
                    store.createSection(title: title)
                case .edit(let section):
                    store.updateSection(id: section.id, title: title)
                }
            }
        }
        .sheet(item: $itemSheet) { state in
            ItemEditorSheet(state: state, sections: store.sections) { name, content, sectionId in
                switch state.mode {
                case .create:
                    store.createItem(sectionId: sectionId, name: name, content: content)
                    selectedSectionId = sectionId
                case .edit(let item):
                    store.updateItem(id: item.id, sectionId: sectionId, name: name, content: content)
                    selectedSectionId = sectionId
                }
            }
        }
        .confirmationDialog("刪除分類", isPresented: Binding(
            get: { pendingSectionDelete != nil },
            set: { if !$0 { pendingSectionDelete = nil } }
        )) {
            if let section = pendingSectionDelete {
                Button("刪除「\(section.title)」", role: .destructive) {
                    store.deleteSection(id: section.id)
                    pendingSectionDelete = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("分類內項目會移到「其它」。")
        }
        .confirmationDialog("刪除項目", isPresented: Binding(
            get: { pendingItemDelete != nil },
            set: { if !$0 { pendingItemDelete = nil } }
        )) {
            if let item = pendingItemDelete {
                Button("刪除「\(item.name)」", role: .destructive) {
                    store.deleteItem(id: item.id)
                    pendingItemDelete = nil
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var sectionList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("分類")
                        .font(.headline)
                    Text("\(store.sections.count) 個分類")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    sectionSheet = SectionSheetState(mode: .create)
                } label: {
                    Label("新增分類", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("新增分類")
            }
            .padding()

            List(selection: $selectedSectionId) {
                ForEach(store.sections) { section in
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .lineLimit(1)
                            Text("\(store.items(in: section.id).count) 項")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(section.id as String?)
                    .contextMenu {
                        Button("編輯") {
                            sectionSheet = SectionSheetState(mode: .edit(section))
                        }
                        Button("刪除", role: .destructive) {
                            pendingSectionDelete = section
                        }
                        .disabled(section.title == "其它")
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let selectedSection {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedSection.title)
                                .font(.title2.bold())
                            Text(searchText.isEmpty ? "\(store.items(in: selectedSection.id).count) 個可複製項目" : "找到 \(filteredItems.count) 個項目")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            sectionSheet = SectionSheetState(mode: .edit(selectedSection))
                        } label: {
                            Label("編輯分類", systemImage: "pencil")
                        }
                        Button {
                            itemSheet = ItemSheetState(mode: .create(sectionId: selectedSection.id))
                        } label: {
                            Label("新增項目", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜尋名稱、內容或備註", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                .panelPadding()

                Divider()

                if filteredItems.isEmpty {
                    EmptyStateView(
                        title: store.items(in: selectedSection.id).isEmpty ? "這個分類目前沒有項目" : "沒有符合搜尋的項目",
                        systemImage: "tray"
                    )
                } else {
                    List {
                        ForEach(filteredItems) { item in
                            ClipItemRow(
                                item: item,
                                sections: store.sections,
                                currentSectionId: selectedSection.id,
                                onCopy: { store.copy(item.content) },
                                onMove: { destinationId in
                                    selectedSectionId = destinationId
                                    store.moveItem(id: item.id, sectionId: destinationId)
                                },
                                onEdit: { itemSheet = ItemSheetState(mode: .edit(item)) },
                                onDelete: { pendingItemDelete = item }
                            )
                            .padding(.vertical, 6)
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                EmptyStateView(title: "請先新增分類或匯入 CSV", systemImage: "folder.badge.plus")
            }
        }
    }

    private func reconcileSelection() {
        if let selectedSectionId, store.sections.contains(where: { $0.id == selectedSectionId }) {
            return
        }
        selectedSectionId = store.sections.first?.id
    }
}

private struct ClipItemRow: View {
    let item: ClipItem
    let sections: [ClipSection]
    let currentSectionId: String
    let onCopy: () -> Void
    let onMove: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name)
                    .font(.headline)
                Text(item.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineLimit(3)
                if let metadata = item.metadata {
                    Text(metadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 20)
            Picker("移動", selection: Binding(
                get: { currentSectionId },
                set: { onMove($0) }
            )) {
                ForEach(sections) { section in
                    Text(section.title).tag(section.id)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Button(action: onCopy) {
                Label("複製", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)

            Button(action: onEdit) {
                Label("編輯", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help("編輯")

            Button(role: .destructive, action: onDelete) {
                Label("刪除", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .help("刪除")
        }
    }
}

struct SectionSheetState: Identifiable {
    enum Mode {
        case create
        case edit(ClipSection)
    }

    let id = UUID()
    let mode: Mode
}

private struct SectionEditorSheet: View {
    let state: SectionSheetState
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String

    init(state: SectionSheetState, onSave: @escaping (String) -> Void) {
        self.state = state
        self.onSave = onSave
        switch state.mode {
        case .create:
            _title = State(initialValue: "")
        case .edit(let section):
            _title = State(initialValue: section.title)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(sheetTitle)
                .font(.title3.bold())
            TextField("分類名稱", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("儲存") {
                    onSave(title)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private var sheetTitle: String {
        switch state.mode {
        case .create: return "新增分類"
        case .edit: return "編輯分類"
        }
    }
}

struct ItemSheetState: Identifiable {
    enum Mode {
        case create(sectionId: String)
        case edit(ClipItem)
    }

    let id = UUID()
    let mode: Mode
}

private struct ItemEditorSheet: View {
    let state: ItemSheetState
    let sections: [ClipSection]
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sectionId: String
    @State private var name: String
    @State private var content: String

    init(state: ItemSheetState, sections: [ClipSection], onSave: @escaping (String, String, String) -> Void) {
        self.state = state
        self.sections = sections
        self.onSave = onSave
        switch state.mode {
        case .create(let sectionId):
            _sectionId = State(initialValue: sectionId)
            _name = State(initialValue: "")
            _content = State(initialValue: "")
        case .edit(let item):
            _sectionId = State(initialValue: item.sectionId)
            _name = State(initialValue: item.name)
            _content = State(initialValue: item.content)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sheetTitle)
                .font(.title3.bold())

            Picker("分類", selection: $sectionId) {
                ForEach(sections) { section in
                    Text(section.title).tag(section.id)
                }
            }

            TextField("項目名稱", text: $name)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $content)
                .font(.body)
                .frame(height: 180)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("儲存") {
                    onSave(name, content, sectionId)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 520)
    }

    private var sheetTitle: String {
        switch state.mode {
        case .create: return "新增項目"
        case .edit: return "編輯項目"
        }
    }
}
