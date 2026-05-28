import XCTest
@testable import ClipBase

final class ClipBaseCoreTests: XCTestCase {
    func testDefaultServerURLUsesProductionClipBase() {
        XCTAssertEqual(ClipBaseSnapshot.empty.baseURL, "https://clipbase.thelonesomeera.com/")
    }

    func testPromptOptimizerMergeMatchesWebRules() {
        let optimizer = PromptOptimizer(
            id: "optimizer-1",
            title: "Prefix",
            placement: .prefix,
            affixText: "固定提示詞",
            position: 0,
            updatedAt: 100,
            deletedAt: nil
        )

        XCTAssertEqual(DomainRules.mergedPrompt(input: "", optimizer: optimizer), "固定提示詞")
        XCTAssertEqual(DomainRules.mergedPrompt(input: "  原始內容  ", optimizer: optimizer), "固定提示詞\n\n原始內容")

        var suffix = optimizer
        suffix.placement = .suffix
        suffix.affixText = "固定後綴"
        XCTAssertEqual(DomainRules.mergedPrompt(input: "原始內容", optimizer: suffix), "原始內容\n\n固定後綴")
    }

    func testMemoRangesAreNormalizedWithWebRules() {
        let content = "abcde"
        let ranges = [
            CopyableRange(start: 3, end: 8),
            CopyableRange(start: 1, end: 2),
            CopyableRange(start: 2, end: 4),
            CopyableRange(start: 4, end: 4),
            CopyableRange(start: 1, end: 2)
        ]

        XCTAssertEqual(
            DomainRules.normalizeCopyableRanges(ranges, content: content),
            [CopyableRange(start: 1, end: 4)]
        )
    }

    func testDeletingSectionMovesActiveItemsToOtherAndKeepsTombstone() throws {
        var snapshot = ClipBaseSnapshot.empty
        let sectionId = try snapshot.createSection(title: "帳號", now: 100)
        let item = ClipItem(
            id: "item-1",
            sectionId: sectionId,
            name: "Email",
            content: "user@example.com",
            metadata: nil,
            position: 0,
            updatedAt: 110,
            deletedAt: nil
        )
        snapshot.items.append(item)

        let fallbackId = try snapshot.deleteSection(id: sectionId, now: 200)

        XCTAssertEqual(snapshot.sections.first(where: { $0.id == sectionId })?.deletedAt, 200)
        XCTAssertEqual(snapshot.items.first(where: { $0.id == "item-1" })?.sectionId, fallbackId)
        XCTAssertEqual(snapshot.sections.first(where: { $0.id == fallbackId })?.title, "其它")
        XCTAssertThrowsError(try snapshot.deleteSection(id: fallbackId, now: 250)) { error in
            XCTAssertEqual(error as? ClipBaseDomainError, .protectedSection)
        }
    }

    func testRemoteChangesUseRowLevelLastWriteWins() {
        var snapshot = ClipBaseSnapshot.empty
        snapshot.sections = [
            ClipSection(id: "section-1", title: "Local", position: 0, updatedAt: 500, deletedAt: nil)
        ]

        snapshot.applyRemoteChanges(SyncChanges(sections: [
            ClipSection(id: "section-1", title: "Old Remote", position: 0, updatedAt: 400, deletedAt: nil)
        ]))
        XCTAssertEqual(snapshot.sections.first?.title, "Local")

        snapshot.applyRemoteChanges(SyncChanges(sections: [
            ClipSection(id: "section-1", title: "Deleted Remote", position: 0, updatedAt: 450, deletedAt: 600)
        ]))
        XCTAssertEqual(snapshot.sections.first?.deletedAt, 600)
    }

    func testLocalChangesIncludeRecordsAfterLastSync() {
        var snapshot = ClipBaseSnapshot.empty
        snapshot.sections = [
            ClipSection(id: "old", title: "Old", position: 0, updatedAt: 100, deletedAt: nil),
            ClipSection(id: "new", title: "New", position: 1, updatedAt: 300, deletedAt: nil),
            ClipSection(id: "deleted", title: "Deleted", position: 2, updatedAt: 100, deletedAt: 350)
        ]

        let changes = snapshot.localChanges(after: 200)
        XCTAssertEqual(changes.sections.map(\.id), ["new", "deleted"])
    }

    func testCSVExportNeutralizesSpreadsheetFormulas() {
        let section = ClipSection(id: "section-1", title: "帳號", position: 0, updatedAt: 100, deletedAt: nil)
        let item = ClipItem(
            id: "item-1",
            sectionId: "section-1",
            name: "Token",
            content: "  =IMPORTXML(\"https://example.com\")",
            metadata: nil,
            position: 0,
            updatedAt: 100,
            deletedAt: nil
        )

        let csv = CSVSupport.export(sections: [section]) { _ in [item] }

        XCTAssertTrue(csv.contains(",Token,\"'  =IMPORTXML(\"\"https://example.com\"\")\""))
    }
}
