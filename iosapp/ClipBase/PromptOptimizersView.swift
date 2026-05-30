import SwiftUI

struct PromptOptimizersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedOptimizerId: String?
    @State private var input = ""
    @State private var searchText = ""
    @State private var activeSheet: OptimizerSheet?

    private var optimizers: [PromptOptimizer] {
        let rows = model.snapshot.activeOptimizers
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return rows
        }
        return rows.filter { optimizer in
            [optimizer.title, optimizer.affixText, optimizer.placement.rawValue].contains { $0.lowercased().contains(query) }
        }
    }

    private var selectedOptimizer: PromptOptimizer? {
        if let selectedOptimizerId, let optimizer = model.snapshot.activeOptimizers.first(where: { $0.id == selectedOptimizerId }) {
            return optimizer
        }
        return model.snapshot.activeOptimizers.first
    }

    private var combinedPrompt: String {
        guard let selectedOptimizer else {
            return ""
        }
        return DomainRules.mergedPrompt(input: input, optimizer: selectedOptimizer)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedOptimizerId) {
                Section {
                    ForEach(optimizers) { optimizer in
                        NavigationLink(value: optimizer.id) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(optimizer.title)
                                    .lineLimit(1)
                                Text(optimizer.placement.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button {
                                activeSheet = .edit(optimizer)
                            } label: {
                                Label("編輯", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                model.deleteOptimizer(id: optimizer.id)
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    SectionHeaderCount(title: "優化器", count: model.snapshot.activeOptimizers.count)
                }
            }
            .searchable(text: $searchText, prompt: "搜尋優化器")
            .navigationTitle("提示詞")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .new
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                }
            }
        } detail: {
            NavigationStack {
                if let optimizer = selectedOptimizer {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(optimizer.title)
                                        .font(.title2.weight(.semibold))
                                    Text(optimizer.placement == .prefix ? "固定內容會放在輸入前" : "固定內容會放在輸入後")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button {
                                        activeSheet = .edit(optimizer)
                                    } label: {
                                        Label("編輯", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        model.deleteOptimizer(id: optimizer.id)
                                    } label: {
                                        Label("刪除", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                            }

                            LabeledTextEditor(title: "輸入內容", text: $input, minHeight: 160)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("合併結果")
                                        .font(.headline)
                                    Spacer()
                                    CopyButton(text: combinedPrompt)
                                        .buttonStyle(.borderedProminent)
                                }
                                Text(combinedPrompt.isEmpty ? " " : combinedPrompt)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(optimizer.placement == .prefix ? "固定前綴" : "固定後綴")
                                    .font(.headline)
                                Text(optimizer.affixText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding()
                    }
                    .navigationTitle(optimizer.title)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            CopyButton(text: combinedPrompt)
                        }
                    }
                } else {
                    EmptyStateView(title: "尚無優化器", message: "新增固定前綴或後綴模板後即可合併並複製提示詞。", systemImage: "wand.and.stars")
                        .navigationTitle("提示詞")
                        .toolbar {
                            Button {
                                activeSheet = .new
                            } label: {
                                Label("新增", systemImage: "plus")
                            }
                        }
                }
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: model.snapshot.activeOptimizers) {
            ensureSelection()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .new:
                OptimizerEditorView(title: "新增優化器") { title, placement, affixText in
                    if let id = model.createOptimizer(title: title, placement: placement, affixText: affixText) {
                        selectedOptimizerId = id
                    }
                }
            case .edit(let optimizer):
                OptimizerEditorView(title: "編輯優化器", optimizer: optimizer) { title, placement, affixText in
                    model.updateOptimizer(id: optimizer.id, title: title, placement: placement, affixText: affixText)
                }
            }
        }
    }

    private func ensureSelection() {
        if let selectedOptimizerId, model.snapshot.activeOptimizers.contains(where: { $0.id == selectedOptimizerId }) {
            return
        }
        selectedOptimizerId = model.snapshot.activeOptimizers.first?.id
    }
}

private enum OptimizerSheet: Identifiable {
    case new
    case edit(PromptOptimizer)

    var id: String {
        switch self {
        case .new:
            return "new"
        case .edit(let optimizer):
            return optimizer.id
        }
    }
}

private struct OptimizerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var optimizer: PromptOptimizer?
    var onSave: (String, PromptPlacement, String) -> Void

    @State private var draftTitle = ""
    @State private var placement: PromptPlacement = .prefix
    @State private var affixText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("名稱") {
                    TextField("優化器名稱", text: $draftTitle)
                }
                Section("類型") {
                    Picker("類型", selection: $placement) {
                        ForEach(PromptPlacement.allCases) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section(placement == .prefix ? "前綴內容" : "後綴內容") {
                    TextEditor(text: $affixText)
                        .frame(minHeight: 220)
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
                        onSave(draftTitle, placement, affixText)
                        dismiss()
                    }
                    .disabled(
                        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        affixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .onAppear {
            draftTitle = optimizer?.title ?? ""
            placement = optimizer?.placement ?? .prefix
            affixText = optimizer?.affixText ?? ""
        }
    }
}
