import Foundation

final class LocalRepository {
    private let fileURL: URL
    private(set) var snapshot: ClipBaseSnapshot

    init(fileURL: URL = LocalRepository.defaultStoreURL()) {
        self.fileURL = fileURL
        self.snapshot = (try? Self.load(from: fileURL)) ?? ClipBaseSnapshot()
    }

    var lastSyncAt: Int64 {
        snapshot.lastSyncAt
    }

    var allSections: [ClipSection] { snapshot.sections }
    var allItems: [ClipItem] { snapshot.items }
    var allOptimizers: [PromptOptimizer] { snapshot.optimizers }
    var allMemoDocuments: [MemoDocument] { snapshot.memoDocuments }

    var activeSections: [ClipSection] {
        snapshot.sections
            .filter { $0.deletedAt == nil }
            .sorted { sortPositionTitle($0.position, $0.title, $1.position, $1.title) }
    }

    var activeOptimizers: [PromptOptimizer] {
        snapshot.optimizers
            .filter { $0.deletedAt == nil }
            .sorted { sortPositionTitle($0.position, $0.title, $1.position, $1.title) }
    }

    var activeMemoDocuments: [MemoDocument] {
        snapshot.memoDocuments
            .filter { $0.deletedAt == nil }
            .sorted { sortPositionTitle($0.position, $0.title, $1.position, $1.title) }
    }

    func activeItems(in sectionId: String) -> [ClipItem] {
        snapshot.items
            .filter { $0.deletedAt == nil && $0.sectionId == sectionId }
            .sorted { sortPositionTitle($0.position, $0.name, $1.position, $1.name) }
    }

    func localChanges(after since: Int64) -> SyncChanges {
        SyncChanges(
            sections: snapshot.sections.filter { $0.effectiveTime > since }.sorted(by: sortSection),
            items: snapshot.items.filter { $0.effectiveTime > since }.sorted(by: sortItem),
            optimizers: snapshot.optimizers.filter { $0.effectiveTime > since }.sorted(by: sortOptimizer),
            memoDocuments: snapshot.memoDocuments.filter { $0.effectiveTime > since }.sorted(by: sortMemo)
        )
    }

    @discardableResult
    func createSection(title: String, now: Int64 = Clock.nowMillis()) throws -> ClipSection {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw RepositoryError.validation("分類名稱不可空白")
        }

