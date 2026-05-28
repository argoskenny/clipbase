import Combine
import Foundation

@MainActor
final class ClipStore: ObservableObject {
    private static let persistenceKey = "clipbase.sections.v2"

    @Published private(set) var sections: [ClipSection] = []
    @Published var selectedSectionID: UUID?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    var selectedSection: ClipSection? {
        guard let selectedSectionID else {
            return sections.first
        }

        return sections.first(where: { $0.id == selectedSectionID })
    }

    func load() {
        if loadPersistedSections() == false {
            resetFromCSV()
        } else if selectedSectionID == nil {
            selectedSectionID = sections.first?.id
        }
    }

    func resetFromCSV() {
        sections = makeSectionsFromBundledCSV()
        selectedSectionID = sections.first?.id
        persistSections()
    }

    func addSection(title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else {
            return
        }

        let resolvedTitle = uniqueSectionTitle(from: trimmedTitle)
        let section = ClipSection(id: UUID(), title: resolvedTitle, items: [])
        sections.append(section)
        selectedSectionID = section.id
        persistSections()
    }

    func addItem(name: String, content: String, to sectionID: UUID) {
        guard let sectionIndex = sections.firstIndex(where: { $0.id == sectionID }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false, trimmedContent.isEmpty == false else {
            return
        }

        let item = ClipItem(id: UUID(), name: trimmedName, content: trimmedContent, metadata: nil)
        sections[sectionIndex].items.insert(item, at: 0)
        selectedSectionID = sectionID
        persistSections()
    }

    func moveItem(_ itemID: UUID, to destinationSectionID: UUID) {
        guard let sourceSectionIndex = sections.firstIndex(where: { section in
            section.items.contains(where: { $0.id == itemID })
        }) else {
            return
        }

        guard let destinationSectionIndex = sections.firstIndex(where: { $0.id == destinationSectionID }) else {
            return
        }

        guard sourceSectionIndex != destinationSectionIndex else {
            return
        }

        guard let itemIndex = sections[sourceSectionIndex].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        let item = sections[sourceSectionIndex].items.remove(at: itemIndex)
        sections[destinationSectionIndex].items.insert(item, at: 0)
        selectedSectionID = destinationSectionID
        persistSections()
    }

    func deleteItem(_ itemID: UUID) {
        guard let sectionIndex = sections.firstIndex(where: { section in
            section.items.contains(where: { $0.id == itemID })
        }) else {
            return
        }

        guard let itemIndex = sections[sectionIndex].items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        sections[sectionIndex].items.remove(at: itemIndex)
        selectedSectionID = sections[sectionIndex].id
        persistSections()
    }

    private func loadPersistedSections() -> Bool {
        guard
            let data = UserDefaults.standard.data(forKey: Self.persistenceKey),
            let decodedSections = try? decoder.decode([ClipSection].self, from: data),
            decodedSections.isEmpty == false
        else {
            return false
        }

        sections = decodedSections
        return true
    }

    private func persistSections() {
        guard let data = try? encoder.encode(sections) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.persistenceKey)
    }

    private func uniqueSectionTitle(from proposedTitle: String) -> String {
        guard sections.contains(where: { $0.title == proposedTitle }) else {
            return proposedTitle
        }

        var index = 2
        while sections.contains(where: { $0.title == "\(proposedTitle) (\(index))" }) {
            index += 1
        }

        return "\(proposedTitle) (\(index))"
    }

    private func makeSectionsFromBundledCSV() -> [ClipSection] {
        guard let csvText = loadBundledCSVText() else {
            return []
        }

        let rows = CSVParser.rows(from: csvText)
        var sectionOrder: [String] = []
        var regularItemsBySection: [String: [ClipItem]] = [:]
        var customGroups: [String: (message: String?, createdAt: String?)] = [:]
        var customOrder: [String] = []

        for row in rows where row.section.isEmpty == false {
            if sectionOrder.contains(row.section) == false {
                sectionOrder.append(row.section)
            }

            if row.section == "📝 自定義項目" {
                if customOrder.contains(row.subsection) == false {
                    customOrder.append(row.subsection)
                }

                var group = customGroups[row.subsection] ?? (message: nil, createdAt: nil)

                switch row.field {
                case "訊息":
                    group.message = row.value
                case "建立時間":
                    group.createdAt = row.value
                default:
                    if group.message == nil {
                        group.message = row.value
                    }
                }

                customGroups[row.subsection] = group
                continue
            }

            let itemName = makeItemName(subsection: row.subsection, field: row.field)
            let item = ClipItem(id: UUID(), name: itemName, content: row.value, metadata: nil)
            regularItemsBySection[row.section, default: []].append(item)
        }

        return sectionOrder.map { sectionTitle in
            if sectionTitle == "📝 自定義項目" {
                let items = customOrder.map { name in
                    let data = customGroups[name] ?? (message: nil, createdAt: nil)
                    return ClipItem(
                        id: UUID(),
                        name: name,
                        content: data.message ?? "",
                        metadata: data.createdAt.map { "建立時間：\($0)" }
                    )
                }

                return ClipSection(id: UUID(), title: sectionTitle, items: items)
            }

            return ClipSection(
                id: UUID(),
                title: sectionTitle,
                items: regularItemsBySection[sectionTitle, default: []]
            )
        }
    }

    private func loadBundledCSVText() -> String? {
        for url in candidateCSVURLs() {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }

        return nil
    }

    private func makeItemName(subsection: String, field: String) -> String {
        guard subsection.isEmpty == false else {
            return field
        }

        return "\(subsection) / \(field)"
    }

    private func candidateCSVURLs() -> [URL] {
        var urls: [URL] = []
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        urls.append(currentDirectoryURL.appendingPathComponent("src.csv"))
        urls.append(currentDirectoryURL.appendingPathComponent("Sources/ClipBaseApp/Resources/src.csv"))

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent("src.csv"))
            urls.append(resourceURL.appendingPathComponent("Clip_Clip.bundle/src.csv"))
        }

        return urls.uniqued()
    }
}

private extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seenPaths = Set<String>()

        return filter { url in
            let inserted = seenPaths.insert(url.path).inserted
            return inserted
        }
    }
}
