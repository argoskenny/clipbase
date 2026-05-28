import Foundation

struct ClipSection: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var items: [ClipItem]
}

struct ClipItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var content: String
    var metadata: String?
}

struct CSVRow: Hashable {
    let section: String
    let subsection: String
    let field: String
    let value: String
}

enum PromptAffixPlacement: String, Codable, CaseIterable, Hashable {
    case prefix
    case suffix

    var title: String {
        switch self {
        case .prefix:
            return "前綴"
        case .suffix:
            return "後綴"
        }
    }
}

struct PromptOptimizer: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var placement: PromptAffixPlacement
    var affixText: String
}
