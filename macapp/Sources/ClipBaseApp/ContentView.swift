import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var clipStore: ClipStore
    @ObservedObject var optimizerStore: PromptOptimizerStore

    var body: some View {
        TabView {
            ClipLibraryView(store: clipStore)
                .tabItem {
                    Label("剪貼內容", systemImage: "list.bullet.rectangle")
                }

            PromptOptimizerPage(store: optimizerStore)
                .tabItem {
                    Label("提示詞優化器", systemImage: "wand.and.stars")
                }
        }
        .frame(minWidth: 1500, minHeight: 720)
    }
}

private struct ClipLibraryView: View {
    @ObservedObject var store: ClipStore

    @State private var isPresentingAddItemSheet = false
    @State private var isPresentingAddCategorySheet = false
    @State private var copiedItemID: UUID?
    @State private var draftSectionID: UUID?

    var body: some View {
        NavigationSplitView {
            List(store.sections, selection: $store.selectedSectionID) { section in
                Text(section.title)
                    .tag(Optional(section.id))
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            GeometryReader { geometry in
                let contentWidth = max(geometry.size.width - 40, 1000)
                let nameColumnWidth = contentWidth * 0.2
                let bodyColumnWidth = contentWidth * 0.6
                let actionColumnWidth = contentWidth * 0.2

                if let section = store.selectedSection {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(section.title)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text("共 \(section.items.count) 項")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("新增項目") {
                                openAddItemSheet(for: section.id)
                            }
                        }

                        Table(section.items) {
                            TableColumn("項目名稱") { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)

                                    if let metadata = item.metadata {
                                        Text(metadata)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .width(min: nameColumnWidth, ideal: nameColumnWidth, max: nameColumnWidth)

                            TableColumn("項目內容") { item in
                                Text(item.content)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .width(min: bodyColumnWidth, ideal: bodyColumnWidth, max: bodyColumnWidth)

                            TableColumn("操作") { item in
                                HStack(spacing: 4) {
                                    Button(copiedItemID == item.id ? "已複製" : "複製") {
                                        copyClipItem(item)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .frame(width: 56)
                                    .fixedSize()

                                    Menu {
                                        ForEach(store.sections) { destination in
                                            Button(destination.title) {
                                                store.moveItem(item.id, to: destination.id)
                                            }
                                            .disabled(destination.id == section.id)
                                        }
                                    } label: {
                                        Text("移動")
                                            .frame(width: 56)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .fixedSize()

                                    Button("刪除") {
                                        store.deleteItem(item.id)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .frame(width: 56)
                                    .fixedSize()
                                }
                                .frame(width: actionColumnWidth, alignment: .leading)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .width(min: actionColumnWidth, ideal: actionColumnWidth, max: actionColumnWidth)
                        }
                    }
                    .padding(20)
                } else {
                    VStack(spacing: 12) {
                        Text("沒有可顯示的項目")
                            .font(.headline)
                        Text("可以先從 `src.csv` 匯入，或直接新增種類與項目。")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("從 CSV 重建") {
                                store.resetFromCSV()
                            }

                            Button("新增種類") {
                                isPresentingAddCategorySheet = true
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(isPresented: $isPresentingAddItemSheet) {
            AddItemSheet(
                sections: store.sections,
                initialSectionID: draftSectionID ?? store.selectedSectionID,
                onSave: { name, content, sectionID in
                    store.addItem(name: name, content: content, to: sectionID)
                }
            )
        }
        .sheet(isPresented: $isPresentingAddCategorySheet) {
            AddCategorySheet { title in
                store.addSection(title: title)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("從 CSV 重建") {
                    store.resetFromCSV()
                }

                Button("新增種類") {
                    isPresentingAddCategorySheet = true
                }

                Button("新增項目") {
                    openAddItemSheet(for: store.selectedSectionID ?? store.sections.first?.id)
                }
                .disabled(store.sections.isEmpty)
            }
        }
    }

    private func openAddItemSheet(for sectionID: UUID?) {
        draftSectionID = sectionID
        isPresentingAddItemSheet = true
    }

    private func copyClipItem(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)

        copiedItemID = item.id

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedItemID == item.id {
                copiedItemID = nil
            }
        }
    }
}

private struct PromptOptimizerPage: View {
    @ObservedObject var store: PromptOptimizerStore

    @State private var isPresentingAddOptimizerSheet = false
    @State private var optimizerInput = ""
    @State private var copiedOptimizerID: UUID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(store.optimizers, selection: $store.selectedOptimizerID) { optimizer in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(optimizer.title)
                        Text(optimizer.placement.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(Optional(optimizer.id))
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)

                Divider()

                Button {
                    isPresentingAddOptimizerSheet = true
                } label: {
                    Label("新增優化器", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(16)
            }
        } detail: {
            if let optimizer = store.selectedOptimizer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(optimizer.title)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                Text(optimizer.placement == .prefix ? "前綴段落" : "後綴段落")
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(copiedOptimizerID == optimizer.id ? "已複製" : "複製") {
                                copyOptimizerPrompt(optimizer)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(optimizer.placement.title)
                                .font(.headline)

                            Text(optimizer.affixText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("輸入內容")
                                .font(.headline)

                            TextEditor(text: $optimizerInput)
                                .font(.body)
                                .frame(minHeight: 260)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                }
                        }
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 12) {
                    Text("沒有可顯示的優化器")
                        .font(.headline)
                    Text("先新增一個前綴或後綴優化器。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isPresentingAddOptimizerSheet) {
            AddOptimizerSheet { title, placement, affixText in
                store.addOptimizer(title: title, placement: placement, affixText: affixText)
            }
        }
    }

    private func copyOptimizerPrompt(_ optimizer: PromptOptimizer) {
        let combinedText = combinedPrompt(for: optimizer, input: optimizerInput)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(combinedText, forType: .string)

        copiedOptimizerID = optimizer.id

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedOptimizerID == optimizer.id {
                copiedOptimizerID = nil
            }
        }
    }

    private func combinedPrompt(for optimizer: PromptOptimizer, input: String) -> String {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let affixText = optimizer.affixText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedInput.isEmpty {
            return affixText
        }

        switch optimizer.placement {
        case .prefix:
            return [affixText, trimmedInput]
                .filter { $0.isEmpty == false }
                .joined(separator: "\n\n")
        case .suffix:
            return [trimmedInput, affixText]
                .filter { $0.isEmpty == false }
                .joined(separator: "\n\n")
        }
    }
}

private struct AddItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sections: [ClipSection]
    let onSave: (String, String, UUID) -> Void

    @State private var name = ""
    @State private var content = ""
    @State private var selectedSectionID: UUID

    init(
        sections: [ClipSection],
        initialSectionID: UUID?,
        onSave: @escaping (String, String, UUID) -> Void
    ) {
        self.sections = sections
        self.onSave = onSave
        let fallbackID = initialSectionID ?? sections.first?.id ?? UUID()
        _selectedSectionID = State(initialValue: fallbackID)
    }

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        sections.contains(where: { $0.id == selectedSectionID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增項目")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("種類")

                Picker("種類", selection: $selectedSectionID) {
                    ForEach(sections) { section in
                        Text(section.title).tag(section.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("項目名稱")
                TextField("例如：帳號", text: $name)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("項目內容")
                TextEditor(text: $content)
                    .font(.body)
                    .frame(minHeight: 120)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
            }

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button("儲存") {
                    onSave(name, content, selectedSectionID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canSave == false)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct AddCategorySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""

    let onSave: (String) -> Void

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增種類")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("種類名稱")
                TextField("例如：測試帳號", text: $title)
            }

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button("儲存") {
                    onSave(title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canSave == false)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct AddOptimizerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, PromptAffixPlacement, String) -> Void

    @State private var title = ""
    @State private var placement: PromptAffixPlacement = .prefix
    @State private var affixText = ""

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        affixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增優化器")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("優化器名稱")
                TextField("例如：英文潤稿器", text: $title)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("類型")

                Picker("類型", selection: $placement) {
                    ForEach(PromptAffixPlacement.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(placement == .prefix ? "前綴內容" : "後綴內容")
                TextEditor(text: $affixText)
                    .font(.body)
                    .frame(minHeight: 180)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
            }

            HStack {
                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button("儲存") {
                    onSave(title, placement, affixText)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(canSave == false)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
