import SwiftUI

struct PromptOptimizersView: View {
    @ObservedObject var store: ClipBaseStore
    @State private var selectedOptimizerId: String?
    @State private var searchText = ""
    @State private var input = ""
    @State private var sheetState: OptimizerSheetState?
    @State private var pendingDelete: PromptOptimizer?

    private var selectedOptimizer: PromptOptimizer? {
        if let selectedOptimizerId, let optimizer = store.optimizers.first(where: { $0.id == selectedOptimizerId }) {
            return optimizer
        }
        return store.optimizers.first
    }

    private var filteredOptimizers: [PromptOptimizer] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.optimizers }
        return store.optimizers.filter { optimizer in
            [optimizer.title, optimizer.affixText, optimizer.placement.rawValue]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private var combinedPrompt: String {
        selectedOptimizer?.mergedPrompt(input: input) ?? ""
    }

    var body: some View {
        HSplitView {
            optimizerList
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            detail
                .frame(minWidth: 680)
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: store.optimizers) { _ in reconcileSelection() }
        .sheet(item: $sheetState) { state in
            OptimizerEditorSheet(state: state) { title, placement, affixText in
                switch state.mode {
                case .create:
                    store.createOptimizer(title: title, placement: placement, affixText: affixText)
                case .edit(let optimizer):
                    store.updateOptimizer(id: optimizer.id, title: title, placement: placement, affixText: affixText)
                }
            }
        }
        .confirmationDialog("刪除優化器", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            if let optimizer = pendingDelete {
                Button("刪除「\(optimizer.title)」", role: .destructive) {
                    store.deleteOptimizer(id: optimizer.id)
                    pendingDelete = nil
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var optimizerList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("優化器")
                        .font(.headline)
                    Text("\(store.optimizers.count) 個模板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    sheetState = OptimizerSheetState(mode: .create)
                } label: {
                    Label("新增優化器", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .help("新增優化器")
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜尋名稱或內容", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.bottom, 8)

            List(selection: $selectedOptimizerId) {
                ForEach(filteredOptimizers) { optimizer in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(optimizer.title)
                            .lineLimit(1)
                        Text(optimizer.placement.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(optimizer.id as String?)
                    .contextMenu {
                        Button("編輯") {
                            sheetState = OptimizerSheetState(mode: .edit(optimizer))
                        }
                        Button("刪除", role: .destructive) {
                            pendingDelete = optimizer
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let selectedOptimizer {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedOptimizer.title)
                                .font(.title2.bold())
                            Text(selectedOptimizer.placement == .prefix ? "前綴會放在輸入內容之前" : "後綴會放在輸入內容之後")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            sheetState = OptimizerSheetState(mode: .edit(selectedOptimizer))
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }
                        Button {
                            store.copy(combinedPrompt)
                        } label: {
                            Label("複製結果", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        Button(role: .destructive) {
                            pendingDelete = selectedOptimizer
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                    }
                }
                .panelPadding()

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        editorBlock(title: "輸入內容") {
                            TextEditor(text: $input)
                                .font(.body)
                                .frame(minHeight: 140)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                        }

                        editorBlock(title: "合併結果") {
                            VStack(alignment: .trailing, spacing: 8) {
                                ScrollView {
                                    Text(combinedPrompt.isEmpty ? " " : combinedPrompt)
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                }
                                .frame(minHeight: 180)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

                                Button {
                                    store.copy(combinedPrompt)
                                } label: {
                                    Label("複製", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        editorBlock(title: selectedOptimizer.placement == .prefix ? "固定前綴" : "固定後綴") {
                            Text(selectedOptimizer.affixText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(20)
                }
            } else {
                EmptyStateView(title: "請先新增一個優化器", systemImage: "sparkles")
            }
        }
    }

    private func editorBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func reconcileSelection() {
        if let selectedOptimizerId, store.optimizers.contains(where: { $0.id == selectedOptimizerId }) {
            return
        }
        selectedOptimizerId = store.optimizers.first?.id
    }
}

struct OptimizerSheetState: Identifiable {
    enum Mode {
        case create
        case edit(PromptOptimizer)
    }

    let id = UUID()
    let mode: Mode
}

private struct OptimizerEditorSheet: View {
    let state: OptimizerSheetState
    let onSave: (String, OptimizerPlacement, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var placement: OptimizerPlacement
    @State private var affixText: String

    init(state: OptimizerSheetState, onSave: @escaping (String, OptimizerPlacement, String) -> Void) {
        self.state = state
        self.onSave = onSave
        switch state.mode {
        case .create:
            _title = State(initialValue: "")
            _placement = State(initialValue: .prefix)
            _affixText = State(initialValue: "")
        case .edit(let optimizer):
            _title = State(initialValue: optimizer.title)
            _placement = State(initialValue: optimizer.placement)
            _affixText = State(initialValue: optimizer.affixText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sheetTitle)
                .font(.title3.bold())

            TextField("優化器名稱", text: $title)
                .textFieldStyle(.roundedBorder)

            Picker("類型", selection: $placement) {
                ForEach(OptimizerPlacement.allCases, id: \.self) { placement in
                    Text(placement.displayName).tag(placement)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $affixText)
                .font(.body)
                .frame(height: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("儲存") {
                    onSave(title, placement, affixText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || affixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 560)
    }

    private var sheetTitle: String {
        switch state.mode {
        case .create: return "新增優化器"
        case .edit: return "編輯優化器"
        }
    }
}