        let section = ClipSection(
            id: UUID().uuidString,
            title: uniqueActiveTitle(trimmedTitle, in: snapshot.sections.map { ($0.id, $0.title, $0.deletedAt) }),
            position: nextPosition(snapshot.sections.map(\.position)),
            updatedAt: now,
            deletedAt: nil
        )
        snapshot.sections.append(section)
        try persist()
        return section
    }

    @discardableResult
    func updateSection(id: String, title: String, now: Int64 = Clock.nowMillis()) throws -> ClipSection {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw RepositoryError.validation("分類名稱不可空白")
        }
        guard let index = snapshot.sections.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw RepositoryError.notFound("找不到分類")
        }

        snapshot.sections[index].title = uniqueActiveTitle(trimmedTitle, excludedId: id, in: snapshot.sections.map { ($0.id, $0.title, $0.deletedAt) })
        snapshot.sections[index].updatedAt = now
        snapshot.sections[index].deletedAt = nil
        try persist()
        return snapshot.sections[index]
    }

    @discardableResult
    func deleteSection(id: String, now: Int64 = Clock.nowMillis()) throws -> ClipSection {
        guard let index = snapshot.sections.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw RepositoryError.notFound("找不到分類")
        }
        guard snapshot.sections[index].title != "其它" else {
            throw RepositoryError.validation("其它分類不可刪除")
        }

        let fallback = ensureOtherSection(now: now)
        let offset = firstPositionForSection(fallback.id) - 1
        for itemIndex in snapshot.items.indices where snapshot.items[itemIndex].sectionId == id && snapshot.items[itemIndex].deletedAt == nil {
            snapshot.items[itemIndex].sectionId = fallback.id
            snapshot.items[itemIndex].position += offset
            snapshot.items[itemIndex].updatedAt = now
        }

        snapshot.sections[index].deletedAt = now
        try persist()
        return fallback
    }

    @discardableResult
    func createItem(sectionId: String, name: String, content: String, now: Int64 = Clock.nowMillis()) throws -> ClipItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else {
            throw RepositoryError.validation("項目名稱與內容不可空白")
        }
        guard activeSections.contains(where: { $0.id == sectionId }) else {
            throw RepositoryError.notFound("找不到分類")
        }

        let item = ClipItem(
            id: UUID().uuidString,
            sectionId: sectionId,
            name: trimmedName,
            content: trimmedContent,
            metadata: nil,
            position: firstPositionForSection(sectionId) - 1,
            updatedAt: now,
            deletedAt: nil
        )
        snapshot.items.append(item)
        try persist()
        return item
    }

    @discardableResult
    func updateItem(id: String, sectionId: String, name: String, content: String, now: Int64 = Clock.nowMillis()) throws -> ClipItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else {
            throw RepositoryError.validation("項目名稱與內容不可空白")
        }
        guard activeSections.contains(where: { $0.id == sectionId }) else {
            throw RepositoryError.notFound("找不到分類")
        }
        guard let index = snapshot.items.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw RepositoryError.notFound("找不到項目")
        }

        let oldSectionId = snapshot.items[index].sectionId
        snapshot.items[index].sectionId = sectionId
        snapshot.items[index].name = trimmedName
        snapshot.items[index].content = trimmedContent
        if sectionId != oldSectionId {
            snapshot.items[index].position = firstPositionForSection(sectionId) - 1
        }
        snapshot.items[index].updatedAt = now
        snapshot.items[index].deletedAt = nil
        try persist()
        return snapshot.items[index]
    }

    func moveItem(id: String, sectionId: String, now: Int64 = Clock.nowMillis()) throws {
        guard activeSections.contains(where: { $0.id == sectionId }) else {
            throw RepositoryError.notFound("找不到分類")
        }
        guard let index = snapshot.items.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw RepositoryError.notFound("找不到項目")
        }

        snapshot.items[index].sectionId = sectionId
        snapshot.items[index].position = firstPositionForSection(sectionId) - 1
        snapshot.items[index].updatedAt = now
        snapshot.items[index].deletedAt = nil
        try persist()
    }

    func deleteItem(id: String, now: Int64 = Clock.nowMillis()) throws {
        guard let index = snapshot.items.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        snapshot.items[index].deletedAt = now
        try persist()
    }

    @discardableResult
    func createOptimizer(title: String, placement: OptimizerPlacement, affixText: String, now: Int64 = Clock.nowMillis()) throws -> PromptOptimizer {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAffixText = affixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedAffixText.isEmpty else {
            throw RepositoryError.validation("優化器名稱與內容不可空白")
        }

        let optimizer = PromptOptimizer(
            id: UUID().uuidString,
            title: uniqueActiveTitle(trimmedTitle, in: snapshot.optimizers.map { ($0.id, $0.title, $0.deletedAt) }),
            placement: placement,
            affixText: trimmedAffixText,
            position: nextPosition(snapshot.optimizers.map(\.position)),
            updatedAt: now,
            deletedAt: nil
        )
        snapshot.optimizers.append(optimizer)
        try persist()
        return optimizer
    }

    @discardableResult
    func updateOptimizer(id: String, title: String, placement: OptimizerPlacement, affixText: String, now: Int64 = Clock.nowMillis()) throws -> PromptOptimizer {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAffixText = affixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedAffixText.isEmpty else {
            throw RepositoryError.validation("優化器名稱與內容不可空白")
        }
        guard let index = snapshot.optimizers.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw RepositoryError.notFound("找不到優化器")
        }

        snapshot.optimizers[index].title = uniqueActiveTitle(trimmedTitle, excludedId: id, in: snapshot.optimizers.map { ($0.id, $0.title, $0.deletedAt) })
        snapshot.optimizers[index].placement = placement
        snapshot.optimizers[index].affixText = trimmedAffixText
        snapshot.optimizers[index].updatedAt = now
        snapshot.optimizers[index].deletedAt = nil
        try persist()
        return snapshot.optimizers[index]
    }

    func deleteOptimizer(id: String, now: Int64 = Clock.nowMillis()) throws {
        guard let index = snapshot.optimizers.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        snapshot.optimizers[index].deletedAt = now
        try persist()
    }

    @discardableResult
    func createMemoDocument(title: String, content: String, copyableRanges: [CopyableRange], now: Int64 = Clock.nowMillis()) throws -> MemoDocument {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw RepositoryError.validation("文件標題不可空白")
        }

        let document = MemoDocument(
            id: UUID().uuidString,
            title: uniqueActiveTitle(trimmedTitle, in: snapshot.memoDocuments.map { ($0.id, $0.title, $0.deletedAt) }),
            content: content,
            copyableRanges: TextRangeHelpers.normalize(copyableRanges, content: content),
            position: nextPosition(snapshot.memoDocuments.map(\.position)),
            updatedAt: now,
            deletedAt: nil
        )
        snapshot.memoDocuments.append(document)
        try persist()
        return document
    }

    @discardableResult
    func updateMemoDocument(id: String, title: String, content: String, copyableRanges: [CopyableRange], now: Int64 = Clock.nowMillis()) throws -> MemoDocument {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw RepositoryError.validation("文件標題不可空白")
        }
        guard let index = snapshot.memoDocuments.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw RepositoryError.notFound("找不到文件")
        }

        snapshot.memoDocuments[index].title = uniqueActiveTitle(trimmedTitle, excludedId: id, in: snapshot.memoDocuments.map { ($0.id, $0.title, $0.deletedAt) })
        snapshot.memoDocuments[index].content = content
        snapshot.memoDocuments[index].copyableRanges = TextRangeHelpers.normalize(copyableRanges, content: content)
        snapshot.memoDocuments[index].updatedAt = now
        snapshot.memoDocuments[index].deletedAt = nil
        try persist()
        return snapshot.memoDocuments[index]
    }

    func deleteMemoDocument(id: String, now: Int64 = Clock.nowMillis()) throws {
        guard let index = snapshot.memoDocuments.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        snapshot.memoDocuments[index].deletedAt = now
        try persist()
    }

    func applyRemoteChanges(_ changes: SyncChanges, serverTime: Int64) throws {
        for section in changes.sections {
            applyRemoteSection(section)
        }
        for item in changes.items {
            applyRemoteItem(item)
        }
        for optimizer in changes.optimizers {
            applyRemoteOptimizer(optimizer)
        }
        for document in changes.memoDocuments {
            applyRemoteMemoDocument(document)
        }
        snapshot.lastSyncAt = serverTime
        try persist()
    }

    func resetAll() throws {
        snapshot = ClipBaseSnapshot()
        try persist()
    }

    func exportCSVRows() -> [CSVRow] {
        var rows: [CSVRow] = []
        for section in activeSections {
            for item in activeItems(in: section.id) {
                if let metadata = item.metadata, metadata.hasPrefix("建立時間：") {
                    rows.append(CSVRow(section: section.title, subsection: item.name, field: "訊息", value: item.content))
                    rows.append(CSVRow(section: section.title, subsection: item.name, field: "建立時間", value: String(metadata.dropFirst("建立時間：".count))))
                    continue
                }

                let split = splitItemName(item.name)
                rows.append(CSVRow(section: section.title, subsection: split.subsection, field: split.field, value: item.content))
            }
        }
        return rows
    }

    func importCSVRows(_ rows: [CSVRow], now: Int64 = Clock.nowMillis()) throws {
        var sectionOrder: [String] = []
        var regularItemsBySection: [String: [(name: String, content: String, metadata: String?)]] = [:]
        var customGroups: [String: (section: String, name: String, message: String?, createdAt: String?)] = [:]
        var customOrder: [String] = []

        for row in rows where !row.section.isEmpty {
            if !sectionOrder.contains(row.section) {
                sectionOrder.append(row.section)
            }

            if !row.subsection.isEmpty, row.field == "建立時間" || row.field == "訊息" {
                let key = "\(row.section)\u{0}\(row.subsection)"
                if !customOrder.contains(key) {
                    customOrder.append(key)
                }
                var group = customGroups[key] ?? (section: row.section, name: row.subsection, message: nil, createdAt: nil)
                if row.field == "建立時間" {
                    group.createdAt = row.value
                } else {
                    group.message = row.value
                }
                customGroups[key] = group
                continue
            }

            let itemName = row.subsection.isEmpty ? row.field : "\(row.subsection) / \(row.field)"
            regularItemsBySection[row.section, default: []].append((name: itemName, content: row.value, metadata: nil))
        }

        var usedSectionIds = Set<String>()
        var desiredItems: [(sectionId: String, name: String, content: String, metadata: String?, position: Int)] = []

        for (sectionIndex, title) in sectionOrder.enumerated() {
            let sectionId: String
            if let existingIndex = snapshot.sections.firstIndex(where: { $0.title == title && !usedSectionIds.contains($0.id) }) {
                snapshot.sections[existingIndex].position = sectionIndex
                snapshot.sections[existingIndex].updatedAt = now
                snapshot.sections[existingIndex].deletedAt = nil
                sectionId = snapshot.sections[existingIndex].id
            } else {
                let section = ClipSection(id: UUID().uuidString, title: title, position: sectionIndex, updatedAt: now, deletedAt: nil)
                snapshot.sections.append(section)
                sectionId = section.id
            }
            usedSectionIds.insert(sectionId)

            let groupedItems = customOrder
                .compactMap { customGroups[$0] }
                .filter { $0.section == title }
                .map { group in
                    (
                        name: group.name,
                        content: group.message ?? "",
                        metadata: group.createdAt.map { "建立時間：\($0)" }
                    )
                }
            let items = (regularItemsBySection[title] ?? []) + groupedItems
            for (itemIndex, item) in items.enumerated() {
                desiredItems.append((sectionId: sectionId, name: item.name, content: item.content, metadata: item.metadata, position: itemIndex))
            }
        }

        for index in snapshot.sections.indices where snapshot.sections[index].deletedAt == nil && !usedSectionIds.contains(snapshot.sections[index].id) {
            if snapshot.sections[index].title == "其它" {
                continue
            }
            snapshot.sections[index].deletedAt = now
        }

        var usedItemIds = Set<String>()
        for item in desiredItems {
            if let existingIndex = snapshot.items.firstIndex(where: {
                $0.sectionId == item.sectionId &&
                $0.name == item.name &&
                !usedItemIds.contains($0.id)
            }) {
                snapshot.items[existingIndex].content = item.content
                snapshot.items[existingIndex].metadata = item.metadata
                snapshot.items[existingIndex].position = item.position
                snapshot.items[existingIndex].updatedAt = now
                snapshot.items[existingIndex].deletedAt = nil
                usedItemIds.insert(snapshot.items[existingIndex].id)
            } else {
                let newItem = ClipItem(
                    id: UUID().uuidString,
                    sectionId: item.sectionId,
                    name: item.name,
                    content: item.content,
                    metadata: item.metadata,
                    position: item.position,
                    updatedAt: now,
                    deletedAt: nil
                )
                snapshot.items.append(newItem)
                usedItemIds.insert(newItem.id)
            }
        }

        for index in snapshot.items.indices where snapshot.items[index].deletedAt == nil && !usedItemIds.contains(snapshot.items[index].id) {
            snapshot.items[index].deletedAt = now
        }

        try persist()
    }

    func exportBackup(now: Int64 = Clock.nowMillis()) -> ClipBaseBackup {
        ClipBaseBackup(
            version: 1,
            exportedAt: now,
            changes: SyncChanges(
                sections: snapshot.sections.sorted(by: sortSection),
                items: snapshot.items.sorted(by: sortItem),
                optimizers: snapshot.optimizers.sorted(by: sortOptimizer),
                memoDocuments: snapshot.memoDocuments.sorted(by: sortMemo)
            )
        )
    }

    func restoreBackup(_ backup: ClipBaseBackup) throws {
        guard backup.version == 1 else {
            throw RepositoryError.validation("備份檔格式不正確")
        }

        for section in backup.changes.sections where section.id.isEmpty || section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RepositoryError.validation("備份檔包含無效分類資料")
        }
        let sectionIds = Set(backup.changes.sections.map(\.id))
        for item in backup.changes.items where item.id.isEmpty || item.sectionId.isEmpty || item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sectionIds.contains(item.sectionId) {
            throw RepositoryError.validation("備份檔包含無效項目資料")
        }
        for optimizer in backup.changes.optimizers where optimizer.id.isEmpty || optimizer.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RepositoryError.validation("備份檔包含無效優化器資料")
        }
        for document in backup.changes.memoDocuments where document.id.isEmpty || document.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RepositoryError.validation("備份檔包含無效備忘文件資料")
        }

        snapshot = ClipBaseSnapshot(
            sections: backup.changes.sections,
            items: backup.changes.items,
            optimizers: backup.changes.optimizers,
            memoDocuments: backup.changes.memoDocuments.map { document in
                var normalized = document
                normalized.copyableRanges = TextRangeHelpers.normalize(document.copyableRanges, content: document.content)
                return normalized
            },
            lastSyncAt: 0
        )
        try persist()
    }

    private func applyRemoteSection(_ change: ClipSection) {
        guard !change.id.isEmpty, !change.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard shouldApplyRemote(id: change.id, remoteTime: change.effectiveTime, in: snapshot.sections) else {
            return
        }

        let updatedAt = normalizedTimestamp(change.updatedAt)
        let deletedAt = normalizedNullableTimestamp(change.deletedAt)
        let existingIndex = snapshot.sections.firstIndex(where: { $0.id == change.id })

        if let deletedAt {
            if let existingIndex, snapshot.sections[existingIndex].deletedAt == nil, snapshot.sections[existingIndex].title != "其它" {
                moveActiveItems(from: change.id, toOtherAt: deletedAt)
            }
            let title = existingIndex.map { snapshot.sections[$0].title } ?? change.title
            let section = ClipSection(id: change.id, title: title, position: change.position, updatedAt: updatedAt, deletedAt: deletedAt)
            upsert(section, in: &snapshot.sections)
            return
        }

        let title = uniqueActiveTitle(change.title, excludedId: change.id, in: snapshot.sections.map { ($0.id, $0.title, $0.deletedAt) })
        upsert(ClipSection(id: change.id, title: title, position: change.position, updatedAt: updatedAt, deletedAt: nil), in: &snapshot.sections)
    }

    private func applyRemoteItem(_ change: ClipItem) {
        guard !change.id.isEmpty, !change.sectionId.isEmpty, !change.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard shouldApplyRemote(id: change.id, remoteTime: change.effectiveTime, in: snapshot.items) else {
            return
        }

        let updatedAt = normalizedTimestamp(change.updatedAt)
        let deletedAt = normalizedNullableTimestamp(change.deletedAt)
        let targetSectionId = resolveActiveSectionId(change.sectionId, now: max(updatedAt, deletedAt ?? 0))
        upsert(
            ClipItem(
                id: change.id,
                sectionId: targetSectionId,
                name: change.name,
                content: change.content,
                metadata: change.metadata,
                position: change.position,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            ),
            in: &snapshot.items
        )
    }

    private func applyRemoteOptimizer(_ change: PromptOptimizer) {
        guard !change.id.isEmpty, !change.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard shouldApplyRemote(id: change.id, remoteTime: change.effectiveTime, in: snapshot.optimizers) else {
            return
        }

        let title = uniqueActiveTitle(change.title, excludedId: change.id, in: snapshot.optimizers.map { ($0.id, $0.title, $0.deletedAt) })
        upsert(
            PromptOptimizer(
                id: change.id,
                title: title,
                placement: change.placement,
                affixText: change.affixText,
                position: change.position,
                updatedAt: normalizedTimestamp(change.updatedAt),
                deletedAt: normalizedNullableTimestamp(change.deletedAt)
            ),
            in: &snapshot.optimizers
        )
    }

    private func applyRemoteMemoDocument(_ change: MemoDocument) {
        guard !change.id.isEmpty, !change.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard shouldApplyRemote(id: change.id, remoteTime: change.effectiveTime, in: snapshot.memoDocuments) else {
            return
        }

        let title = uniqueActiveTitle(change.title, excludedId: change.id, in: snapshot.memoDocuments.map { ($0.id, $0.title, $0.deletedAt) })
        upsert(
            MemoDocument(
                id: change.id,
                title: title,
                content: change.content,
                copyableRanges: TextRangeHelpers.normalize(change.copyableRanges, content: change.content),
                position: change.position,
                updatedAt: normalizedTimestamp(change.updatedAt),
                deletedAt: normalizedNullableTimestamp(change.deletedAt)
            ),
            in: &snapshot.memoDocuments
        )
    }

    private func ensureOtherSection(now: Int64) -> ClipSection {
        if let active = snapshot.sections.first(where: { $0.title == "其它" && $0.deletedAt == nil }) {
            return active
        }
        if let index = snapshot.sections.firstIndex(where: { $0.title == "其它" }) {
            snapshot.sections[index].updatedAt = now
            snapshot.sections[index].deletedAt = nil
            return snapshot.sections[index]
        }

        let section = ClipSection(
            id: UUID().uuidString,
            title: "其它",
            position: nextPosition(snapshot.sections.map(\.position)),
            updatedAt: now,
            deletedAt: nil
        )
        snapshot.sections.append(section)
        return section
    }

    private func resolveActiveSectionId(_ sectionId: String, now: Int64) -> String {
        if snapshot.sections.contains(where: { $0.id == sectionId && $0.deletedAt == nil }) {
            return sectionId
        }
        return ensureOtherSection(now: now).id
    }

    private func moveActiveItems(from sectionId: String, toOtherAt now: Int64) {
        let fallback = ensureOtherSection(now: now)
        let offset = firstPositionForSection(fallback.id) - 1
        for itemIndex in snapshot.items.indices where snapshot.items[itemIndex].sectionId == sectionId && snapshot.items[itemIndex].deletedAt == nil {
            snapshot.items[itemIndex].sectionId = fallback.id
            snapshot.items[itemIndex].position += offset
            snapshot.items[itemIndex].updatedAt = now
        }
    }

    private func firstPositionForSection(_ sectionId: String) -> Int {
        snapshot.items
            .filter { $0.sectionId == sectionId && $0.deletedAt == nil }
            .map(\.position)
            .min() ?? 0
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.clipBase.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from fileURL: URL) throws -> ClipBaseSnapshot {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.clipBase.decode(ClipBaseSnapshot.self, from: data)
    }

    private static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("ClipBase", isDirectory: true)
            .appendingPathComponent("clipbase-state.json")
    }
}

