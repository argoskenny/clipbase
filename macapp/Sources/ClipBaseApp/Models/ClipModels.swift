import Foundation

struct ClipSection: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var position: Int
    var updatedAt: Int64
    var deletedAt: Int64?

    var effectiveTime: Int64 {
        max(updatedAt, deletedAt ?? 0)
    }
}

struct ClipItem: Codable, Identifiable, Equatable {
    var id: String
    var sectionId: String
    var name: String
    var content: String
    var metadata: String?
    var position: Int
    var updatedAt: Int64
    var deletedAt: Int64?

    var effectiveTime: Int64 {
        max(updatedAt, deletedAt ?? 0)
    }
}

enum OptimizerPlacement: String, Codable, CaseIterable, Equatable {
    case prefix
    case suffix

    var displayName: String {
        switch self {
        case .prefix: return "前綴"
        case .suffix: return "後綴"
        }
    }
}

struct PromptOptimizer: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var placement: OptimizerPlacement
    var affixText: String
    var position: Int
    var updatedAt: Int64
    var deletedAt: Int64?

    var effectiveTime: Int64 {
        max(updatedAt, deletedAt ?? 0)
    }

    func mergedPrompt(input: String) -> String {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAffix = affixText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedInput.isEmpty else {
            return trimmedAffix
        }

        switch placement {
        case .prefix:
            return [trimmedAffix, trimmedInput].filter { !$0.isEmpty }.joined(separator: "\n\n")
        case .suffix:
            return [trimmedInput, trimmedAffix].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }
}

struct CopyableRange: Codable, Hashable, Equatable {
    var start: Int
    var end: Int
}

struct MemoDocument: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var content: String
    var copyableRanges: [CopyableRange]
    var position: Int
    var updatedAt: Int64
    var deletedAt: Int64?

    var effectiveTime: Int64 {
        max(updatedAt, deletedAt ?? 0)
    }
}

struct SyncChanges: Codable, Equatable {
    var sections: [ClipSection]
    var items: [ClipItem]
    var optimizers: [PromptOptimizer]
    var memoDocuments: [MemoDocument]

    static let empty = SyncChanges(sections: [], items: [], optimizers: [], memoDocuments: [])

    var isEmpty: Bool {
        sections.isEmpty && items.isEmpty && optimizers.isEmpty && memoDocuments.isEmpty
    }
}

struct ClipBaseSnapshot: Codable, Equatable {
    var sections: [ClipSection] = []
    var items: [ClipItem] = []
    var optimizers: [PromptOptimizer] = []
    var memoDocuments: [MemoDocument] = []
    var lastSyncAt: Int64 = 0
}

struct ClipBaseBackup: Codable, Equatable {
    var version: Int
    var exportedAt: Int64
    var changes: SyncChanges
}

enum AppFeature: String, CaseIterable, Identifiable {
    case clips
    case optimizers
    case memos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clips: return "剪貼內容"
        case .optimizers: return "提示詞優化器"
        case .memos: return "備忘文件"
        }
    }

    var systemImage: String {
        switch self {
        case .clips: return "tray.full"
        case .optimizers: return "sparkles"
        case .memos: return "doc.text"
        }
    }
}

struct UserFacingAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct UserFacingToast: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
