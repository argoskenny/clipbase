import Combine
import Foundation

@MainActor
final class PromptOptimizerStore: ObservableObject {
    private static let persistenceKey = "clipbase.prompt-optimizers.v1"

    @Published private(set) var optimizers: [PromptOptimizer] = []
    @Published var selectedOptimizerID: UUID?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    var selectedOptimizer: PromptOptimizer? {
        guard let selectedOptimizerID else {
            return optimizers.first
        }

        return optimizers.first(where: { $0.id == selectedOptimizerID })
    }

    func load() {
        if loadPersistedOptimizers() == false {
            optimizers = Self.defaultOptimizers
            persistOptimizers()
        }

        if selectedOptimizerID == nil {
            selectedOptimizerID = optimizers.first?.id
        }
    }

    func addOptimizer(title: String, placement: PromptAffixPlacement, affixText: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAffixText = affixText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedTitle.isEmpty == false, trimmedAffixText.isEmpty == false else {
            return
        }

        let optimizer = PromptOptimizer(
            id: UUID(),
            title: uniqueTitle(from: trimmedTitle),
            placement: placement,
            affixText: trimmedAffixText
        )

        optimizers.append(optimizer)
        selectedOptimizerID = optimizer.id
        persistOptimizers()
    }

    private func loadPersistedOptimizers() -> Bool {
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
            let decodedOptimizers = try? decoder.decode([PromptOptimizer].self, from: data),
            decodedOptimizers.isEmpty == false
        else {
            return false
        }

        optimizers = decodedOptimizers
        return true
    }

    private func persistOptimizers() {
        guard let data = try? encoder.encode(optimizers) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.persistenceKey)
    }

    private func uniqueTitle(from proposedTitle: String) -> String {
        guard optimizers.contains(where: { $0.title == proposedTitle }) else {
            return proposedTitle
        }

        var index = 2
        while optimizers.contains(where: { $0.title == "\(proposedTitle) (\(index))" }) {
            index += 1
        }

        return "\(proposedTitle) (\(index))"
    }

    private static let defaultOptimizers: [PromptOptimizer] = [
        PromptOptimizer(
            id: UUID(),
            title: "AI Coding Prompt 優化器",
            placement: .prefix,
            affixText: """
            請將我接下來提供的內容 優化為更清晰、結構化、且適合 AI coding agent（如 Codex / Cursor / GPT）理解與執行的提示詞。

            優化原則：
            保留原始需求與技術細節，不改變需求本身
            讓描述更清楚、可執行、避免歧義
            適度加入結構（例如條列、區塊、步驟）
            避免冗長敘述
            讓 AI 工具更容易理解修改目標與限制

            輸出規則：
            只輸出優化後的提示詞
            不要加入說明、分析或額外文字

            以下是需要優化的提示詞：
            """
        )
    ]
}