enum RepositoryError: LocalizedError, Equatable {
    case validation(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message), .notFound(let message):
            return message
        }
    }
}

private protocol SyncRecord: Identifiable {
    var id: String { get }
    var effectiveTime: Int64 { get }
}

extension ClipSection: SyncRecord {}
extension ClipItem: SyncRecord {}
extension PromptOptimizer: SyncRecord {}
extension MemoDocument: SyncRecord {}

private func shouldApplyRemote<T: SyncRecord>(id: String, remoteTime: Int64, in records: [T]) -> Bool {
    guard let local = records.first(where: { $0.id == id }) else {
        return true
    }
    return remoteTime > local.effectiveTime
}

private func upsert<T: Identifiable>(_ value: T, in records: inout [T]) where T.ID == String {
    if let index = records.firstIndex(where: { $0.id == value.id }) {
        records[index] = value
    } else {
        records.append(value)
    }
}

private func sortPositionTitle(_ leftPosition: Int, _ leftTitle: String, _ rightPosition: Int, _ rightTitle: String) -> Bool {
    if leftPosition == rightPosition {
        return leftTitle.localizedStandardCompare(rightTitle) == .orderedAscending
    }
    return leftPosition < rightPosition
}

private func sortSection(_ left: ClipSection, _ right: ClipSection) -> Bool {
    sortPositionTitle(left.position, left.title, right.position, right.title)
}

