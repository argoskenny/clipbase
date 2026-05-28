import Foundation

typealias Milliseconds = Int64

enum PromptPlacement: String, Codable, CaseIterable, Identifiable {
    case prefix
    case suffix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prefix:
            return "前綴"
        case .suffix:
            return "後綴"
        }
    }
}

struct CopyableRange: Codable, Hashable, Identifiable {
    var start: Int
    var end: Int

    var id: String {
        "\(start)-\(end)"
    }
}

struct MemoTextSegment: Hashable, Identifiable {
    let id = UUID()
    var text: String
    var isCopyable: Bool
}

struct ClipSection: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var position: Int
    var updatedAt: Milliseconds
    var deletedAt: Milliseconds?
}

struct ClipItem: Identifiable, Codable, Hashable {
    var id: String
    var sectionId: String
    var name: String
    var content: String
    var metadata: String?
    var position: Int
    var updatedAt: Milliseconds
    var deletedAt: Milliseconds?
}

struct PromptOptimizer: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var placement: PromptPlacement
    var affixText: String
    var position: Int
    var updatedAt: Milliseconds
    var deletedAt: Milliseconds?
}

struct MemoDocument: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var content: String
    var copyableRanges: [CopyableRange]
    var position: Int
    var updatedAt: Milliseconds
    var deletedAt: Milliseconds?
}

struct SyncChanges: Codable, Equatable {
    var sections: [ClipSection] = []
    var items: [ClipItem] = []
    var optimizers: [PromptOptimizer] = []
    var memoDocuments: [MemoDocument] = []

    var isEmpty: Bool {
        sections.isEmpty && items.isEmpty && optimizers.isEmpty && memoDocuments.isEmpty
    }
}

struct SyncResponse: Codable {
    var serverTime: Milliseconds
    var changes: SyncChanges
}

struct LoginResponse: Decodable {
    var username: String
    var token: String?
}

struct ClipBaseSnapshot: Codable, Equatable {
    static let defaultBaseURL = "https://clipbase.thelonesomeera.com/"

    var sections: [ClipSection] = []
    var items: [ClipItem] = []
    var optimizers: [PromptOptimizer] = []
    var memoDocuments: [MemoDocument] = []
    var lastSyncAt: Milliseconds = 0
    var baseURL: String = Self.defaultBaseURL
    var username: String?

    static let empty = ClipBaseSnapshot()
}

enum ClipBaseDomainError: LocalizedError, Equatable {
    case validation(String)
    case notFound(String)
    case protectedSection

    var errorDescription: String? {
        switch self {
        case .validation(let message), .notFound(let message):
            return message
        case .protectedSection:
            return "其它分類不可刪除"
        }
    }
}
