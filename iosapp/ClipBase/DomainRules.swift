import Foundation

enum DomainRules {
    static func nowMilliseconds() -> Milliseconds {
        Milliseconds(Date().timeIntervalSince1970 * 1000)
    }

    static func effectiveTime(updatedAt: Milliseconds, deletedAt: Milliseconds?) -> Milliseconds {
        max(updatedAt, deletedAt ?? 0)
    }

    static func mergedPrompt(input: String, optimizer: PromptOptimizer) -> String {
        let affixText = optimizer.affixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return affixText
        }

        switch optimizer.placement {
        case .prefix:
            return [affixText, trimmedInput].filter { !$0.isEmpty }.joined(separator: "\n\n")
        case .suffix:
            return [trimmedInput, affixText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }

    static func normalizeCopyableRanges(_ ranges: [CopyableRange], content: String) -> [CopyableRange] {
        let length = normalizeLineEndings(content).utf16.count
        let sorted = ranges
            .filter { $0.start >= 0 && $0.start < $0.end && $0.end <= length }
            .sorted { left, right in
                left.start == right.start ? left.end < right.end : left.start < right.start
            }

        var merged: [CopyableRange] = []
        for range in sorted {
            guard let previous = merged.last else {
                merged.append(range)
                continue
            }
            if range.start <= previous.end {
                merged[merged.count - 1].end = max(previous.end, range.end)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    static func splitMemoText(content: String, ranges: [CopyableRange]) -> [[MemoTextSegment]] {
        let normalized = normalizeLineEndings(content)
        let nsText = normalized as NSString
        let normalizedRanges = normalizeCopyableRanges(ranges, content: normalized)

        return paragraphRanges(in: normalized).map { paragraph in
            let paragraphRanges = normalizedRanges
                .map { CopyableRange(start: max($0.start, paragraph.start), end: min($0.end, paragraph.end)) }
                .filter { $0.start < $0.end }
            var cursor = paragraph.start
            var segments: [MemoTextSegment] = []

            for range in paragraphRanges {
                if cursor < range.start {
                    let text = nsText.substring(with: NSRange(location: cursor, length: range.start - cursor))
                    segments.append(MemoTextSegment(text: text, isCopyable: false))
                }
                let text = nsText.substring(with: NSRange(location: range.start, length: range.end - range.start))
                segments.append(MemoTextSegment(text: text, isCopyable: true))
                cursor = range.end
            }

            if cursor < paragraph.end {
                let text = nsText.substring(with: NSRange(location: cursor, length: paragraph.end - cursor))
                segments.append(MemoTextSegment(text: text, isCopyable: false))
            }

            return segments.filter { !$0.text.isEmpty }
        }
    }

    static func copyableRange(content: String, selectedRange: NSRange) -> CopyableRange? {
        let normalized = normalizeLineEndings(content)
        let nsText = normalized as NSString
        let length = nsText.length
        var start = max(0, min(selectedRange.location, length))
        var end = max(start, min(selectedRange.location + selectedRange.length, length))

        while start < end, isWhitespace(nsText.character(at: start)) {
            start += 1
        }
        while end > start, isWhitespace(nsText.character(at: end - 1)) {
            end -= 1
        }

        return start < end ? CopyableRange(start: start, end: end) : nil
    }

    static func validSectionSelection(current: String?, sections: [ClipSection]) -> String? {
        guard let current, sections.contains(where: { $0.id == current }) else {
            return nil
        }
        return current
    }

    static func normalizeLineEndings(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func isWhitespace(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(value)) else {
            return false
        }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func paragraphRanges(in content: String) -> [CopyableRange] {
        let nsText = content as NSString
        let length = nsText.length
        var ranges: [CopyableRange] = []
        var index = 0

        while index < length {
            while index < length, isWhitespace(nsText.character(at: index)) {
                index += 1
            }
            guard index < length else {
                break
            }

            let start = index
            var end = length
            var scan = index
            while scan < length {
                if nsText.character(at: scan) == 10 {
                    var next = scan + 1
                    while next < length, nsText.character(at: next) != 10, isWhitespace(nsText.character(at: next)) {
                        next += 1
                    }
                    if next < length, nsText.character(at: next) == 10 {
                        end = scan
                        index = next + 1
                        break
                    }
                }
                scan += 1
            }
            if scan >= length {
                index = length
            }

            while end > start, isWhitespace(nsText.character(at: end - 1)) {
                end -= 1
            }
            if start < end {
                ranges.append(CopyableRange(start: start, end: end))
            }
        }

        return ranges
    }
}

extension ClipBaseSnapshot {
    var activeSections: [ClipSection] {
        sections
            .filter { $0.deletedAt == nil }
            .sorted { left, right in
                left.position == right.position ? left.title < right.title : left.position < right.position
            }
    }

    var activeOptimizers: [PromptOptimizer] {
        optimizers
            .filter { $0.deletedAt == nil }
            .sorted { left, right in
                left.position == right.position ? left.title < right.title : left.position < right.position
            }
    }

    var activeMemoDocuments: [MemoDocument] {
        memoDocuments
            .filter { $0.deletedAt == nil }
            .sorted { left, right in
                left.position == right.position ? left.title < right.title : left.position < right.position
            }
    }

    func activeItems(in sectionId: String) -> [ClipItem] {
        items
            .filter { $0.sectionId == sectionId && $0.deletedAt == nil }
            .sorted { left, right in
                left.position == right.position ? left.name < right.name : left.position < right.position
            }
    }

    func localChanges(after timestamp: Milliseconds) -> SyncChanges {
        SyncChanges(
            sections: sections.filter { DomainRules.effectiveTime(updatedAt: $0.updatedAt, deletedAt: $0.deletedAt) > timestamp },
            items: items.filter { DomainRules.effectiveTime(updatedAt: $0.updatedAt, deletedAt: $0.deletedAt) > timestamp },
            optimizers: optimizers.filter { DomainRules.effectiveTime(updatedAt: $0.updatedAt, deletedAt: $0.deletedAt) > timestamp },
            memoDocuments: memoDocuments.filter { DomainRules.effectiveTime(updatedAt: $0.updatedAt, deletedAt: $0.deletedAt) > timestamp }
        )
    }

    mutating func createSection(title: String, now: Milliseconds = DomainRules.nowMilliseconds()) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClipBaseDomainError.validation("分類名稱不可空白")
        }

        let id = UUID().uuidString
        sections.append(ClipSection(
            id: id,
            title: uniqueTitle(trimmed, in: sections.map(\.title)),
            position: nextSectionPosition(),
            updatedAt: now,
            deletedAt: nil
        ))
        return id
    }

    mutating func deleteSection(id: String, now: Milliseconds = DomainRules.nowMilliseconds()) throws -> String {
        guard let sectionIndex = sections.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到分類")
        }
        guard sections[sectionIndex].title != "其它" else {
            throw ClipBaseDomainError.protectedSection
        }

        let fallbackId = ensureOtherSection(now: now)
        var position = firstPositionForSection(fallbackId)
        for index in items.indices where items[index].sectionId == id && items[index].deletedAt == nil {
            position -= 1
            items[index].sectionId = fallbackId
            items[index].position = position
            items[index].updatedAt = max(items[index].updatedAt, now)
            items[index].deletedAt = nil
        }

        sections[sectionIndex].deletedAt = now
        return fallbackId
    }

    mutating func applyRemoteChanges(_ changes: SyncChanges) {
        changes.sections.forEach { applyRemoteSection($0) }
        changes.items.forEach { applyRemoteItem($0) }
        changes.optimizers.forEach { applyRemoteOptimizer($0) }
        changes.memoDocuments.forEach { applyRemoteMemoDocument($0) }
    }

    mutating func updateSection(id: String, title: String, now: Milliseconds = DomainRules.nowMilliseconds()) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClipBaseDomainError.validation("分類名稱不可空白")
        }
        guard let index = sections.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到分類")
        }
        sections[index].title = uniqueTitle(trimmed, in: sections.filter { $0.id != id }.map(\.title))
        sections[index].updatedAt = now
        sections[index].deletedAt = nil
    }

    mutating func createItem(sectionId: String, name: String, content: String, now: Milliseconds = DomainRules.nowMilliseconds()) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty && !trimmedContent.isEmpty else {
            throw ClipBaseDomainError.validation("項目名稱與內容不可空白")
        }
        guard sections.contains(where: { $0.id == sectionId && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到分類")
        }

        let id = UUID().uuidString
        items.append(ClipItem(
            id: id,
            sectionId: sectionId,
            name: trimmedName,
            content: trimmedContent,
            metadata: nil,
            position: firstPositionForSection(sectionId) - 1,
            updatedAt: now,
            deletedAt: nil
        ))
        return id
    }

    mutating func updateItem(id: String, sectionId: String, name: String, content: String, now: Milliseconds = DomainRules.nowMilliseconds()) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty && !trimmedContent.isEmpty else {
            throw ClipBaseDomainError.validation("項目名稱與內容不可空白")
        }
        guard sections.contains(where: { $0.id == sectionId && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到分類")
        }
        guard let index = items.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到項目")
        }

        if items[index].sectionId != sectionId {
            items[index].position = firstPositionForSection(sectionId) - 1
        }
        items[index].sectionId = sectionId
        items[index].name = trimmedName
        items[index].content = trimmedContent
        items[index].updatedAt = now
        items[index].deletedAt = nil
    }

    mutating func moveItem(id: String, to sectionId: String, now: Milliseconds = DomainRules.nowMilliseconds()) throws {
        guard sections.contains(where: { $0.id == sectionId && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到分類")
        }
        guard let index = items.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到項目")
        }

        items[index].sectionId = sectionId
        items[index].position = firstPositionForSection(sectionId) - 1
        items[index].updatedAt = now
        items[index].deletedAt = nil
    }

    mutating func deleteItem(id: String, now: Milliseconds = DomainRules.nowMilliseconds()) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        items[index].deletedAt = now
    }

    mutating func createOptimizer(
        title: String,
        placement: PromptPlacement,
        affixText: String,
        now: Milliseconds = DomainRules.nowMilliseconds()
    ) throws -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAffix = affixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty && !trimmedAffix.isEmpty else {
            throw ClipBaseDomainError.validation("優化器名稱與內容不可空白")
        }

        let id = UUID().uuidString
        optimizers.append(PromptOptimizer(
            id: id,
            title: uniqueTitle(trimmedTitle, in: optimizers.map(\.title)),
            placement: placement,
            affixText: trimmedAffix,
            position: nextOptimizerPosition(),
            updatedAt: now,
            deletedAt: nil
        ))
        return id
    }

    mutating func updateOptimizer(
        id: String,
        title: String,
        placement: PromptPlacement,
        affixText: String,
        now: Milliseconds = DomainRules.nowMilliseconds()
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAffix = affixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty && !trimmedAffix.isEmpty else {
            throw ClipBaseDomainError.validation("優化器名稱與內容不可空白")
        }
        guard let index = optimizers.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到優化器")
        }

        optimizers[index].title = uniqueTitle(trimmedTitle, in: optimizers.filter { $0.id != id }.map(\.title))
        optimizers[index].placement = placement
        optimizers[index].affixText = trimmedAffix
        optimizers[index].updatedAt = now
        optimizers[index].deletedAt = nil
    }

    mutating func deleteOptimizer(id: String, now: Milliseconds = DomainRules.nowMilliseconds()) {
        guard let index = optimizers.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        optimizers[index].deletedAt = now
    }

    mutating func createMemoDocument(
        title: String,
        content: String,
        copyableRanges: [CopyableRange],
        now: Milliseconds = DomainRules.nowMilliseconds()
    ) throws -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ClipBaseDomainError.validation("文件標題不可空白")
        }

        let normalizedContent = DomainRules.normalizeLineEndings(content)
        let id = UUID().uuidString
        memoDocuments.append(MemoDocument(
            id: id,
            title: uniqueTitle(trimmedTitle, in: memoDocuments.map(\.title)),
            content: normalizedContent,
            copyableRanges: DomainRules.normalizeCopyableRanges(copyableRanges, content: normalizedContent),
            position: nextMemoPosition(),
            updatedAt: now,
            deletedAt: nil
        ))
        return id
    }

    mutating func updateMemoDocument(
        id: String,
        title: String,
        content: String,
        copyableRanges: [CopyableRange],
        now: Milliseconds = DomainRules.nowMilliseconds()
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw ClipBaseDomainError.validation("文件標題不可空白")
        }
        guard let index = memoDocuments.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw ClipBaseDomainError.notFound("找不到文件")
        }

        let normalizedContent = DomainRules.normalizeLineEndings(content)
        memoDocuments[index].title = uniqueTitle(trimmedTitle, in: memoDocuments.filter { $0.id != id }.map(\.title))
        memoDocuments[index].content = normalizedContent
        memoDocuments[index].copyableRanges = DomainRules.normalizeCopyableRanges(copyableRanges, content: normalizedContent)
        memoDocuments[index].updatedAt = now
        memoDocuments[index].deletedAt = nil
    }

    mutating func deleteMemoDocument(id: String, now: Milliseconds = DomainRules.nowMilliseconds()) {
        guard let index = memoDocuments.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            return
        }
        memoDocuments[index].deletedAt = now
    }

    mutating func importCSVRows(_ rows: [CSVRow], now: Milliseconds = DomainRules.nowMilliseconds()) {
        var sectionOrder: [String] = []
        var regularItemsBySection: [String: [(name: String, content: String, metadata: String?)]] = [:]
        var customGroups: [String: (section: String, name: String, message: String?, createdAt: String?)] = [:]
        var customOrder: [String] = []

        for row in rows where !row.section.isEmpty {
            if !sectionOrder.contains(row.section) {
                sectionOrder.append(row.section)
            }

            if !row.subsection.isEmpty && (row.field == "建立時間" || row.field == "訊息") {
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
            if let existingIndex = sections.firstIndex(where: { $0.title == title && !usedSectionIds.contains($0.id) }) {
                sections[existingIndex].position = sectionIndex
                sections[existingIndex].updatedAt = now
                sections[existingIndex].deletedAt = nil
                sectionId = sections[existingIndex].id
            } else {
                let newSection = ClipSection(
                    id: UUID().uuidString,
                    title: uniqueTitle(title, in: sections.map(\.title)),
                    position: sectionIndex,
                    updatedAt: now,
                    deletedAt: nil
                )
                sections.append(newSection)
                sectionId = newSection.id
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
            let importedItems = (regularItemsBySection[title] ?? []) + groupedItems
            for (itemIndex, item) in importedItems.enumerated() {
                desiredItems.append((
                    sectionId: sectionId,
                    name: item.name,
                    content: item.content,
                    metadata: item.metadata,
                    position: itemIndex
                ))
            }
        }

        for index in sections.indices where sections[index].deletedAt == nil && !usedSectionIds.contains(sections[index].id) {
            if sections[index].title != "其它" {
                sections[index].deletedAt = now
            }
        }

        var usedItemIds = Set<String>()
        for item in desiredItems {
            if let existingIndex = items.firstIndex(where: {
                $0.sectionId == item.sectionId &&
                $0.name == item.name &&
                !usedItemIds.contains($0.id)
            }) {
                items[existingIndex].content = item.content
                items[existingIndex].metadata = item.metadata
                items[existingIndex].position = item.position
                items[existingIndex].updatedAt = now
                items[existingIndex].deletedAt = nil
                usedItemIds.insert(items[existingIndex].id)
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
                items.append(newItem)
                usedItemIds.insert(newItem.id)
            }
        }

        for index in items.indices where items[index].deletedAt == nil && !usedItemIds.contains(items[index].id) {
            items[index].deletedAt = now
        }
    }

    private mutating func applyRemoteSection(_ remote: ClipSection) {
        let remoteTime = DomainRules.effectiveTime(updatedAt: remote.updatedAt, deletedAt: remote.deletedAt)
        if let index = sections.firstIndex(where: { $0.id == remote.id }) {
            let local = sections[index]
            let localTime = DomainRules.effectiveTime(updatedAt: local.updatedAt, deletedAt: local.deletedAt)
            guard remoteTime > localTime else {
                return
            }
            if remote.deletedAt != nil && local.deletedAt == nil && local.title != "其它" {
                moveActiveItems(from: remote.id, to: ensureOtherSection(now: remoteTime), now: remoteTime)
            }
            sections[index] = remote
        } else {
            sections.append(remote)
        }
    }

    private mutating func applyRemoteItem(_ remote: ClipItem) {
        let remoteTime = DomainRules.effectiveTime(updatedAt: remote.updatedAt, deletedAt: remote.deletedAt)
        if let index = items.firstIndex(where: { $0.id == remote.id }) {
            let local = items[index]
            let localTime = DomainRules.effectiveTime(updatedAt: local.updatedAt, deletedAt: local.deletedAt)
            guard remoteTime > localTime else {
                return
            }
            var resolved = remote
            resolved.sectionId = resolveActiveSectionId(remote.sectionId, now: remoteTime)
            items[index] = resolved
        } else {
            var resolved = remote
            resolved.sectionId = resolveActiveSectionId(remote.sectionId, now: remoteTime)
            items.append(resolved)
        }
    }

    private mutating func applyRemoteOptimizer(_ remote: PromptOptimizer) {
        let remoteTime = DomainRules.effectiveTime(updatedAt: remote.updatedAt, deletedAt: remote.deletedAt)
        if let index = optimizers.firstIndex(where: { $0.id == remote.id }) {
            let local = optimizers[index]
            let localTime = DomainRules.effectiveTime(updatedAt: local.updatedAt, deletedAt: local.deletedAt)
            guard remoteTime > localTime else {
                return
            }
            optimizers[index] = remote
        } else {
            optimizers.append(remote)
        }
    }

    private mutating func applyRemoteMemoDocument(_ remote: MemoDocument) {
        let remoteTime = DomainRules.effectiveTime(updatedAt: remote.updatedAt, deletedAt: remote.deletedAt)
        var normalized = remote
        normalized.content = DomainRules.normalizeLineEndings(remote.content)
        normalized.copyableRanges = DomainRules.normalizeCopyableRanges(remote.copyableRanges, content: normalized.content)

        if let index = memoDocuments.firstIndex(where: { $0.id == remote.id }) {
            let local = memoDocuments[index]
            let localTime = DomainRules.effectiveTime(updatedAt: local.updatedAt, deletedAt: local.deletedAt)
            guard remoteTime > localTime else {
                return
            }
            memoDocuments[index] = normalized
        } else {
            memoDocuments.append(normalized)
        }
    }

    private mutating func ensureOtherSection(now: Milliseconds) -> String {
        if let index = sections.firstIndex(where: { $0.title == "其它" }) {
            sections[index].deletedAt = nil
            sections[index].updatedAt = now
            return sections[index].id
        }

        let id = UUID().uuidString
        sections.append(ClipSection(id: id, title: "其它", position: nextSectionPosition(), updatedAt: now, deletedAt: nil))
        return id
    }

    private mutating func resolveActiveSectionId(_ sectionId: String, now: Milliseconds) -> String {
        if sections.contains(where: { $0.id == sectionId && $0.deletedAt == nil }) {
            return sectionId
        }
        return ensureOtherSection(now: now)
    }

    private mutating func moveActiveItems(from sectionId: String, to fallbackId: String, now: Milliseconds) {
        var position = firstPositionForSection(fallbackId)
        for index in items.indices where items[index].sectionId == sectionId && items[index].deletedAt == nil {
            position -= 1
            items[index].sectionId = fallbackId
            items[index].position = position
            items[index].updatedAt = max(items[index].updatedAt, now)
        }
    }

    private func uniqueTitle(_ proposedTitle: String, in existingTitles: [String]) -> String {
        guard existingTitles.contains(proposedTitle) else {
            return proposedTitle
        }

        var index = 2
        while existingTitles.contains("\(proposedTitle) (\(index))") {
            index += 1
        }
        return "\(proposedTitle) (\(index))"
    }

    private func nextSectionPosition() -> Int {
        (sections.map(\.position).max() ?? -1) + 1
    }

    private func nextOptimizerPosition() -> Int {
        (optimizers.map(\.position).max() ?? -1) + 1
    }

    private func nextMemoPosition() -> Int {
        (memoDocuments.map(\.position).max() ?? -1) + 1
    }

    private func firstPositionForSection(_ sectionId: String) -> Int {
        items
            .filter { $0.sectionId == sectionId && $0.deletedAt == nil }
            .map(\.position)
            .min() ?? 0
    }
}