private func sortItem(_ left: ClipItem, _ right: ClipItem) -> Bool {
    sortPositionTitle(left.position, left.name, right.position, right.name)
}

private func sortOptimizer(_ left: PromptOptimizer, _ right: PromptOptimizer) -> Bool {
    sortPositionTitle(left.position, left.title, right.position, right.title)
}

private func sortMemo(_ left: MemoDocument, _ right: MemoDocument) -> Bool {
    sortPositionTitle(left.position, left.title, right.position, right.title)
}

private func nextPosition(_ positions: [Int]) -> Int {
    (positions.max() ?? -1) + 1
}

private func uniqueActiveTitle(_ proposedTitle: String, excludedId: String? = nil, in records: [(id: String, title: String, deletedAt: Int64?)]) -> String {
    func exists(_ title: String) -> Bool {
        records.contains { record in
            record.deletedAt == nil &&
            record.title == title &&
            record.id != excludedId
        }
    }

    guard exists(proposedTitle) else {
        return proposedTitle
    }

    var index = 2
    while exists("\(proposedTitle) (\(index))") {
        index += 1
    }
    return "\(proposedTitle) (\(index))"
}

private func normalizedTimestamp(_ value: Int64) -> Int64 {
    value > 0 ? value : Clock.nowMillis()
}

private func normalizedNullableTimestamp(_ value: Int64?) -> Int64? {
    guard let value, value > 0 else { return nil }
    return value
}

private func splitItemName(_ name: String) -> (subsection: String, field: String) {
    let separator = " / "
    guard name.contains(separator) else {
        return ("", name)
    }
    let parts = name.components(separatedBy: separator)
    return (parts.first ?? "", parts.dropFirst().joined(separator: separator))
}
